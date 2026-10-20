BEGIN;

ALTER TABLE education.applications
  ADD COLUMN institution_id uuid,
  ADD COLUMN program_id uuid;

CREATE TABLE education.institution (
  institution_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(institution_id)),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 300),
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','INACTIVE')),
  version integer NOT NULL CHECK (version > 0),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE UNIQUE INDEX institution_name_country_version_uq
  ON education.institution (lower(btrim(name)),country_code,version);

CREATE TABLE education.program (
  program_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(program_id)),
  institution_id uuid NOT NULL REFERENCES education.institution,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 300),
  level text NOT NULL CHECK (length(btrim(level)) BETWEEN 1 AND 100),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','INACTIVE')),
  version integer NOT NULL CHECK (version > 0),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE UNIQUE INDEX program_institution_name_level_version_uq
  ON education.program (institution_id,lower(btrim(name)),lower(btrim(level)),version);
CREATE INDEX program_institution_idx ON education.program(institution_id);

ALTER TABLE education.applications
  ADD CONSTRAINT applications_institution_fk FOREIGN KEY (institution_id) REFERENCES education.institution,
  ADD CONSTRAINT applications_program_fk FOREIGN KEY (program_id) REFERENCES education.program;

CREATE TABLE education.academic_record (
  academic_record_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(academic_record_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  student_person_id uuid NOT NULL REFERENCES core.student_profiles(person_id),
  level text NOT NULL CHECK (length(btrim(level)) BETWEEN 1 AND 100),
  school_name text NOT NULL CHECK (length(btrim(school_name)) BETWEEN 1 AND 300),
  graduation_date date,
  evidence_document_id uuid REFERENCES docs.documents,
  recorded_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE INDEX academic_record_student_idx ON education.academic_record(student_person_id);

CREATE TABLE education.score_record (
  score_record_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(score_record_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  student_person_id uuid NOT NULL REFERENCES core.student_profiles(person_id),
  subject text NOT NULL CHECK (length(btrim(subject)) BETWEEN 1 AND 100),
  score numeric(12,4) NOT NULL CHECK (score >= 0),
  exam_date date NOT NULL,
  source text NOT NULL CHECK (length(btrim(source)) BETWEEN 1 AND 200),
  recorded_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE INDEX score_record_student_exam_idx ON education.score_record(student_person_id,exam_date);

CREATE TABLE education.language_test (
  language_test_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(language_test_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  student_person_id uuid NOT NULL REFERENCES core.student_profiles(person_id),
  test_kind text NOT NULL CHECK (length(btrim(test_kind)) BETWEEN 1 AND 100),
  score_json jsonb NOT NULL CHECK (jsonb_typeof(score_json)='object' AND score_json <> '{}'::jsonb),
  test_date date NOT NULL,
  evidence_document_id uuid REFERENCES docs.documents,
  recorded_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE INDEX language_test_student_date_idx ON education.language_test(student_person_id,test_date);

CREATE TABLE education.plan (
  plan_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(plan_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  student_person_id uuid NOT NULL REFERENCES core.student_profiles(person_id),
  goal_text text NOT NULL CHECK (length(btrim(goal_text)) BETWEEN 1 AND 2000),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','COMPLETED','ARCHIVED')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE INDEX education_plan_student_idx ON education.plan(student_person_id);

CREATE TABLE education.plan_target (
  plan_id uuid NOT NULL REFERENCES education.plan,
  target_no integer NOT NULL CHECK (target_no > 0),
  institution_id uuid NOT NULL REFERENCES education.institution,
  program_id uuid NOT NULL REFERENCES education.program,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  PRIMARY KEY (plan_id,target_no),
  UNIQUE (plan_id,institution_id,program_id)
);
CREATE INDEX education_plan_target_plan_idx ON education.plan_target(plan_id);

CREATE FUNCTION education.reject_append_only_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, education
AS $fn$
BEGIN
  RAISE EXCEPTION 'EDUCATION_RECORD_APPEND_ONLY';
END
$fn$;

CREATE TRIGGER institution_append_only BEFORE UPDATE OR DELETE ON education.institution
FOR EACH ROW EXECUTE FUNCTION education.reject_append_only_change();
CREATE TRIGGER program_append_only BEFORE UPDATE OR DELETE ON education.program
FOR EACH ROW EXECUTE FUNCTION education.reject_append_only_change();
CREATE TRIGGER academic_record_append_only BEFORE UPDATE OR DELETE ON education.academic_record
FOR EACH ROW EXECUTE FUNCTION education.reject_append_only_change();
CREATE TRIGGER score_record_append_only BEFORE UPDATE OR DELETE ON education.score_record
FOR EACH ROW EXECUTE FUNCTION education.reject_append_only_change();
CREATE TRIGGER language_test_append_only BEFORE UPDATE OR DELETE ON education.language_test
FOR EACH ROW EXECUTE FUNCTION education.reject_append_only_change();
CREATE TRIGGER plan_target_append_only BEFORE UPDATE OR DELETE ON education.plan_target
FOR EACH ROW EXECUTE FUNCTION education.reject_append_only_change();

CREATE FUNCTION education.validate_student_family() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, core, education
AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM core.family_memberships m
     WHERE m.family_id=NEW.family_id AND m.person_id=NEW.student_person_id
       AND m.valid_from <= NEW.created_at
       AND (m.valid_until IS NULL OR m.valid_until > NEW.created_at)
  ) THEN
    RAISE EXCEPTION 'EDUCATION_STUDENT_FAMILY_MISMATCH';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER academic_record_student_family BEFORE INSERT ON education.academic_record
FOR EACH ROW EXECUTE FUNCTION education.validate_student_family();
CREATE TRIGGER score_record_student_family BEFORE INSERT ON education.score_record
FOR EACH ROW EXECUTE FUNCTION education.validate_student_family();
CREATE TRIGGER language_test_student_family BEFORE INSERT ON education.language_test
FOR EACH ROW EXECUTE FUNCTION education.validate_student_family();
CREATE TRIGGER plan_student_family BEFORE INSERT ON education.plan
FOR EACH ROW EXECUTE FUNCTION education.validate_student_family();

CREATE FUNCTION education.validate_education_evidence() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, docs, education
AS $fn$
BEGIN
  IF NEW.evidence_document_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM docs.documents d
     WHERE d.document_id=NEW.evidence_document_id
       AND d.family_id=NEW.family_id
       AND d.subject_person_id=NEW.student_person_id
       AND d.data_class='EDUCATION'
       AND d.withdrawn_at IS NULL
  ) THEN
    RAISE EXCEPTION 'EDUCATION_EVIDENCE_SUBJECT_OR_CLASS_MISMATCH';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER academic_record_evidence BEFORE INSERT ON education.academic_record
FOR EACH ROW EXECUTE FUNCTION education.validate_education_evidence();
CREATE TRIGGER language_test_evidence BEFORE INSERT ON education.language_test
FOR EACH ROW EXECUTE FUNCTION education.validate_education_evidence();

CREATE FUNCTION education.validate_master_target() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, education
AS $fn$
BEGIN
  IF NEW.institution_id IS NULL AND NEW.program_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.institution_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM education.institution i
       WHERE i.institution_id=NEW.institution_id AND i.status='ACTIVE') THEN
    RAISE EXCEPTION 'EDUCATION_INSTITUTION_NOT_ACTIVE';
  END IF;
  IF NEW.program_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM education.program p
       WHERE p.program_id=NEW.program_id AND p.institution_id=NEW.institution_id
         AND p.status='ACTIVE') THEN
    RAISE EXCEPTION 'EDUCATION_PROGRAM_INSTITUTION_OR_STATUS_INVALID';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER application_master_target BEFORE INSERT OR UPDATE OF institution_id,program_id
ON education.applications FOR EACH ROW EXECUTE FUNCTION education.validate_master_target();

CREATE FUNCTION education.validate_plan_target() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, education
AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM education.program p JOIN education.institution i ON i.institution_id=p.institution_id
     WHERE p.program_id=NEW.program_id AND p.institution_id=NEW.institution_id
       AND p.status='ACTIVE' AND i.status='ACTIVE'
  ) THEN RAISE EXCEPTION 'EDUCATION_PLAN_TARGET_INVALID'; END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER plan_target_master_match BEFORE INSERT ON education.plan_target
FOR EACH ROW EXECUTE FUNCTION education.validate_plan_target();

CREATE FUNCTION education.protect_plan_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, education
AS $fn$
BEGIN
  IF NEW.plan_id IS DISTINCT FROM OLD.plan_id OR NEW.family_id IS DISTINCT FROM OLD.family_id
     OR NEW.student_person_id IS DISTINCT FROM OLD.student_person_id
     OR NEW.goal_text IS DISTINCT FROM OLD.goal_text
     OR NEW.created_by_principal_id IS DISTINCT FROM OLD.created_by_principal_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'EDUCATION_PLAN_FIELDS_IMMUTABLE';
  END IF;
  IF NOT ((OLD.status='DRAFT' AND NEW.status IN ('ACTIVE','ARCHIVED'))
       OR (OLD.status='ACTIVE' AND NEW.status IN ('COMPLETED','ARCHIVED'))
       OR OLD.status=NEW.status) THEN
    RAISE EXCEPTION 'EDUCATION_PLAN_TRANSITION_INVALID';
  END IF;
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END
$fn$;
CREATE TRIGGER protect_plan_update BEFORE UPDATE ON education.plan
FOR EACH ROW EXECUTE FUNCTION education.protect_plan_update();
CREATE TRIGGER plan_delete_denied BEFORE DELETE ON education.plan
FOR EACH ROW EXECUTE FUNCTION education.reject_append_only_change();

CREATE FUNCTION education.can_read_student_record(p_family_id uuid,p_student_person_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, education
RETURN coalesce(
  auth.write_context_is_live() AND auth.current_family_id()=p_family_id
  AND (
    core.actor_can_manage_subject(p_student_person_id,'EDUCATION')
    OR (auth.current_channel()='ADVISOR'
        AND core.can_read_subject_basics(p_student_person_id)
        AND consent.has_active_consent(p_student_person_id,'EDUCATION_CASE','EDUCATION'))
    OR auth.is_internal_service()
  ),false);

CREATE FUNCTION education.can_write_student_record(p_family_id uuid,p_student_person_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, education
RETURN education.can_read_student_record(p_family_id,p_student_person_id);

CREATE FUNCTION education.create_institution_draft(
  p_institution_id uuid,p_name text,p_country_code text,p_version integer
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, education, audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id() IS NULL
      AND core.is_uuid_v7(p_institution_id)
      AND length(btrim(p_name)) BETWEEN 1 AND 300
      AND p_country_code ~ '^[A-Z]{2}$' AND p_version > 0) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_INSTITUTION',p_institution_id,false,'UNBOUND_SERVICE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM education.institution WHERE institution_id=p_institution_id)
     OR EXISTS (SELECT 1 FROM education.institution
                 WHERE lower(btrim(name))=lower(btrim(p_name))
                   AND country_code=p_country_code AND version=p_version) THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_INSTITUTION',p_institution_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO education.institution(institution_id,name,country_code,status,version,created_by_principal_id)
    VALUES (p_institution_id,btrim(p_name),p_country_code,'DRAFT',p_version,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','EDUCATION_INSTITUTION',p_institution_id,true,'DRAFT_CREATED_PENDING_REVIEW');
END
$fn$;

CREATE FUNCTION education.create_program_draft(
  p_program_id uuid,p_institution_id uuid,p_name text,p_level text,p_version integer
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, education, audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id() IS NULL
      AND core.is_uuid_v7(p_program_id) AND p_version > 0
      AND length(btrim(p_name)) BETWEEN 1 AND 300
      AND length(btrim(p_level)) BETWEEN 1 AND 100
      AND EXISTS (SELECT 1 FROM education.institution WHERE institution_id=p_institution_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_PROGRAM',p_program_id,false,'UNBOUND_SERVICE_INSTITUTION_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM education.program WHERE program_id=p_program_id)
     OR EXISTS (SELECT 1 FROM education.program
                 WHERE institution_id=p_institution_id
                   AND lower(btrim(name))=lower(btrim(p_name))
                   AND lower(btrim(level))=lower(btrim(p_level)) AND version=p_version) THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_PROGRAM',p_program_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO education.program(program_id,institution_id,name,level,status,version,created_by_principal_id)
    VALUES (p_program_id,p_institution_id,btrim(p_name),btrim(p_level),'DRAFT',p_version,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','EDUCATION_PROGRAM',p_program_id,true,'DRAFT_CREATED_PENDING_REVIEW');
END
$fn$;

CREATE FUNCTION education.create_academic_record(
  p_id uuid,p_family_id uuid,p_student_person_id uuid,p_level text,p_school_name text,
  p_graduation_date date,p_evidence_document_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, docs, education, audit
AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_id) AND education.can_write_student_record(p_family_id,p_student_person_id)
      AND length(btrim(p_level)) BETWEEN 1 AND 100
      AND length(btrim(p_school_name)) BETWEEN 1 AND 300
      AND (p_evidence_document_id IS NULL OR EXISTS (
        SELECT 1 FROM docs.documents d WHERE d.document_id=p_evidence_document_id
          AND d.family_id=p_family_id AND d.subject_person_id=p_student_person_id
          AND d.data_class='EDUCATION' AND d.withdrawn_at IS NULL))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_ACADEMIC_RECORD',p_id,false,'SUBJECT_AUTHORITY_EVIDENCE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM education.academic_record WHERE academic_record_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_ACADEMIC_RECORD',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO education.academic_record(academic_record_id,family_id,student_person_id,level,school_name,
    graduation_date,evidence_document_id,recorded_by_principal_id)
  VALUES (p_id,p_family_id,p_student_person_id,btrim(p_level),btrim(p_school_name),
    p_graduation_date,p_evidence_document_id,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','EDUCATION_ACADEMIC_RECORD',p_id,true,'AUTHORIZED_CREATE');
END
$fn$;

CREATE FUNCTION education.create_score_record(
  p_id uuid,p_family_id uuid,p_student_person_id uuid,p_subject text,p_score numeric,
  p_exam_date date,p_source text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, education, audit
AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_id) AND education.can_write_student_record(p_family_id,p_student_person_id)
      AND length(btrim(p_subject)) BETWEEN 1 AND 100 AND p_score >= 0
      AND p_exam_date IS NOT NULL AND length(btrim(p_source)) BETWEEN 1 AND 200) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_SCORE_RECORD',p_id,false,'SUBJECT_AUTHORITY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM education.score_record WHERE score_record_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_SCORE_RECORD',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO education.score_record(score_record_id,family_id,student_person_id,subject,score,exam_date,source,recorded_by_principal_id)
  VALUES (p_id,p_family_id,p_student_person_id,btrim(p_subject),p_score,p_exam_date,btrim(p_source),auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','EDUCATION_SCORE_RECORD',p_id,true,'AUTHORIZED_CREATE');
END
$fn$;

CREATE FUNCTION education.create_language_test(
  p_id uuid,p_family_id uuid,p_student_person_id uuid,p_test_kind text,p_score_json jsonb,
  p_test_date date,p_evidence_document_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, docs, education, audit
AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_id) AND education.can_write_student_record(p_family_id,p_student_person_id)
      AND length(btrim(p_test_kind)) BETWEEN 1 AND 100
      AND jsonb_typeof(p_score_json)='object' AND p_score_json<>'{}'::jsonb AND p_test_date IS NOT NULL
      AND (p_evidence_document_id IS NULL OR EXISTS (
        SELECT 1 FROM docs.documents d WHERE d.document_id=p_evidence_document_id
          AND d.family_id=p_family_id AND d.subject_person_id=p_student_person_id
          AND d.data_class='EDUCATION' AND d.withdrawn_at IS NULL))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_LANGUAGE_TEST',p_id,false,'SUBJECT_AUTHORITY_EVIDENCE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM education.language_test WHERE language_test_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_LANGUAGE_TEST',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO education.language_test(language_test_id,family_id,student_person_id,test_kind,score_json,test_date,evidence_document_id,recorded_by_principal_id)
  VALUES (p_id,p_family_id,p_student_person_id,btrim(p_test_kind),p_score_json,p_test_date,p_evidence_document_id,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','EDUCATION_LANGUAGE_TEST',p_id,true,'AUTHORIZED_CREATE');
END
$fn$;

CREATE FUNCTION education.create_plan(
  p_id uuid,p_family_id uuid,p_student_person_id uuid,p_goal_text text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, education, audit
AS $fn$
BEGIN
  IF (core.is_uuid_v7(p_id) AND education.can_write_student_record(p_family_id,p_student_person_id)
      AND length(btrim(p_goal_text)) BETWEEN 1 AND 2000) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_PLAN',p_id,false,'SUBJECT_AUTHORITY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM education.plan WHERE plan_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','EDUCATION_PLAN',p_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO education.plan(plan_id,family_id,student_person_id,goal_text,status,created_by_principal_id)
  VALUES (p_id,p_family_id,p_student_person_id,btrim(p_goal_text),'DRAFT',auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','EDUCATION_PLAN',p_id,true,'AUTHORIZED_CREATE');
END
$fn$;

CREATE FUNCTION education.advance_plan(p_id uuid,p_next_status text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, education, audit
AS $fn$
DECLARE v_plan education.plan%ROWTYPE;
BEGIN
  SELECT * INTO v_plan FROM education.plan WHERE plan_id=p_id FOR UPDATE;
  IF (FOUND AND education.can_write_student_record(v_plan.family_id,v_plan.student_person_id)
      AND ((v_plan.status='DRAFT' AND p_next_status IN ('ACTIVE','ARCHIVED'))
        OR (v_plan.status='ACTIVE' AND p_next_status IN ('COMPLETED','ARCHIVED')))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','EDUCATION_PLAN',p_id,false,'SUBJECT_AUTHORITY_OR_TRANSITION_DENIED');
  END IF;
  UPDATE education.plan SET status=p_next_status WHERE plan_id=p_id;
  RETURN audit.record_write_decision('ADVANCE','EDUCATION_PLAN',p_id,true,'STATE_TRANSITION_ALLOWED');
END
$fn$;

CREATE FUNCTION education.add_plan_target(
  p_plan_id uuid,p_target_no integer,p_institution_id uuid,p_program_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, education, audit
AS $fn$
DECLARE v_plan education.plan%ROWTYPE;
BEGIN
  SELECT * INTO v_plan FROM education.plan WHERE plan_id=p_plan_id;
  IF (FOUND AND education.can_write_student_record(v_plan.family_id,v_plan.student_person_id)
      AND p_target_no > 0 AND EXISTS (
        SELECT 1 FROM education.program p JOIN education.institution i ON i.institution_id=p.institution_id
         WHERE p.program_id=p_program_id AND p.institution_id=p_institution_id
           AND p.status='ACTIVE' AND i.status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD_TARGET','EDUCATION_PLAN',p_plan_id,false,'SUBJECT_AUTHORITY_OR_MASTER_TARGET_DENIED');
  END IF;
  IF EXISTS (SELECT 1 FROM education.plan_target WHERE plan_id=p_plan_id AND (target_no=p_target_no OR (institution_id=p_institution_id AND program_id=p_program_id))) THEN
    RETURN audit.record_write_decision('ADD_TARGET','EDUCATION_PLAN',p_plan_id,false,'ALREADY_EXISTS');
  END IF;
  INSERT INTO education.plan_target(plan_id,target_no,institution_id,program_id,created_by_principal_id)
  VALUES (p_plan_id,p_target_no,p_institution_id,p_program_id,auth.current_principal_id());
  RETURN audit.record_write_decision('ADD_TARGET','EDUCATION_PLAN',p_plan_id,true,'AUTHORIZED_CREATE');
END
$fn$;

CREATE FUNCTION education.set_application_master_target(
  p_application_id uuid,p_institution_id uuid,p_program_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, education, audit
AS $fn$
DECLARE v_application education.applications%ROWTYPE;
BEGIN
  SELECT * INTO v_application FROM education.applications WHERE application_id=p_application_id FOR UPDATE;
  IF (FOUND AND education.can_write_application(p_application_id,v_application.student_person_id)
      AND EXISTS (SELECT 1 FROM education.institution WHERE institution_id=p_institution_id AND status='ACTIVE')
      AND (p_program_id IS NULL OR EXISTS (SELECT 1 FROM education.program
        WHERE program_id=p_program_id AND institution_id=p_institution_id AND status='ACTIVE'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SET_TARGET','EDUCATION_APPLICATION',p_application_id,false,'APPLICATION_AUTHORITY_OR_MASTER_TARGET_DENIED');
  END IF;
  UPDATE education.applications SET institution_id=p_institution_id,program_id=p_program_id
   WHERE application_id=p_application_id;
  RETURN audit.record_write_decision('SET_TARGET','EDUCATION_APPLICATION',p_application_id,true,'AUTHORIZED_TARGET_SET');
END
$fn$;

ALTER TABLE education.institution ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.program ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.academic_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.score_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.language_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.plan_target ENABLE ROW LEVEL SECURITY;

CREATE POLICY institution_read ON education.institution FOR SELECT TO phoenix_canonical_app,phoenix_canonical_reader
  USING (status='ACTIVE' AND auth.current_principal_id() IS NOT NULL);
CREATE POLICY program_read ON education.program FOR SELECT TO phoenix_canonical_app,phoenix_canonical_reader
  USING (status='ACTIVE' AND auth.current_principal_id() IS NOT NULL);
CREATE POLICY academic_record_read ON education.academic_record FOR SELECT TO phoenix_canonical_app,phoenix_canonical_reader
  USING (education.can_read_student_record(family_id,student_person_id));
CREATE POLICY score_record_read ON education.score_record FOR SELECT TO phoenix_canonical_app,phoenix_canonical_reader
  USING (education.can_read_student_record(family_id,student_person_id));
CREATE POLICY language_test_read ON education.language_test FOR SELECT TO phoenix_canonical_app,phoenix_canonical_reader
  USING (education.can_read_student_record(family_id,student_person_id));
CREATE POLICY education_plan_read ON education.plan FOR SELECT TO phoenix_canonical_app,phoenix_canonical_reader
  USING (education.can_read_student_record(family_id,student_person_id));
CREATE POLICY education_plan_target_read ON education.plan_target FOR SELECT TO phoenix_canonical_app,phoenix_canonical_reader
  USING (EXISTS (SELECT 1 FROM education.plan p WHERE p.plan_id=plan_target.plan_id
    AND education.can_read_student_record(p.family_id,p.student_person_id)));

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA education FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  education.can_read_student_record(uuid,uuid),education.can_write_student_record(uuid,uuid),
  education.create_institution_draft(uuid,text,text,integer),
  education.create_program_draft(uuid,uuid,text,text,integer),
  education.create_academic_record(uuid,uuid,uuid,text,text,date,uuid),
  education.create_score_record(uuid,uuid,uuid,text,numeric,date,text),
  education.create_language_test(uuid,uuid,uuid,text,jsonb,date,uuid),
  education.create_plan(uuid,uuid,uuid,text),education.advance_plan(uuid,text),
  education.add_plan_target(uuid,integer,uuid,uuid),
  education.set_application_master_target(uuid,uuid,uuid)
TO phoenix_canonical_app;

GRANT SELECT ON education.institution,education.program,education.academic_record,
  education.score_record,education.language_test,education.plan,education.plan_target
TO phoenix_canonical_app,phoenix_canonical_reader;

COMMIT;
