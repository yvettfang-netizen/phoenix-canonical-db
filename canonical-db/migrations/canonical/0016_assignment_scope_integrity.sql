BEGIN;

-- V16-F1 (EV-1 8.1 / BC: an advisor acts only through an *active* case
-- assignment): a CLOSED case, or an assignment that is not ACTIVE, no longer
-- grants authority over the case's Education Application or Identity Case.
-- V16-F2 (EV-4 1.2): a case grants authority over its resource only when the
-- resource belongs to the case's family and subject. A case may be created
-- before the resource exists (EV-4 E4-6); the check applies once it exists.
-- This function backs the advisor write checks (0009/0011), the read RLS
-- policies (0004) and the access decision API (0006).
CREATE OR REPLACE FUNCTION casework.has_active_advisor_assignment(p_resource_kind text, p_resource_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, casework, education, identity
RETURN EXISTS (
  SELECT 1
  FROM casework.cases c
  JOIN casework.advisor_assignments a ON a.case_id = c.case_id
  WHERE c.family_id = auth.current_family_id()
    AND c.status IN ('OPEN','PAUSED')
    AND c.resource_kind = p_resource_kind AND c.resource_id = p_resource_id
    AND a.advisor_person_id = auth.current_actor_person_id()
    AND a.lifecycle_status = 'ACTIVE'
    AND a.valid_from <= transaction_timestamp() AND a.valid_until > transaction_timestamp()
    AND a.revoked_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM education.applications x
       WHERE c.resource_kind = 'EDUCATION_APPLICATION' AND x.application_id = c.resource_id
         AND (x.family_id <> c.family_id OR x.student_person_id <> c.subject_person_id))
    AND NOT EXISTS (
      SELECT 1 FROM identity.cases x
       WHERE c.resource_kind = 'IDENTITY_CASE' AND x.identity_case_id = c.resource_id
         AND (x.family_id <> c.family_id OR x.subject_person_id <> c.subject_person_id))
);

-- V16-F2: reject a case whose existing resource belongs to another family or subject.
CREATE OR REPLACE FUNCTION casework.create_case(p_id uuid,p_family_id uuid,p_subject_id uuid,
  p_title text,p_resource_kind text,p_resource_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,casework,education,identity,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_id) AND core.person_in_current_family(p_subject_id)
      AND length(btrim(p_title)) BETWEEN 1 AND 300
      AND ((p_resource_kind IS NULL AND p_resource_id IS NULL)
        OR (p_resource_kind IN ('EDUCATION_APPLICATION','IDENTITY_CASE') AND core.is_uuid_v7(p_resource_id)))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CASEWORK_CASE',p_id,false,'SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  IF (p_resource_kind='EDUCATION_APPLICATION' AND EXISTS (
        SELECT 1 FROM education.applications x WHERE x.application_id=p_resource_id
           AND (x.family_id<>p_family_id OR x.student_person_id<>p_subject_id)))
     OR (p_resource_kind='IDENTITY_CASE' AND EXISTS (
        SELECT 1 FROM identity.cases x WHERE x.identity_case_id=p_resource_id
           AND (x.family_id<>p_family_id OR x.subject_person_id<>p_subject_id))) THEN
    RETURN audit.record_write_decision('CREATE','CASEWORK_CASE',p_id,false,'RESOURCE_FAMILY_OR_SUBJECT_MISMATCH');
  END IF;
  IF EXISTS(SELECT 1 FROM casework.cases WHERE case_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','CASEWORK_CASE',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO casework.cases(case_id,family_id,subject_person_id,title,status,resource_kind,resource_id,created_by_principal_id)
    VALUES(p_id,p_family_id,p_subject_id,p_title,'OPEN',p_resource_kind,p_resource_id,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','CASEWORK_CASE',p_id,true,'SERVICE_CREATED');
END $fn$;

-- V16-F2: a resource created after its case (EV-4 E4-6) must match that case.
CREATE FUNCTION casework.reject_resource_case_mismatch() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, casework, education, identity
AS $fn$
DECLARE v_id uuid; v_family uuid; v_subject uuid; v_kind text;
BEGIN
  IF TG_TABLE_SCHEMA = 'education' THEN
    v_kind := 'EDUCATION_APPLICATION'; v_id := NEW.application_id;
    v_family := NEW.family_id; v_subject := NEW.student_person_id;
  ELSE
    v_kind := 'IDENTITY_CASE'; v_id := NEW.identity_case_id;
    v_family := NEW.family_id; v_subject := NEW.subject_person_id;
  END IF;
  IF EXISTS (SELECT 1 FROM casework.cases c
              WHERE c.resource_kind = v_kind AND c.resource_id = v_id
                AND (c.family_id <> v_family OR c.subject_person_id <> v_subject)) THEN
    RAISE EXCEPTION 'CASE_RESOURCE_FAMILY_OR_SUBJECT_MISMATCH';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER education_application_case_match BEFORE INSERT ON education.applications
FOR EACH ROW EXECUTE FUNCTION casework.reject_resource_case_mismatch();
CREATE TRIGGER identity_case_case_match BEFORE INSERT ON identity.cases
FOR EACH ROW EXECUTE FUNCTION casework.reject_resource_case_mismatch();

-- V16-F3 (D-10: default deny with audit): a duplicate active assignment or
-- guardian authority returns an audited denial instead of a unique-index error.
-- Expired rows still flagged ACTIVE are left to the 0008 insert trigger, which
-- marks them EXPIRED before the new row is written.
CREATE OR REPLACE FUNCTION casework.create_advisor_assignment(p_id uuid,p_case_id uuid,p_advisor_id uuid,
  p_valid_until timestamptz) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,casework,audit AS $fn$
DECLARE v_case casework.cases%ROWTYPE;
BEGIN
  SELECT * INTO v_case FROM casework.cases WHERE case_id=p_case_id;
  IF (FOUND AND auth.is_internal_service() AND v_case.family_id=auth.current_family_id()
      AND v_case.status IN ('OPEN','PAUSED') AND core.is_uuid_v7(p_id)
      AND p_valid_until>clock_timestamp()
      AND EXISTS(SELECT 1 FROM auth.principals WHERE person_id=p_advisor_id
        AND principal_kind='ADVISOR' AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ASSIGN','ADVISOR_ASSIGNMENT',p_id,false,'SERVICE_CASE_ADVISOR_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM casework.advisor_assignments WHERE assignment_id=p_id) THEN
    RETURN audit.record_write_decision('ASSIGN','ADVISOR_ASSIGNMENT',p_id,false,'ALREADY_EXISTS');
  END IF;
  IF EXISTS(SELECT 1 FROM casework.advisor_assignments WHERE case_id=p_case_id
      AND advisor_person_id=p_advisor_id AND lifecycle_status='ACTIVE'
      AND revoked_at IS NULL AND valid_until>clock_timestamp()) THEN
    RETURN audit.record_write_decision('ASSIGN','ADVISOR_ASSIGNMENT',p_id,false,'ALREADY_ACTIVE');
  END IF;
  INSERT INTO casework.advisor_assignments(assignment_id,case_id,advisor_person_id,valid_from,valid_until,assigned_by_principal_id)
    VALUES(p_id,p_case_id,p_advisor_id,clock_timestamp(),p_valid_until,auth.current_principal_id());
  RETURN audit.record_write_decision('ASSIGN','ADVISOR_ASSIGNMENT',p_id,true,'SERVICE_ASSIGNED');
END $fn$;

CREATE OR REPLACE FUNCTION core.create_guardian_authority(p_id uuid,p_family_id uuid,p_guardian_id uuid,
  p_subject_id uuid,p_level text,p_scope text,p_until timestamptz,p_evidence_ref text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_id) AND p_guardian_id<>p_subject_id
      AND core.person_in_current_family(p_guardian_id)
      AND core.person_in_current_family(p_subject_id)
      AND p_level='VERIFIED' AND p_scope IN ('GENERAL','EDUCATION','IDENTITY')
      AND p_until>clock_timestamp()
      AND length(btrim(p_evidence_ref)) BETWEEN 1 AND 500) IS NOT TRUE THEN
    RETURN audit.record_write_decision('VERIFY','GUARDIAN_AUTHORITY',p_id,false,'SERVICE_EVIDENCE_OR_FAMILY_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM core.guardian_authorities WHERE authority_id=p_id) THEN
    RETURN audit.record_write_decision('VERIFY','GUARDIAN_AUTHORITY',p_id,false,'ALREADY_EXISTS');
  END IF;
  IF EXISTS(SELECT 1 FROM core.guardian_authorities WHERE family_id=p_family_id
      AND guardian_person_id=p_guardian_id AND subject_person_id=p_subject_id
      AND scope=p_scope AND lifecycle_status='ACTIVE'
      AND revoked_at IS NULL AND valid_until>clock_timestamp()) THEN
    RETURN audit.record_write_decision('VERIFY','GUARDIAN_AUTHORITY',p_id,false,'ALREADY_ACTIVE');
  END IF;
  INSERT INTO core.guardian_authorities(authority_id,family_id,guardian_person_id,subject_person_id,
    evidence_level,scope,valid_from,valid_until,evidence_ref,verified_by_principal_id)
    VALUES(p_id,p_family_id,p_guardian_id,p_subject_id,p_level,p_scope,clock_timestamp(),p_until,
      p_evidence_ref,auth.current_principal_id());
  RETURN audit.record_write_decision('VERIFY','GUARDIAN_AUTHORITY',p_id,true,'SERVICE_VERIFIED');
END $fn$;

REVOKE EXECUTE ON FUNCTION casework.reject_resource_case_mismatch() FROM PUBLIC;

COMMIT;
