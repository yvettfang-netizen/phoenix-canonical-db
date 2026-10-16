BEGIN;

-- D-12: append-only civil-capacity evidence; absence means UNVERIFIED.
CREATE TABLE core.civil_capacity_history (
  capacity_record_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(capacity_record_id)),
  person_id uuid NOT NULL REFERENCES core.people,
  capacity_status text NOT NULL CHECK (capacity_status IN ('ADULT_VERIFIED','MINOR_VERIFIED','UNVERIFIED')),
  evidence_ref text NOT NULL CHECK (length(btrim(evidence_ref)) BETWEEN 1 AND 500),
  verified_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  verified_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX civil_capacity_latest ON core.civil_capacity_history(person_id, verified_at DESC, capacity_record_id DESC);
ALTER TABLE core.civil_capacity_history ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION core.reject_civil_capacity_mutation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
BEGIN
  RAISE EXCEPTION 'CIVIL_CAPACITY_HISTORY_IMMUTABLE';
END
$fn$;
CREATE TRIGGER civil_capacity_immutable BEFORE UPDATE OR DELETE ON core.civil_capacity_history
FOR EACH ROW EXECUTE FUNCTION core.reject_civil_capacity_mutation();

CREATE FUNCTION core.current_civil_capacity(p_person_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, core
RETURN coalesce((SELECT h.capacity_status FROM core.civil_capacity_history h
  WHERE h.person_id=p_person_id ORDER BY h.verified_at DESC,h.capacity_record_id DESC LIMIT 1),'UNVERIFIED');

CREATE FUNCTION core.set_civil_capacity(
  p_record_id uuid,p_person_id uuid,p_capacity_status text,p_evidence_ref text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND core.is_uuid_v7(p_record_id)
      AND core.person_in_current_family(p_person_id)
      AND p_capacity_status IN ('ADULT_VERIFIED','MINOR_VERIFIED','UNVERIFIED')
      AND length(btrim(p_evidence_ref)) BETWEEN 1 AND 500) IS NOT TRUE THEN
    RETURN audit.record_write_decision('VERIFY','CIVIL_CAPACITY',p_record_id,false,'SERVICE_FAMILY_OR_EVIDENCE_DENIED');
  END IF;
  INSERT INTO core.civil_capacity_history(capacity_record_id,person_id,capacity_status,
    evidence_ref,verified_by_principal_id,verified_at)
    VALUES (p_record_id,p_person_id,p_capacity_status,p_evidence_ref,
      auth.current_principal_id(),clock_timestamp()) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN
    RETURN audit.record_write_decision('VERIFY','CIVIL_CAPACITY',p_record_id,false,'ALREADY_EXISTS');
  END IF;
  RETURN audit.record_write_decision('VERIFY','CIVIL_CAPACITY',p_record_id,true,'SERVICE_VERIFIED');
END
$fn$;

CREATE OR REPLACE FUNCTION consent.actor_can_grant(
  p_subject_person_id uuid, p_purpose text, p_data_class text
) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent
RETURN coalesce(
  p_purpose IN ('DOCUMENT_READ','EDUCATION_CASE','IDENTITY_CASE')
  AND p_data_class IN ('GENERAL','EDUCATION','IDENTITY_SENSITIVE')
  AND (p_purpose = 'DOCUMENT_READ'
       OR (p_purpose = 'EDUCATION_CASE' AND p_data_class = 'EDUCATION')
       OR (p_purpose = 'IDENTITY_CASE' AND p_data_class = 'IDENTITY_SENSITIVE'))
  AND auth.write_context_is_live()
  AND auth.current_channel() = 'FAMILY'
  AND core.current_actor_is_family_member()
  AND core.person_in_current_family(p_subject_person_id)
  AND ((auth.current_actor_person_id() = p_subject_person_id
        AND core.current_civil_capacity(p_subject_person_id) = 'ADULT_VERIFIED')
       OR core.has_verified_guardian_authority(p_subject_person_id,
         CASE p_data_class WHEN 'EDUCATION' THEN 'EDUCATION'
           WHEN 'IDENTITY_SENSITIVE' THEN 'IDENTITY' ELSE 'GENERAL' END)), false);

-- Withdrawal narrows access and remains available to an unverified subject.
CREATE OR REPLACE FUNCTION consent.withdraw_grant(p_consent_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, audit
AS $fn$
DECLARE v_grant consent.grants%ROWTYPE;
BEGIN
  SELECT * INTO v_grant FROM consent.grants WHERE consent_id=p_consent_id FOR UPDATE;
  IF (FOUND AND v_grant.family_id=auth.current_family_id()
      AND v_grant.status='ACTIVE' AND v_grant.expires_at>clock_timestamp()
      AND core.actor_can_manage_subject(v_grant.subject_person_id,
        CASE v_grant.data_class WHEN 'EDUCATION' THEN 'EDUCATION'
          WHEN 'IDENTITY_SENSITIVE' THEN 'IDENTITY' ELSE 'GENERAL' END)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('WITHDRAW','CONSENT',p_consent_id,false,'GRANTOR_AUTHORITY_OR_STATE_DENIED');
  END IF;
  UPDATE consent.grants SET status='WITHDRAWN', withdrawn_at=clock_timestamp()
   WHERE consent_id=p_consent_id;
  RETURN audit.record_write_decision('WITHDRAW','CONSENT',p_consent_id,true,'AUTHORIZED_WITHDRAWAL');
END
$fn$;

-- D-13: official facts are append-only and can only be recorded by a service
-- or an assigned advisor with the case-specific consent.
CREATE FUNCTION education.can_record_official_fact(p_application_id uuid,p_student_person_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, consent, casework, education
RETURN coalesce(auth.write_context_is_live() AND (
  auth.is_internal_service()
  OR (auth.current_channel()='ADVISOR'
    AND casework.has_active_advisor_assignment('EDUCATION_APPLICATION',p_application_id)
    AND consent.has_active_consent(p_student_person_id,'EDUCATION_CASE','EDUCATION'))),false);

CREATE FUNCTION identity.can_record_official_fact(p_identity_case_id uuid,p_subject_person_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, consent, casework, identity
RETURN coalesce(auth.write_context_is_live() AND (
  auth.is_internal_service()
  OR (auth.current_channel()='ADVISOR'
    AND casework.has_active_advisor_assignment('IDENTITY_CASE',p_identity_case_id)
    AND consent.has_active_consent(p_subject_person_id,'IDENTITY_CASE','IDENTITY_SENSITIVE'))),false);

CREATE FUNCTION education.record_external_fact(
  p_fact_id uuid,p_application_id uuid,p_fact_kind text,
  p_source_name text,p_external_reference text,p_observed_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, education, audit
AS $fn$
DECLARE v_app education.applications%ROWTYPE;
BEGIN
  SELECT * INTO v_app FROM education.applications WHERE application_id=p_application_id;
  IF (FOUND AND v_app.family_id=auth.current_family_id()
      AND education.can_record_official_fact(p_application_id,v_app.student_person_id)
      AND core.is_uuid_v7(p_fact_id)
      AND p_fact_kind IN ('OFFICIAL_RECEIPT','DECISION')
      AND length(btrim(p_source_name)) BETWEEN 1 AND 300
      AND length(btrim(p_external_reference)) BETWEEN 1 AND 300
      AND p_observed_at <= clock_timestamp()) IS NOT TRUE THEN
    RETURN audit.record_write_decision('RECORD','EDUCATION_EXTERNAL_FACT',p_fact_id,false,'OFFICIAL_FACT_AUTHORITY_OR_INPUT_DENIED');
  END IF;
  INSERT INTO education.external_facts(fact_id,application_id,fact_kind,source_name,external_reference,observed_at)
    VALUES (p_fact_id,p_application_id,p_fact_kind,p_source_name,p_external_reference,p_observed_at)
    ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN
    RETURN audit.record_write_decision('RECORD','EDUCATION_EXTERNAL_FACT',p_fact_id,false,'ALREADY_EXISTS');
  END IF;
  RETURN audit.record_write_decision('RECORD','EDUCATION_EXTERNAL_FACT',p_fact_id,true,'OFFICIAL_FACT_RECORDED');
END
$fn$;

CREATE FUNCTION identity.record_external_fact(
  p_fact_id uuid,p_identity_case_id uuid,p_fact_kind text,
  p_source_name text,p_external_reference text,p_observed_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, identity, audit
AS $fn$
DECLARE v_case identity.cases%ROWTYPE;
BEGIN
  SELECT * INTO v_case FROM identity.cases WHERE identity_case_id=p_identity_case_id;
  IF (FOUND AND v_case.family_id=auth.current_family_id()
      AND identity.can_record_official_fact(p_identity_case_id,v_case.subject_person_id)
      AND core.is_uuid_v7(p_fact_id)
      AND p_fact_kind IN ('OFFICIAL_RECEIPT','DECISION')
      AND length(btrim(p_source_name)) BETWEEN 1 AND 300
      AND length(btrim(p_external_reference)) BETWEEN 1 AND 300
      AND p_observed_at <= clock_timestamp()) IS NOT TRUE THEN
    RETURN audit.record_write_decision('RECORD','IDENTITY_EXTERNAL_FACT',p_fact_id,false,'OFFICIAL_FACT_AUTHORITY_OR_INPUT_DENIED');
  END IF;
  INSERT INTO identity.external_facts(fact_id,identity_case_id,fact_kind,source_name,external_reference,observed_at)
    VALUES (p_fact_id,p_identity_case_id,p_fact_kind,p_source_name,p_external_reference,p_observed_at)
    ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN
    RETURN audit.record_write_decision('RECORD','IDENTITY_EXTERNAL_FACT',p_fact_id,false,'ALREADY_EXISTS');
  END IF;
  RETURN audit.record_write_decision('RECORD','IDENTITY_EXTERNAL_FACT',p_fact_id,true,'OFFICIAL_FACT_RECORDED');
END
$fn$;

CREATE FUNCTION education.reject_external_fact_mutation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, education
AS $fn$ BEGIN RAISE EXCEPTION 'EDUCATION_EXTERNAL_FACT_IMMUTABLE'; END $fn$;
CREATE TRIGGER education_fact_immutable BEFORE UPDATE OR DELETE ON education.external_facts
FOR EACH ROW EXECUTE FUNCTION education.reject_external_fact_mutation();
CREATE FUNCTION identity.reject_external_fact_mutation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, identity
AS $fn$ BEGIN RAISE EXCEPTION 'IDENTITY_EXTERNAL_FACT_IMMUTABLE'; END $fn$;
CREATE TRIGGER identity_fact_immutable BEFORE UPDATE OR DELETE ON identity.external_facts
FOR EACH ROW EXECUTE FUNCTION identity.reject_external_fact_mutation();

CREATE OR REPLACE FUNCTION education.advance_application(p_application_id uuid,p_next_status text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, education, audit
AS $fn$
DECLARE v_item education.applications%ROWTYPE; v_valid boolean; v_authorized boolean;
BEGIN
  SELECT * INTO v_item FROM education.applications WHERE application_id=p_application_id FOR UPDATE;
  v_authorized := FOUND AND v_item.family_id=auth.current_family_id() AND
    CASE WHEN p_next_status='DECIDED' THEN
      education.can_record_official_fact(v_item.application_id,v_item.student_person_id)
    ELSE education.can_write_application(v_item.application_id,v_item.student_person_id) END;
  IF v_authorized IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','EDUCATION_APPLICATION',p_application_id,false,'FAMILY_ADVISOR_OR_CONSENT_DENIED');
  END IF;
  v_valid := (v_item.status='DRAFT' AND p_next_status IN ('READY','WITHDRAWN'))
    OR (v_item.status='READY' AND p_next_status IN ('SUBMITTED','WITHDRAWN'))
    OR (v_item.status='SUBMITTED' AND p_next_status IN ('DECIDED','WITHDRAWN'));
  IF v_valid IS NOT TRUE OR (p_next_status='DECIDED' AND NOT EXISTS (
      SELECT 1 FROM education.external_facts f WHERE f.application_id=p_application_id
        AND f.fact_kind='DECISION')) THEN
    RETURN audit.record_write_decision('ADVANCE','EDUCATION_APPLICATION',p_application_id,false,'STATE_OR_DECISION_FACT_DENIED');
  END IF;
  UPDATE education.applications SET status=p_next_status WHERE application_id=p_application_id;
  RETURN audit.record_write_decision('ADVANCE','EDUCATION_APPLICATION',p_application_id,true,'STATE_TRANSITION_ALLOWED');
END
$fn$;

CREATE OR REPLACE FUNCTION identity.advance_case(p_identity_case_id uuid,p_next_status text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, identity, audit
AS $fn$
DECLARE v_item identity.cases%ROWTYPE; v_valid boolean; v_authorized boolean;
BEGIN
  SELECT * INTO v_item FROM identity.cases WHERE identity_case_id=p_identity_case_id FOR UPDATE;
  v_authorized := FOUND AND v_item.family_id=auth.current_family_id() AND
    CASE WHEN p_next_status='RESOLVED' THEN
      identity.can_record_official_fact(v_item.identity_case_id,v_item.subject_person_id)
    ELSE identity.can_write_case(v_item.identity_case_id,v_item.subject_person_id) END;
  IF v_authorized IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,false,'FAMILY_ADVISOR_OR_CONSENT_DENIED');
  END IF;
  v_valid := (v_item.status='DRAFT' AND p_next_status='EVIDENCE_PENDING')
    OR (v_item.status='EVIDENCE_PENDING' AND p_next_status='UNDER_REVIEW')
    OR (v_item.status='UNDER_REVIEW' AND p_next_status IN ('RESOLVED','CLOSED'));
  IF v_valid IS NOT TRUE OR (p_next_status='RESOLVED' AND NOT EXISTS (
      SELECT 1 FROM identity.external_facts f WHERE f.identity_case_id=p_identity_case_id
        AND f.fact_kind='DECISION')) THEN
    RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,false,'STATE_OR_DECISION_FACT_DENIED');
  END IF;
  UPDATE identity.cases SET status=p_next_status WHERE identity_case_id=p_identity_case_id;
  RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,true,'STATE_TRANSITION_ALLOWED');
END
$fn$;

-- D-14: confirmation is a separate, immutable step while status remains PREPARING.
ALTER TABLE docs.submission_manifests ADD COLUMN confirmed_at timestamptz;
ALTER TABLE docs.submission_manifests ADD CONSTRAINT manifest_confirmation_consistency
  CHECK ((confirmed_by IS NULL) = (confirmed_at IS NULL));
ALTER TABLE docs.submission_manifests ADD CONSTRAINT manifest_distinct_actors
  CHECK (submitted_by IS NULL OR confirmed_by <> submitted_by);

CREATE FUNCTION core.actor_can_confirm_subject(p_subject_person_id uuid,p_scope text)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core
RETURN coalesce(auth.write_context_is_live()
  AND auth.current_channel()='FAMILY'
  AND core.current_actor_is_family_member()
  AND core.person_in_current_family(p_subject_person_id)
  AND ((auth.current_actor_person_id()=p_subject_person_id
        AND core.current_civil_capacity(p_subject_person_id)='ADULT_VERIFIED')
       OR core.has_verified_guardian_authority(p_subject_person_id,p_scope)),false);

CREATE FUNCTION docs.reject_confirmed_item_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, docs
AS $fn$
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') AND EXISTS (
      SELECT 1 FROM docs.submission_manifests m WHERE m.submission_id=OLD.submission_id
        AND m.confirmed_by IS NOT NULL) THEN
    RAISE EXCEPTION 'CONFIRMED_MANIFEST_ITEMS_IMMUTABLE';
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') AND EXISTS (
      SELECT 1 FROM docs.submission_manifests m WHERE m.submission_id=NEW.submission_id
        AND m.confirmed_by IS NOT NULL) THEN
    RAISE EXCEPTION 'CONFIRMED_MANIFEST_ITEMS_IMMUTABLE';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER confirmed_manifest_items_immutable BEFORE INSERT OR UPDATE OR DELETE ON docs.submission_items
FOR EACH ROW EXECUTE FUNCTION docs.reject_confirmed_item_change();

CREATE OR REPLACE FUNCTION docs.protect_submission_manifest() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, docs
AS $fn$
BEGIN
  IF TG_OP='DELETE' OR OLD.status='SUBMITTED' THEN
    RAISE EXCEPTION 'SUBMITTED_MANIFEST_IMMUTABLE';
  END IF;
  IF OLD.confirmed_by IS NOT NULL AND (
      NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by
      OR NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at
      OR NEW.status IS DISTINCT FROM 'SUBMITTED'
      OR NEW.family_id IS DISTINCT FROM OLD.family_id
      OR NEW.subject_person_id IS DISTINCT FROM OLD.subject_person_id
      OR NEW.target_kind IS DISTINCT FROM OLD.target_kind
      OR NEW.target_id IS DISTINCT FROM OLD.target_id
      OR NEW.prepared_by IS DISTINCT FROM OLD.prepared_by) THEN
    RAISE EXCEPTION 'CONFIRMED_MANIFEST_IMMUTABLE';
  END IF;
  IF NEW.status='SUBMITTED' THEN
    IF NEW.confirmed_by IS NULL OR NEW.confirmed_at IS NULL THEN
      RAISE EXCEPTION 'MANIFEST_CONFIRMATION_REQUIRED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM docs.submission_items WHERE submission_id=NEW.submission_id) THEN
      RAISE EXCEPTION 'SUBMISSION_ITEMS_REQUIRED';
    END IF;
    IF EXISTS (
      SELECT 1 FROM docs.submission_items i
      JOIN docs.document_versions v ON v.version_id=i.version_id
      JOIN docs.documents d ON d.document_id=v.document_id
      WHERE i.submission_id=NEW.submission_id AND d.withdrawn_at IS NOT NULL
    ) THEN RAISE EXCEPTION 'WITHDRAWN_DOCUMENT_NEW_USE_DENIED'; END IF;
  END IF;
  RETURN NEW;
END
$fn$;

CREATE OR REPLACE FUNCTION docs.add_submission_item(
  p_submission_id uuid,p_item_no integer,p_version_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, docs, audit
AS $fn$
DECLARE v_manifest docs.submission_manifests%ROWTYPE; v_digest char(64);
BEGIN
  SELECT * INTO v_manifest FROM docs.submission_manifests WHERE submission_id=p_submission_id FOR UPDATE;
  IF (FOUND AND v_manifest.status='PREPARING' AND v_manifest.confirmed_by IS NULL
      AND docs.can_manage_submission_target(v_manifest.family_id,v_manifest.subject_person_id,
        v_manifest.target_kind,v_manifest.target_id)
      AND p_item_no>0) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD_ITEM','SUBMISSION_MANIFEST',p_submission_id,false,'MANIFEST_OPERATOR_OR_STATE_DENIED');
  END IF;
  SELECT v.content_sha256 INTO v_digest
    FROM docs.document_versions v JOIN docs.documents d ON d.document_id=v.document_id
   WHERE v.version_id=p_version_id AND d.family_id=v_manifest.family_id
     AND d.subject_person_id=v_manifest.subject_person_id AND d.withdrawn_at IS NULL
     AND docs.can_read_document(d.subject_person_id,d.data_class);
  IF v_digest IS NULL OR EXISTS (SELECT 1 FROM docs.submission_items
      WHERE submission_id=p_submission_id AND (item_no=p_item_no OR version_id=p_version_id)) THEN
    RETURN audit.record_write_decision('ADD_ITEM','SUBMISSION_MANIFEST',p_submission_id,false,'DOCUMENT_OR_ITEM_DENIED');
  END IF;
  INSERT INTO docs.submission_items(submission_id,item_no,version_id,pinned_sha256)
    VALUES (p_submission_id,p_item_no,p_version_id,v_digest);
  RETURN audit.record_write_decision('ADD_ITEM','SUBMISSION_MANIFEST',p_submission_id,true,'VERSION_PINNED');
END
$fn$;

CREATE FUNCTION docs.confirm_manifest(p_submission_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, docs, audit
AS $fn$
DECLARE v_manifest docs.submission_manifests%ROWTYPE; v_scope text;
BEGIN
  SELECT * INTO v_manifest FROM docs.submission_manifests WHERE submission_id=p_submission_id FOR UPDATE;
  v_scope := CASE v_manifest.target_kind WHEN 'EDUCATION_APPLICATION' THEN 'EDUCATION'
    WHEN 'IDENTITY_CASE' THEN 'IDENTITY' ELSE NULL END;
  IF (FOUND AND v_manifest.status='PREPARING' AND v_manifest.confirmed_by IS NULL
      AND v_manifest.family_id=auth.current_family_id()
      AND core.actor_can_confirm_subject(v_manifest.subject_person_id,v_scope)
      AND docs.can_manage_submission_target(v_manifest.family_id,v_manifest.subject_person_id,
        v_manifest.target_kind,v_manifest.target_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CONFIRM','SUBMISSION_MANIFEST',p_submission_id,false,'FAMILY_AUTHORITY_OR_STATE_DENIED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM docs.submission_items WHERE submission_id=p_submission_id)
     OR EXISTS (SELECT 1 FROM docs.submission_items i
       JOIN docs.document_versions v ON v.version_id=i.version_id
       JOIN docs.documents d ON d.document_id=v.document_id
       WHERE i.submission_id=p_submission_id AND (d.withdrawn_at IS NOT NULL
         OR d.family_id<>v_manifest.family_id OR d.subject_person_id<>v_manifest.subject_person_id
         OR docs.can_read_document(d.subject_person_id,d.data_class) IS NOT TRUE)) THEN
    RETURN audit.record_write_decision('CONFIRM','SUBMISSION_MANIFEST',p_submission_id,false,'ITEMS_INVALID_OR_WITHDRAWN');
  END IF;
  UPDATE docs.submission_manifests SET confirmed_by=auth.current_actor_person_id(),
    confirmed_at=clock_timestamp() WHERE submission_id=p_submission_id;
  RETURN audit.record_write_decision('CONFIRM','SUBMISSION_MANIFEST',p_submission_id,true,'FAMILY_CONFIRMED');
END
$fn$;

CREATE OR REPLACE FUNCTION docs.submit_manifest(p_submission_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, docs, audit
AS $fn$
DECLARE v_manifest docs.submission_manifests%ROWTYPE; v_service boolean; v_advisor boolean;
BEGIN
  SELECT * INTO v_manifest FROM docs.submission_manifests WHERE submission_id=p_submission_id FOR UPDATE;
  v_service := auth.is_internal_service() AND auth.current_family_id()=v_manifest.family_id;
  v_advisor := auth.current_channel()='ADVISOR' AND
    docs.can_manage_submission_target(v_manifest.family_id,v_manifest.subject_person_id,
      v_manifest.target_kind,v_manifest.target_id);
  IF (FOUND AND v_manifest.status='PREPARING'
      AND v_manifest.confirmed_by IS NOT NULL AND v_manifest.confirmed_at IS NOT NULL
      AND (v_service OR v_advisor)
      AND auth.current_actor_person_id() IS DISTINCT FROM v_manifest.confirmed_by) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,false,'CONFIRMATION_OR_SUBMITTER_DENIED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM docs.submission_items WHERE submission_id=p_submission_id)
     OR EXISTS (SELECT 1 FROM docs.submission_items i
       JOIN docs.document_versions v ON v.version_id=i.version_id
       JOIN docs.documents d ON d.document_id=v.document_id
       WHERE i.submission_id=p_submission_id AND (d.withdrawn_at IS NOT NULL
         OR d.family_id<>v_manifest.family_id OR d.subject_person_id<>v_manifest.subject_person_id
         OR (NOT v_service AND docs.can_read_document(d.subject_person_id,d.data_class) IS NOT TRUE))) THEN
    RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,false,'ITEMS_INVALID_OR_WITHDRAWN');
  END IF;
  UPDATE docs.submission_manifests SET status='SUBMITTED',
    submitted_by=auth.current_actor_person_id(),submitted_at=clock_timestamp()
   WHERE submission_id=p_submission_id;
  RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,true,'SUBMITTED_AFTER_CONFIRMATION');
END
$fn$;

REVOKE EXECUTE ON FUNCTION core.reject_civil_capacity_mutation(),core.current_civil_capacity(uuid),
  core.set_civil_capacity(uuid,uuid,text,text),core.actor_can_confirm_subject(uuid,text),
  education.can_record_official_fact(uuid,uuid),identity.can_record_official_fact(uuid,uuid),
  education.record_external_fact(uuid,uuid,text,text,text,timestamptz),
  identity.record_external_fact(uuid,uuid,text,text,text,timestamptz),
  education.reject_external_fact_mutation(),identity.reject_external_fact_mutation(),
  docs.reject_confirmed_item_change(),docs.confirm_manifest(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.set_civil_capacity(uuid,uuid,text,text),
  education.record_external_fact(uuid,uuid,text,text,text,timestamptz),
  identity.record_external_fact(uuid,uuid,text,text,text,timestamptz),
  docs.confirm_manifest(uuid) TO phoenix_canonical_app;

COMMIT;
