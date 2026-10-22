BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA learning;
REVOKE ALL ON SCHEMA learning FROM PUBLIC;

-- Founder-approved authorization vocabulary. Existing values remain valid.
ALTER TABLE auth.principals DROP CONSTRAINT principals_principal_kind_check;
ALTER TABLE auth.principals ADD CONSTRAINT principals_principal_kind_check
  CHECK (principal_kind IN ('FAMILY','ADVISOR','CHANNEL','SERVICE','TEACHER','SUPERVISOR'));
ALTER TABLE auth.session_contexts DROP CONSTRAINT session_contexts_channel_check;
ALTER TABLE auth.session_contexts ADD CONSTRAINT session_contexts_channel_check
  CHECK (channel IN ('FAMILY','ADVISOR','PARTNER','INTERNAL','STAFF'));
ALTER TABLE auth.context_exchange_tickets DROP CONSTRAINT context_exchange_tickets_channel_check;
ALTER TABLE auth.context_exchange_tickets ADD CONSTRAINT context_exchange_tickets_channel_check
  CHECK (channel IN ('FAMILY','ADVISOR','PARTNER','INTERNAL','STAFF'));
ALTER TABLE consent.grants DROP CONSTRAINT grants_purpose_check;
ALTER TABLE consent.grants ADD CONSTRAINT grants_purpose_check
  CHECK (purpose IN ('DOCUMENT_READ','EDUCATION_CASE','IDENTITY_CASE','LEARNING_RECORD'));
ALTER TABLE consent.grants DROP CONSTRAINT grants_data_class_check;
ALTER TABLE consent.grants ADD CONSTRAINT grants_data_class_check
  CHECK (data_class IN ('GENERAL','EDUCATION','IDENTITY_SENSITIVE','LEARNING'));
ALTER TABLE core.guardian_authorities DROP CONSTRAINT guardian_authorities_scope_check;
ALTER TABLE core.guardian_authorities ADD CONSTRAINT guardian_authorities_scope_check
  CHECK (scope IN ('GENERAL','EDUCATION','IDENTITY','LEARNING'));

CREATE TABLE learning.course (
  course_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(course_id)),
  course_code text NOT NULL UNIQUE CHECK (length(btrim(course_code)) BETWEEN 1 AND 60),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 300),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED','ARCHIVED')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);

CREATE TABLE learning.course_version (
  course_version_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(course_version_id)),
  course_id uuid NOT NULL REFERENCES learning.course,
  version_no integer NOT NULL CHECK (version_no >= 1),
  effective_from timestamptz NOT NULL,
  effective_until timestamptz,
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (effective_until IS NULL OR effective_until > effective_from),
  UNIQUE (course_id,version_no),
  UNIQUE (course_version_id,course_id)
);
CREATE UNIQUE INDEX learning_one_active_course_version
  ON learning.course_version(course_id) WHERE status='ACTIVE';

CREATE TABLE learning.teacher (
  teacher_person_id uuid PRIMARY KEY REFERENCES core.people,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);

CREATE TABLE learning.class (
  class_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(class_id)),
  course_version_id uuid NOT NULL REFERENCES learning.course_version,
  class_code text NOT NULL UNIQUE CHECK (length(btrim(class_code)) BETWEEN 1 AND 60),
  capacity integer NOT NULL CHECK (capacity BETWEEN 1 AND 200),
  status text NOT NULL DEFAULT 'PLANNED' CHECK (status IN ('PLANNED','OPEN','RUNNING','CLOSED')),
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (ends_on >= starts_on),
  UNIQUE (class_id,course_version_id)
);

CREATE TABLE learning.enrollment (
  enrollment_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(enrollment_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  student_person_id uuid NOT NULL REFERENCES core.student_profiles(person_id),
  course_version_id uuid NOT NULL REFERENCES learning.course_version,
  status text NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','COMPLETED','WITHDRAWN')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE (enrollment_id,family_id,student_person_id),
  UNIQUE (enrollment_id,family_id,student_person_id,course_version_id)
);
CREATE UNIQUE INDEX learning_one_current_enrollment
  ON learning.enrollment(student_person_id,course_version_id)
  WHERE status IN ('PENDING','ACTIVE','SUSPENDED');

CREATE TABLE learning.enrollment_status_event (
  event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(event_id)),
  enrollment_id uuid NOT NULL REFERENCES learning.enrollment,
  from_status text,
  to_status text NOT NULL CHECK (to_status IN ('PENDING','ACTIVE','SUSPENDED','COMPLETED','WITHDRAWN')),
  reason_code text NOT NULL CHECK (length(btrim(reason_code)) BETWEEN 1 AND 60),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE learning.teacher_assignment (
  assignment_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(assignment_id)),
  class_id uuid NOT NULL REFERENCES learning.class,
  teacher_person_id uuid NOT NULL REFERENCES learning.teacher,
  role text NOT NULL CHECK (role IN ('LEAD','ASSISTANT')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','ENDED','REVOKED')),
  revoked_at timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (valid_until > valid_from),
  CHECK ((status='REVOKED')=(revoked_at IS NOT NULL)),
  UNIQUE (assignment_id,class_id,teacher_person_id)
);
CREATE UNIQUE INDEX learning_one_active_teacher_class
  ON learning.teacher_assignment(class_id,teacher_person_id) WHERE status='ACTIVE';
CREATE UNIQUE INDEX learning_one_active_lead
  ON learning.teacher_assignment(class_id) WHERE status='ACTIVE' AND role='LEAD';

CREATE TABLE learning.enrollment_class (
  enrollment_id uuid NOT NULL,
  class_id uuid NOT NULL,
  family_id uuid NOT NULL,
  student_person_id uuid NOT NULL,
  course_version_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DROPPED')),
  joined_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  left_at timestamptz,
  PRIMARY KEY (enrollment_id,class_id),
  FOREIGN KEY (enrollment_id,family_id,student_person_id,course_version_id)
    REFERENCES learning.enrollment(enrollment_id,family_id,student_person_id,course_version_id),
  FOREIGN KEY (class_id,course_version_id)
    REFERENCES learning.class(class_id,course_version_id),
  CHECK ((status='DROPPED')=(left_at IS NOT NULL)),
  UNIQUE (enrollment_id,class_id,family_id,student_person_id)
);

CREATE TABLE learning.schedule_slot (
  slot_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(slot_id)),
  class_id uuid NOT NULL REFERENCES learning.class,
  teacher_person_id uuid NOT NULL REFERENCES learning.teacher,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  room_label text CHECK (room_label IS NULL OR length(btrim(room_label)) BETWEEN 1 AND 100),
  status text NOT NULL DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED','COMPLETED','CANCELLED')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (ends_at > starts_at),
  UNIQUE (slot_id,class_id),
  EXCLUDE USING gist (
    teacher_person_id WITH =,
    tstzrange(starts_at,ends_at,'[)') WITH &&
  ) WHERE (status <> 'CANCELLED')
);

CREATE TABLE learning.attendance_record (
  attendance_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(attendance_id)),
  slot_id uuid NOT NULL,
  class_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  family_id uuid NOT NULL,
  student_person_id uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('PRESENT','ABSENT','LATE','LEAVE')),
  recorded_by_teacher_person_id uuid NOT NULL REFERENCES learning.teacher,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (slot_id,class_id) REFERENCES learning.schedule_slot(slot_id,class_id),
  FOREIGN KEY (enrollment_id,class_id,family_id,student_person_id)
    REFERENCES learning.enrollment_class(enrollment_id,class_id,family_id,student_person_id),
  UNIQUE (slot_id,enrollment_id)
);

CREATE TABLE learning.attendance_correction (
  correction_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(correction_id)),
  attendance_id uuid NOT NULL REFERENCES learning.attendance_record,
  new_status text NOT NULL CHECK (new_status IN ('PRESENT','ABSENT','LATE','LEAVE')),
  reason_code text NOT NULL CHECK (length(btrim(reason_code)) BETWEEN 1 AND 100),
  corrected_by_teacher_person_id uuid NOT NULL REFERENCES learning.teacher,
  corrected_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE learning.after_class_card (
  card_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(card_id)),
  slot_id uuid NOT NULL,
  class_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  family_id uuid NOT NULL,
  student_person_id uuid NOT NULL,
  author_teacher_person_id uuid NOT NULL REFERENCES learning.teacher,
  summary_text text NOT NULL CHECK (length(btrim(summary_text)) BETWEEN 1 AND 2000),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SUBMITTED','PUBLISHED','RETRACTED')),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (slot_id,class_id) REFERENCES learning.schedule_slot(slot_id,class_id),
  FOREIGN KEY (enrollment_id,class_id,family_id,student_person_id)
    REFERENCES learning.enrollment_class(enrollment_id,class_id,family_id,student_person_id),
  UNIQUE (slot_id,enrollment_id)
);

CREATE TABLE learning.publication (
  publication_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(publication_id)),
  card_id uuid NOT NULL REFERENCES learning.after_class_card,
  family_id uuid NOT NULL REFERENCES core.families,
  audience text NOT NULL DEFAULT 'FAMILY' CHECK (audience='FAMILY'),
  event_kind text NOT NULL CHECK (event_kind IN ('PUBLISHED','RETRACTED')),
  supersedes_publication_id uuid REFERENCES learning.publication,
  acted_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  acted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK ((event_kind='RETRACTED')=(supersedes_publication_id IS NOT NULL))
);

CREATE TABLE learning.stage_report (
  report_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(report_id)),
  enrollment_id uuid NOT NULL,
  family_id uuid NOT NULL,
  student_person_id uuid NOT NULL,
  author_teacher_person_id uuid NOT NULL REFERENCES learning.teacher,
  period_label text NOT NULL CHECK (length(btrim(period_label)) BETWEEN 1 AND 60),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SUBMITTED','PUBLISHED','RETRACTED')),
  summary_text text NOT NULL CHECK (length(btrim(summary_text)) BETWEEN 1 AND 4000),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (enrollment_id,family_id,student_person_id)
    REFERENCES learning.enrollment(enrollment_id,family_id,student_person_id),
  UNIQUE (enrollment_id,period_label)
);

-- Immutable history and state-machine enforcement also apply to the table owner.
CREATE FUNCTION learning.reject_history_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning AS $fn$
BEGIN
  RAISE EXCEPTION 'LEARNING_HISTORY_IMMUTABLE';
END
$fn$;
CREATE TRIGGER enrollment_event_immutable BEFORE UPDATE OR DELETE ON learning.enrollment_status_event
FOR EACH ROW EXECUTE FUNCTION learning.reject_history_change();
CREATE TRIGGER attendance_correction_immutable BEFORE UPDATE OR DELETE ON learning.attendance_correction
FOR EACH ROW EXECUTE FUNCTION learning.reject_history_change();
CREATE TRIGGER publication_immutable BEFORE UPDATE OR DELETE ON learning.publication
FOR EACH ROW EXECUTE FUNCTION learning.reject_history_change();

CREATE FUNCTION learning.protect_state_transition() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning AS $fn$
DECLARE v_allowed boolean := false;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  CASE TG_TABLE_NAME
    WHEN 'course' THEN v_allowed := OLD.status='DRAFT' AND NEW.status='PUBLISHED'
      OR OLD.status='PUBLISHED' AND NEW.status='ARCHIVED';
    WHEN 'course_version' THEN v_allowed := OLD.status='DRAFT' AND NEW.status='ACTIVE'
      OR OLD.status='ACTIVE' AND NEW.status='RETIRED';
    WHEN 'teacher' THEN v_allowed := OLD.status='ACTIVE' AND NEW.status='INACTIVE';
    WHEN 'class' THEN v_allowed := OLD.status='PLANNED' AND NEW.status='OPEN'
      OR OLD.status='OPEN' AND NEW.status='RUNNING'
      OR OLD.status='RUNNING' AND NEW.status='CLOSED';
    WHEN 'enrollment' THEN v_allowed := OLD.status='PENDING' AND NEW.status IN ('ACTIVE','WITHDRAWN')
      OR OLD.status='ACTIVE' AND NEW.status IN ('SUSPENDED','COMPLETED','WITHDRAWN')
      OR OLD.status='SUSPENDED' AND NEW.status IN ('ACTIVE','WITHDRAWN');
    WHEN 'teacher_assignment' THEN v_allowed := OLD.status='ACTIVE' AND NEW.status IN ('ENDED','REVOKED');
    WHEN 'enrollment_class' THEN v_allowed := OLD.status='ACTIVE' AND NEW.status='DROPPED';
    WHEN 'schedule_slot' THEN v_allowed := OLD.status='SCHEDULED' AND NEW.status IN ('COMPLETED','CANCELLED');
    WHEN 'after_class_card' THEN v_allowed := OLD.status='DRAFT' AND NEW.status='SUBMITTED'
      OR OLD.status='SUBMITTED' AND NEW.status IN ('DRAFT','PUBLISHED')
      OR OLD.status='PUBLISHED' AND NEW.status='RETRACTED'
      OR OLD.status='RETRACTED' AND NEW.status='PUBLISHED';
    WHEN 'stage_report' THEN v_allowed := OLD.status='DRAFT' AND NEW.status='SUBMITTED'
      OR OLD.status='SUBMITTED' AND NEW.status IN ('DRAFT','PUBLISHED')
      OR OLD.status='PUBLISHED' AND NEW.status='RETRACTED'
      OR OLD.status='RETRACTED' AND NEW.status='PUBLISHED';
    ELSE v_allowed := false;
  END CASE;
  IF v_allowed IS NOT TRUE THEN RAISE EXCEPTION 'LEARNING_STATE_TRANSITION_INVALID'; END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER course_state BEFORE UPDATE OF status ON learning.course FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER course_version_state BEFORE UPDATE OF status ON learning.course_version FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER teacher_state BEFORE UPDATE OF status ON learning.teacher FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER class_state BEFORE UPDATE OF status ON learning.class FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER enrollment_state BEFORE UPDATE OF status ON learning.enrollment FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER teacher_assignment_state BEFORE UPDATE OF status ON learning.teacher_assignment FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER enrollment_class_state BEFORE UPDATE OF status ON learning.enrollment_class FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER schedule_slot_state BEFORE UPDATE OF status ON learning.schedule_slot FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER after_class_card_state BEFORE UPDATE OF status ON learning.after_class_card FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();
CREATE TRIGGER stage_report_state BEFORE UPDATE OF status ON learning.stage_report FOR EACH ROW EXECUTE FUNCTION learning.protect_state_transition();

CREATE FUNCTION learning.normalize_assignment_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning AS $fn$
BEGIN
  IF NEW.status<>'ACTIVE' OR NEW.valid_until<=clock_timestamp() OR NEW.valid_from>=NEW.valid_until THEN
    RAISE EXCEPTION 'LEARNING_ASSIGNMENT_WINDOW_INVALID';
  END IF;
  UPDATE learning.teacher_assignment SET status='ENDED'
   WHERE status='ACTIVE' AND valid_until<=clock_timestamp()
     AND (class_id=NEW.class_id OR teacher_person_id=NEW.teacher_person_id);
  RETURN NEW;
END
$fn$;
CREATE TRIGGER normalize_teacher_assignment BEFORE INSERT ON learning.teacher_assignment
FOR EACH ROW EXECUTE FUNCTION learning.normalize_assignment_insert();

-- Context validation now admits person-backed TEACHER and SUPERVISOR principals only on STAFF.
CREATE OR REPLACE FUNCTION auth.validate_context_request(
  p_principal_id uuid,p_actor_person_id uuid,p_family_id uuid,p_channel text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,auth,core,integration,casework,learning
AS $fn$
DECLARE v_principal auth.principals%ROWTYPE;
BEGIN
  IF p_channel NOT IN ('FAMILY','ADVISOR','PARTNER','INTERNAL','STAFF') OR p_channel IS NULL THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_INVALID';
  END IF;
  SELECT * INTO v_principal FROM auth.principals
   WHERE principal_id=p_principal_id AND status='ACTIVE';
  IF NOT FOUND THEN RAISE EXCEPTION 'CONTEXT_PRINCIPAL_INVALID'; END IF;
  IF (v_principal.principal_kind='FAMILY' AND p_channel='FAMILY'
      OR v_principal.principal_kind='ADVISOR' AND p_channel='ADVISOR'
      OR v_principal.principal_kind='CHANNEL' AND p_channel='PARTNER'
      OR v_principal.principal_kind='SERVICE' AND p_channel='INTERNAL'
      OR v_principal.principal_kind IN ('TEACHER','SUPERVISOR') AND p_channel='STAFF') IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTEXT_PRINCIPAL_CHANNEL_MISMATCH';
  END IF;
  IF p_channel='INTERNAL' THEN
    IF p_actor_person_id IS NOT NULL OR v_principal.person_id IS NOT NULL THEN
      RAISE EXCEPTION 'CONTEXT_SERVICE_ACTOR_MUST_BE_NULL';
    END IF;
    IF p_family_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.families WHERE family_id=p_family_id) THEN
      RAISE EXCEPTION 'CONTEXT_FAMILY_INVALID';
    END IF;
    RETURN;
  END IF;
  IF p_actor_person_id IS NULL OR p_family_id IS NULL
      OR v_principal.person_id IS DISTINCT FROM p_actor_person_id THEN
    RAISE EXCEPTION 'CONTEXT_ACTOR_OR_FAMILY_INVALID';
  END IF;
  IF p_channel='FAMILY' AND NOT EXISTS (
    SELECT 1 FROM core.family_memberships WHERE family_id=p_family_id AND person_id=p_actor_person_id
      AND valid_from<=clock_timestamp() AND (valid_until IS NULL OR valid_until>clock_timestamp())) THEN
    RAISE EXCEPTION 'CONTEXT_FAMILY_MEMBERSHIP_INVALID';
  END IF;
  IF p_channel='ADVISOR' AND NOT EXISTS (
    SELECT 1 FROM casework.cases c JOIN casework.advisor_assignments a ON a.case_id=c.case_id
     WHERE c.family_id=p_family_id AND a.advisor_person_id=p_actor_person_id
       AND c.status IN ('OPEN','PAUSED') AND a.valid_from<=clock_timestamp()
       AND a.valid_until>clock_timestamp() AND a.revoked_at IS NULL AND a.lifecycle_status='ACTIVE') THEN
    RAISE EXCEPTION 'CONTEXT_ADVISOR_ASSIGNMENT_INVALID';
  END IF;
  IF p_channel='PARTNER' AND NOT EXISTS (
    SELECT 1 FROM integration.channel_grants WHERE principal_id=p_principal_id AND family_id=p_family_id
      AND valid_from<=clock_timestamp() AND valid_until>clock_timestamp() AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_GRANT_INVALID';
  END IF;
  IF p_channel='STAFF' AND v_principal.principal_kind='TEACHER' AND NOT EXISTS (
    SELECT 1 FROM learning.teacher WHERE teacher_person_id=p_actor_person_id AND status='ACTIVE') THEN
    RAISE EXCEPTION 'CONTEXT_TEACHER_INACTIVE';
  END IF;
END
$fn$;

-- Consent and guardian management now understands the exact Learning vocabulary.
CREATE OR REPLACE FUNCTION consent.actor_can_grant(
  p_subject_person_id uuid,p_purpose text,p_data_class text
) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,consent
RETURN coalesce(
  p_purpose IN ('DOCUMENT_READ','EDUCATION_CASE','IDENTITY_CASE','LEARNING_RECORD')
  AND p_data_class IN ('GENERAL','EDUCATION','IDENTITY_SENSITIVE','LEARNING')
  AND (p_purpose='DOCUMENT_READ'
    OR p_purpose='EDUCATION_CASE' AND p_data_class='EDUCATION'
    OR p_purpose='IDENTITY_CASE' AND p_data_class='IDENTITY_SENSITIVE'
    OR p_purpose='LEARNING_RECORD' AND p_data_class='LEARNING')
  AND auth.write_context_is_live() AND auth.current_channel()='FAMILY'
  AND core.current_actor_is_family_member() AND core.person_in_current_family(p_subject_person_id)
  AND ((auth.current_actor_person_id()=p_subject_person_id
        AND core.current_civil_capacity(p_subject_person_id)='ADULT_VERIFIED')
    OR core.has_verified_guardian_authority(p_subject_person_id,
      CASE p_data_class WHEN 'EDUCATION' THEN 'EDUCATION'
        WHEN 'IDENTITY_SENSITIVE' THEN 'IDENTITY'
        WHEN 'LEARNING' THEN 'LEARNING' ELSE 'GENERAL' END)),false);

CREATE OR REPLACE FUNCTION consent.withdraw_grant(p_consent_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,consent,audit
AS $fn$
DECLARE v_grant consent.grants%ROWTYPE;
BEGIN
  SELECT * INTO v_grant FROM consent.grants WHERE consent_id=p_consent_id FOR UPDATE;
  IF (FOUND AND v_grant.family_id=auth.current_family_id()
      AND v_grant.status='ACTIVE' AND v_grant.expires_at>clock_timestamp()
      AND core.actor_can_manage_subject(v_grant.subject_person_id,
        CASE v_grant.data_class WHEN 'EDUCATION' THEN 'EDUCATION'
          WHEN 'IDENTITY_SENSITIVE' THEN 'IDENTITY'
          WHEN 'LEARNING' THEN 'LEARNING' ELSE 'GENERAL' END)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('WITHDRAW','CONSENT',p_consent_id,false,'GRANTOR_AUTHORITY_OR_STATE_DENIED');
  END IF;
  UPDATE consent.grants SET status='WITHDRAWN',withdrawn_at=clock_timestamp() WHERE consent_id=p_consent_id;
  RETURN audit.record_write_decision('WITHDRAW','CONSENT',p_consent_id,true,'AUTHORIZED_WITHDRAWAL');
END
$fn$;

CREATE OR REPLACE FUNCTION core.create_guardian_authority(
  p_id uuid,p_family_id uuid,p_guardian_id uuid,p_subject_id uuid,
  p_level text,p_scope text,p_until timestamptz,p_evidence_ref text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_id) AND p_guardian_id<>p_subject_id
      AND core.person_in_current_family(p_guardian_id) AND core.person_in_current_family(p_subject_id)
      AND p_level='VERIFIED' AND p_scope IN ('GENERAL','EDUCATION','IDENTITY','LEARNING')
      AND p_until>clock_timestamp() AND length(btrim(p_evidence_ref)) BETWEEN 1 AND 500) IS NOT TRUE THEN
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
END
$fn$;

CREATE FUNCTION learning.current_staff_kind() RETURNS text
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth
RETURN (SELECT principal_kind FROM auth.principals
  WHERE principal_id=auth.current_principal_id() AND person_id=auth.current_actor_person_id()
    AND status='ACTIVE' AND auth.current_channel()='STAFF');

CREATE FUNCTION learning.has_learning_consent(p_subject_id uuid) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,consent
RETURN consent.has_active_consent(p_subject_id,'LEARNING_RECORD','LEARNING');

CREATE FUNCTION learning.teacher_has_class_access(p_class_id uuid,p_subject_id uuid) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,learning
RETURN coalesce(learning.current_staff_kind()='TEACHER'
  AND EXISTS (SELECT 1 FROM learning.teacher_assignment a JOIN learning.class c ON c.class_id=a.class_id
    WHERE a.class_id=p_class_id AND a.teacher_person_id=auth.current_actor_person_id()
      AND a.status='ACTIVE' AND a.revoked_at IS NULL AND a.valid_from<=clock_timestamp()
      AND a.valid_until>clock_timestamp() AND c.status IN ('OPEN','RUNNING'))
  AND learning.has_learning_consent(p_subject_id),false);

CREATE FUNCTION learning.can_manage_learning() RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,learning
RETURN coalesce(auth.is_internal_service() OR learning.current_staff_kind()='SUPERVISOR',false);

CREATE FUNCTION learning.can_read_sensitive(p_family_id uuid,p_subject_id uuid,p_class_id uuid) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning
RETURN coalesce(auth.write_context_is_live() AND auth.current_family_id()=p_family_id AND (
  auth.current_channel()='FAMILY' AND (
    auth.current_actor_person_id()=p_subject_id
    OR core.has_verified_guardian_authority(p_subject_id,'LEARNING') AND learning.has_learning_consent(p_subject_id))
  OR auth.current_channel()='STAFF' AND (
    learning.current_staff_kind()='SUPERVISOR' AND learning.has_learning_consent(p_subject_id)
    OR learning.teacher_has_class_access(p_class_id,p_subject_id))),false);

CREATE FUNCTION learning.register_staff_principal(
  p_principal_id uuid,p_person_id uuid,p_kind text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND core.is_uuid_v7(p_principal_id)
      AND p_kind IN ('TEACHER','SUPERVISOR')
      AND EXISTS(SELECT 1 FROM core.people WHERE person_id=p_person_id)
      AND (p_kind='SUPERVISOR' OR EXISTS(SELECT 1 FROM learning.teacher
        WHERE teacher_person_id=p_person_id AND status='ACTIVE'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REGISTER','LEARNING_STAFF_PRINCIPAL',p_principal_id,false,'SERVICE_PERSON_OR_KIND_DENIED');
  END IF;
  INSERT INTO auth.principals(principal_id,person_id,principal_kind,status)
  VALUES(p_principal_id,p_person_id,p_kind,'ACTIVE') ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('REGISTER','LEARNING_STAFF_PRINCIPAL',p_principal_id,false,'ALREADY_EXISTS'); END IF;
  RETURN audit.record_write_decision('REGISTER','LEARNING_STAFF_PRINCIPAL',p_principal_id,true,'SERVICE_REGISTERED');
END
$fn$;

CREATE FUNCTION learning.register_teacher(p_person_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
BEGIN
  IF (auth.is_internal_service() AND EXISTS(SELECT 1 FROM core.people WHERE person_id=p_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REGISTER','LEARNING_TEACHER',p_person_id,false,'SERVICE_OR_PERSON_DENIED');
  END IF;
  INSERT INTO learning.teacher(teacher_person_id,created_by_principal_id)
  VALUES(p_person_id,auth.current_principal_id()) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('REGISTER','LEARNING_TEACHER',p_person_id,false,'ALREADY_EXISTS'); END IF;
  RETURN audit.record_write_decision('REGISTER','LEARNING_TEACHER',p_person_id,true,'SERVICE_REGISTERED');
END
$fn$;

CREATE FUNCTION learning.create_course(p_id uuid,p_code text,p_title text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
BEGIN
  IF (learning.can_manage_learning() AND core.is_uuid_v7(p_id)
      AND length(btrim(p_code)) BETWEEN 1 AND 60 AND length(btrim(p_title)) BETWEEN 1 AND 300) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','LEARNING_COURSE',p_id,false,'MANAGER_OR_INPUT_DENIED');
  END IF;
  INSERT INTO learning.course(course_id,course_code,title,created_by_principal_id)
  VALUES(p_id,p_code,p_title,auth.current_principal_id()) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('CREATE','LEARNING_COURSE',p_id,false,'ALREADY_EXISTS'); END IF;
  RETURN audit.record_write_decision('CREATE','LEARNING_COURSE',p_id,true,'CREATED');
END
$fn$;

CREATE FUNCTION learning.advance_course(p_id uuid,p_next text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning,audit AS $fn$
DECLARE v learning.course%ROWTYPE;
BEGIN
  SELECT * INTO v FROM learning.course WHERE course_id=p_id FOR UPDATE;
  IF (FOUND AND learning.can_manage_learning()
      AND (v.status='DRAFT' AND p_next='PUBLISHED' OR v.status='PUBLISHED' AND p_next='ARCHIVED')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','LEARNING_COURSE',p_id,false,'MANAGER_OR_STATE_DENIED');
  END IF;
  UPDATE learning.course SET status=p_next WHERE course_id=p_id;
  RETURN audit.record_write_decision('ADVANCE','LEARNING_COURSE',p_id,true,'STATE_ADVANCED');
END
$fn$;

CREATE FUNCTION learning.create_course_version(
  p_id uuid,p_course_id uuid,p_version integer,p_from timestamptz,p_until timestamptz
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
BEGIN
  IF (learning.can_manage_learning() AND core.is_uuid_v7(p_id) AND p_version>=1
      AND (p_until IS NULL OR p_until>p_from)
      AND EXISTS(SELECT 1 FROM learning.course WHERE course_id=p_course_id AND status<>'ARCHIVED')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','LEARNING_COURSE_VERSION',p_id,false,'MANAGER_OR_INPUT_DENIED');
  END IF;
  INSERT INTO learning.course_version(course_version_id,course_id,version_no,effective_from,effective_until,created_by_principal_id)
  VALUES(p_id,p_course_id,p_version,p_from,p_until,auth.current_principal_id()) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('CREATE','LEARNING_COURSE_VERSION',p_id,false,'ALREADY_EXISTS'); END IF;
  RETURN audit.record_write_decision('CREATE','LEARNING_COURSE_VERSION',p_id,true,'CREATED');
END
$fn$;

CREATE FUNCTION learning.advance_course_version(p_id uuid,p_next text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning,audit AS $fn$
DECLARE v learning.course_version%ROWTYPE;
BEGIN
  SELECT * INTO v FROM learning.course_version WHERE course_version_id=p_id FOR UPDATE;
  IF (FOUND AND learning.can_manage_learning()
      AND (v.status='DRAFT' AND p_next='ACTIVE' OR v.status='ACTIVE' AND p_next='RETIRED')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','LEARNING_COURSE_VERSION',p_id,false,'MANAGER_OR_STATE_DENIED');
  END IF;
  UPDATE learning.course_version SET status=p_next WHERE course_version_id=p_id;
  RETURN audit.record_write_decision('ADVANCE','LEARNING_COURSE_VERSION',p_id,true,'STATE_ADVANCED');
END
$fn$;

CREATE FUNCTION learning.create_class(
  p_id uuid,p_version_id uuid,p_code text,p_capacity integer,p_start date,p_end date
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
BEGIN
  IF (learning.can_manage_learning() AND core.is_uuid_v7(p_id) AND p_capacity BETWEEN 1 AND 200
      AND p_end>=p_start AND length(btrim(p_code)) BETWEEN 1 AND 60
      AND EXISTS(SELECT 1 FROM learning.course_version WHERE course_version_id=p_version_id AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','LEARNING_CLASS',p_id,false,'MANAGER_OR_INPUT_DENIED');
  END IF;
  INSERT INTO learning.class(class_id,course_version_id,class_code,capacity,starts_on,ends_on,created_by_principal_id)
  VALUES(p_id,p_version_id,p_code,p_capacity,p_start,p_end,auth.current_principal_id()) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('CREATE','LEARNING_CLASS',p_id,false,'ALREADY_EXISTS'); END IF;
  RETURN audit.record_write_decision('CREATE','LEARNING_CLASS',p_id,true,'CREATED');
END
$fn$;

CREATE FUNCTION learning.advance_class(p_id uuid,p_next text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning,audit AS $fn$
DECLARE v learning.class%ROWTYPE;
BEGIN
  SELECT * INTO v FROM learning.class WHERE class_id=p_id FOR UPDATE;
  IF (FOUND AND learning.can_manage_learning()
      AND (v.status='PLANNED' AND p_next='OPEN' OR v.status='OPEN' AND p_next='RUNNING'
        OR v.status='RUNNING' AND p_next='CLOSED')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','LEARNING_CLASS',p_id,false,'MANAGER_OR_STATE_DENIED');
  END IF;
  UPDATE learning.class SET status=p_next WHERE class_id=p_id;
  IF p_next='CLOSED' THEN UPDATE learning.teacher_assignment SET status='ENDED' WHERE class_id=p_id AND status='ACTIVE'; END IF;
  RETURN audit.record_write_decision('ADVANCE','LEARNING_CLASS',p_id,true,'STATE_ADVANCED');
END
$fn$;

CREATE FUNCTION learning.assign_teacher(
  p_id uuid,p_class_id uuid,p_teacher_id uuid,p_role text,p_from timestamptz,p_until timestamptz
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
BEGIN
  IF (learning.can_manage_learning() AND core.is_uuid_v7(p_id) AND p_role IN ('LEAD','ASSISTANT')
      AND p_from<p_until AND p_until>clock_timestamp()
      AND EXISTS(SELECT 1 FROM learning.class WHERE class_id=p_class_id AND status<>'CLOSED')
      AND EXISTS(SELECT 1 FROM learning.teacher WHERE teacher_person_id=p_teacher_id AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ASSIGN','LEARNING_TEACHER',p_id,false,'MANAGER_SCOPE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO learning.teacher_assignment(assignment_id,class_id,teacher_person_id,role,valid_from,valid_until,created_by_principal_id)
  VALUES(p_id,p_class_id,p_teacher_id,p_role,p_from,p_until,auth.current_principal_id());
  RETURN audit.record_write_decision('ASSIGN','LEARNING_TEACHER',p_id,true,'ASSIGNED');
EXCEPTION WHEN unique_violation THEN
  RETURN audit.record_write_decision('ASSIGN','LEARNING_TEACHER',p_id,false,'ACTIVE_ASSIGNMENT_CONFLICT');
END
$fn$;

CREATE FUNCTION learning.end_teacher_assignment(p_id uuid,p_revoke boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning,audit AS $fn$
DECLARE v learning.teacher_assignment%ROWTYPE;
BEGIN
  SELECT * INTO v FROM learning.teacher_assignment WHERE assignment_id=p_id FOR UPDATE;
  IF (FOUND AND learning.can_manage_learning() AND v.status='ACTIVE') IS NOT TRUE THEN
    RETURN audit.record_write_decision('END','LEARNING_TEACHER_ASSIGNMENT',p_id,false,'MANAGER_OR_STATE_DENIED');
  END IF;
  UPDATE learning.teacher_assignment SET status=CASE WHEN p_revoke THEN 'REVOKED' ELSE 'ENDED' END,
    revoked_at=CASE WHEN p_revoke THEN clock_timestamp() ELSE NULL END WHERE assignment_id=p_id;
  RETURN audit.record_write_decision('END','LEARNING_TEACHER_ASSIGNMENT',p_id,true,'ASSIGNMENT_ENDED');
END
$fn$;

CREATE FUNCTION learning.create_schedule_slot(
  p_id uuid,p_class_id uuid,p_teacher_id uuid,p_start timestamptz,p_end timestamptz,p_room text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
BEGIN
  IF (learning.can_manage_learning() AND core.is_uuid_v7(p_id) AND p_end>p_start
      AND (p_room IS NULL OR length(btrim(p_room)) BETWEEN 1 AND 100)
      AND EXISTS(SELECT 1 FROM learning.class WHERE class_id=p_class_id AND status IN ('OPEN','RUNNING'))
      AND EXISTS(SELECT 1 FROM learning.teacher_assignment WHERE class_id=p_class_id
        AND teacher_person_id=p_teacher_id AND status='ACTIVE' AND revoked_at IS NULL
        AND valid_from<=p_start AND valid_until>=p_end)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','LEARNING_SCHEDULE_SLOT',p_id,false,'MANAGER_ASSIGNMENT_OR_INPUT_DENIED');
  END IF;
  INSERT INTO learning.schedule_slot(slot_id,class_id,teacher_person_id,starts_at,ends_at,room_label,created_by_principal_id)
  VALUES(p_id,p_class_id,p_teacher_id,p_start,p_end,p_room,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','LEARNING_SCHEDULE_SLOT',p_id,true,'CREATED');
EXCEPTION WHEN exclusion_violation THEN
  RETURN audit.record_write_decision('CREATE','LEARNING_SCHEDULE_SLOT',p_id,false,'TEACHER_SCHEDULE_OVERLAP');
END
$fn$;

CREATE FUNCTION learning.advance_schedule_slot(p_id uuid,p_next text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning,audit AS $fn$
DECLARE v learning.schedule_slot%ROWTYPE;
BEGIN
  SELECT * INTO v FROM learning.schedule_slot WHERE slot_id=p_id FOR UPDATE;
  IF (FOUND AND learning.can_manage_learning() AND v.status='SCHEDULED' AND p_next IN ('COMPLETED','CANCELLED')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','LEARNING_SCHEDULE_SLOT',p_id,false,'MANAGER_OR_STATE_DENIED');
  END IF;
  UPDATE learning.schedule_slot SET status=p_next WHERE slot_id=p_id;
  RETURN audit.record_write_decision('ADVANCE','LEARNING_SCHEDULE_SLOT',p_id,true,'STATE_ADVANCED');
END
$fn$;

CREATE FUNCTION learning.create_enrollment(
  p_id uuid,p_event_id uuid,p_family_id uuid,p_student_id uuid,p_version_id uuid,p_reason text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,operations_ref,audit AS $fn$
DECLARE v_course uuid;
BEGIN
  SELECT cv.course_id INTO v_course FROM learning.course_version cv JOIN learning.course c ON c.course_id=cv.course_id
   WHERE cv.course_version_id=p_version_id AND cv.status='ACTIVE' AND c.status='PUBLISHED'
     AND cv.effective_from<=clock_timestamp() AND (cv.effective_until IS NULL OR cv.effective_until>clock_timestamp());
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event_id)
      AND FOUND AND core.person_in_current_family(p_student_id)
      AND operations_ref.has_valid_entitlement(p_family_id,p_student_id,'COURSE',v_course)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','LEARNING_ENROLLMENT',p_id,false,'SERVICE_FAMILY_VERSION_OR_ENTITLEMENT_DENIED');
  END IF;
  INSERT INTO learning.enrollment(enrollment_id,family_id,student_person_id,course_version_id,created_by_principal_id)
  VALUES(p_id,p_family_id,p_student_id,p_version_id,auth.current_principal_id());
  INSERT INTO learning.enrollment_status_event(event_id,enrollment_id,to_status,reason_code,actor_principal_id)
  VALUES(p_event_id,p_id,'PENDING',p_reason,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','LEARNING_ENROLLMENT',p_id,true,'ENTITLEMENT_VALIDATED_PENDING');
EXCEPTION WHEN unique_violation THEN
  RETURN audit.record_write_decision('CREATE','LEARNING_ENROLLMENT',p_id,false,'CURRENT_ENROLLMENT_EXISTS');
END
$fn$;

CREATE FUNCTION learning.advance_enrollment(p_id uuid,p_event_id uuid,p_next text,p_reason text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,consent,learning,audit AS $fn$
DECLARE v learning.enrollment%ROWTYPE; v_valid boolean;
BEGIN
  SELECT * INTO v FROM learning.enrollment WHERE enrollment_id=p_id FOR UPDATE;
  v_valid := v.status='PENDING' AND p_next IN ('ACTIVE','WITHDRAWN')
    OR v.status='ACTIVE' AND p_next IN ('SUSPENDED','COMPLETED','WITHDRAWN')
    OR v.status='SUSPENDED' AND p_next IN ('ACTIVE','WITHDRAWN');
  IF (FOUND AND auth.is_internal_service() AND auth.current_family_id()=v.family_id
      AND core.is_uuid_v7(p_event_id) AND v_valid
      AND (p_next<>'ACTIVE' OR EXISTS(SELECT 1 FROM consent.grants WHERE family_id=v.family_id
        AND subject_person_id=v.student_person_id AND purpose='LEARNING_RECORD' AND data_class='LEARNING'
        AND status='ACTIVE' AND expires_at>clock_timestamp()))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','LEARNING_ENROLLMENT',p_id,false,'SERVICE_STATE_OR_CONSENT_DENIED');
  END IF;
  UPDATE learning.enrollment SET status=p_next WHERE enrollment_id=p_id;
  INSERT INTO learning.enrollment_status_event(event_id,enrollment_id,from_status,to_status,reason_code,actor_principal_id)
  VALUES(p_event_id,p_id,v.status,p_next,p_reason,auth.current_principal_id());
  RETURN audit.record_write_decision('ADVANCE','LEARNING_ENROLLMENT',p_id,true,'STATE_ADVANCED');
END
$fn$;

CREATE FUNCTION learning.place_enrollment_in_class(p_enrollment_id uuid,p_class_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,learning,audit AS $fn$
DECLARE v_e learning.enrollment%ROWTYPE; v_c learning.class%ROWTYPE; v_count integer;
BEGIN
  SELECT * INTO v_e FROM learning.enrollment WHERE enrollment_id=p_enrollment_id FOR UPDATE;
  SELECT * INTO v_c FROM learning.class WHERE class_id=p_class_id FOR UPDATE;
  SELECT count(*) INTO v_count FROM learning.enrollment_class WHERE class_id=p_class_id AND status='ACTIVE';
  IF (FOUND AND learning.can_manage_learning() AND v_e.status='ACTIVE'
      AND v_c.status IN ('OPEN','RUNNING') AND v_e.course_version_id=v_c.course_version_id
      AND v_count<v_c.capacity) IS NOT TRUE THEN
    RETURN audit.record_write_decision('PLACE','LEARNING_ENROLLMENT_CLASS',p_enrollment_id,false,'MANAGER_VERSION_CAPACITY_OR_STATE_DENIED');
  END IF;
  INSERT INTO learning.enrollment_class(enrollment_id,class_id,family_id,student_person_id,course_version_id)
  VALUES(v_e.enrollment_id,v_c.class_id,v_e.family_id,v_e.student_person_id,v_e.course_version_id) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('PLACE','LEARNING_ENROLLMENT_CLASS',p_enrollment_id,false,'ALREADY_PLACED'); END IF;
  RETURN audit.record_write_decision('PLACE','LEARNING_ENROLLMENT_CLASS',p_enrollment_id,true,'PLACED');
END
$fn$;

CREATE FUNCTION learning.record_attendance(
  p_id uuid,p_slot_id uuid,p_enrollment_id uuid,p_status text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
DECLARE v_slot learning.schedule_slot%ROWTYPE; v_ec learning.enrollment_class%ROWTYPE;
BEGIN
  SELECT * INTO v_slot FROM learning.schedule_slot WHERE slot_id=p_slot_id;
  SELECT * INTO v_ec FROM learning.enrollment_class WHERE enrollment_id=p_enrollment_id AND class_id=v_slot.class_id;
  IF (FOUND AND core.is_uuid_v7(p_id) AND p_status IN ('PRESENT','ABSENT','LATE','LEAVE')
      AND v_ec.status='ACTIVE' AND (auth.is_internal_service()
        OR learning.teacher_has_class_access(v_slot.class_id,v_ec.student_person_id))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('RECORD','LEARNING_ATTENDANCE',p_id,false,'SERVICE_TEACHER_ASSIGNMENT_OR_CONSENT_DENIED');
  END IF;
  INSERT INTO learning.attendance_record(attendance_id,slot_id,class_id,enrollment_id,family_id,student_person_id,
    status,recorded_by_teacher_person_id)
  VALUES(p_id,v_slot.slot_id,v_slot.class_id,v_ec.enrollment_id,v_ec.family_id,v_ec.student_person_id,p_status,
    coalesce(auth.current_actor_person_id(),v_slot.teacher_person_id)) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('RECORD','LEARNING_ATTENDANCE',p_id,false,'ALREADY_RECORDED'); END IF;
  RETURN audit.record_write_decision('RECORD','LEARNING_ATTENDANCE',p_id,true,'RECORDED');
END
$fn$;

CREATE FUNCTION learning.correct_attendance(
  p_id uuid,p_attendance_id uuid,p_status text,p_reason text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
DECLARE v learning.attendance_record%ROWTYPE;
BEGIN
  SELECT * INTO v FROM learning.attendance_record WHERE attendance_id=p_attendance_id;
  IF (FOUND AND core.is_uuid_v7(p_id) AND p_status IN ('PRESENT','ABSENT','LATE','LEAVE')
      AND length(btrim(p_reason)) BETWEEN 1 AND 100 AND (learning.current_staff_kind()='SUPERVISOR'
        AND learning.has_learning_consent(v.student_person_id)
        OR learning.teacher_has_class_access(v.class_id,v.student_person_id))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CORRECT','LEARNING_ATTENDANCE',p_id,false,'STAFF_ASSIGNMENT_OR_CONSENT_DENIED');
  END IF;
  INSERT INTO learning.attendance_correction(correction_id,attendance_id,new_status,reason_code,corrected_by_teacher_person_id)
  VALUES(p_id,p_attendance_id,p_status,p_reason,auth.current_actor_person_id());
  RETURN audit.record_write_decision('CORRECT','LEARNING_ATTENDANCE',p_id,true,'CORRECTION_APPENDED');
END
$fn$;

CREATE FUNCTION learning.save_after_class_card(
  p_id uuid,p_slot_id uuid,p_enrollment_id uuid,p_summary text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
DECLARE v_slot learning.schedule_slot%ROWTYPE; v_ec learning.enrollment_class%ROWTYPE;
BEGIN
  SELECT * INTO v_slot FROM learning.schedule_slot WHERE slot_id=p_slot_id;
  SELECT * INTO v_ec FROM learning.enrollment_class WHERE enrollment_id=p_enrollment_id AND class_id=v_slot.class_id;
  IF (FOUND AND core.is_uuid_v7(p_id) AND length(btrim(p_summary)) BETWEEN 1 AND 2000
      AND learning.teacher_has_class_access(v_slot.class_id,v_ec.student_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SAVE','LEARNING_AFTER_CLASS_CARD',p_id,false,'TEACHER_ASSIGNMENT_OR_CONSENT_DENIED');
  END IF;
  INSERT INTO learning.after_class_card(card_id,slot_id,class_id,enrollment_id,family_id,student_person_id,
    author_teacher_person_id,summary_text)
  VALUES(p_id,v_slot.slot_id,v_slot.class_id,v_ec.enrollment_id,v_ec.family_id,v_ec.student_person_id,
    auth.current_actor_person_id(),p_summary) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('SAVE','LEARNING_AFTER_CLASS_CARD',p_id,false,'ALREADY_EXISTS'); END IF;
  RETURN audit.record_write_decision('SAVE','LEARNING_AFTER_CLASS_CARD',p_id,true,'DRAFT_SAVED');
END
$fn$;

CREATE FUNCTION learning.submit_after_class_card(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,learning,audit AS $fn$
DECLARE v learning.after_class_card%ROWTYPE;
BEGIN
  SELECT * INTO v FROM learning.after_class_card WHERE card_id=p_id FOR UPDATE;
  IF (FOUND AND v.status='DRAFT' AND v.author_teacher_person_id=auth.current_actor_person_id()
      AND learning.teacher_has_class_access(v.class_id,v.student_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SUBMIT','LEARNING_AFTER_CLASS_CARD',p_id,false,'AUTHOR_ASSIGNMENT_CONSENT_OR_STATE_DENIED');
  END IF;
  UPDATE learning.after_class_card SET status='SUBMITTED',updated_at=clock_timestamp() WHERE card_id=p_id;
  RETURN audit.record_write_decision('SUBMIT','LEARNING_AFTER_CLASS_CARD',p_id,true,'SUBMITTED');
END
$fn$;

CREATE FUNCTION learning.publish_after_class_card(p_publication_id uuid,p_card_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
DECLARE v learning.after_class_card%ROWTYPE;
BEGIN
  SELECT * INTO v FROM learning.after_class_card WHERE card_id=p_card_id FOR UPDATE;
  IF (FOUND AND core.is_uuid_v7(p_publication_id) AND learning.current_staff_kind()='SUPERVISOR'
      AND v.status IN ('SUBMITTED','RETRACTED') AND auth.current_family_id()=v.family_id
      AND learning.has_learning_consent(v.student_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('PUBLISH','LEARNING_AFTER_CLASS_CARD',p_card_id,false,'SUPERVISOR_CONSENT_FAMILY_OR_STATE_DENIED');
  END IF;
  INSERT INTO learning.publication(publication_id,card_id,family_id,event_kind,acted_by_principal_id)
  VALUES(p_publication_id,p_card_id,v.family_id,'PUBLISHED',auth.current_principal_id());
  UPDATE learning.after_class_card SET status='PUBLISHED',updated_at=clock_timestamp() WHERE card_id=p_card_id;
  RETURN audit.record_write_decision('PUBLISH','LEARNING_AFTER_CLASS_CARD',p_card_id,true,'PUBLISHED');
END
$fn$;

CREATE FUNCTION learning.retract_after_class_card(p_publication_id uuid,p_card_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
DECLARE v learning.after_class_card%ROWTYPE; v_previous uuid;
BEGIN
  SELECT * INTO v FROM learning.after_class_card WHERE card_id=p_card_id FOR UPDATE;
  SELECT publication_id INTO v_previous FROM learning.publication
    WHERE card_id=p_card_id AND event_kind='PUBLISHED' ORDER BY acted_at DESC LIMIT 1;
  IF (FOUND AND core.is_uuid_v7(p_publication_id) AND learning.current_staff_kind()='SUPERVISOR'
      AND v.status='PUBLISHED' AND auth.current_family_id()=v.family_id
      AND learning.has_learning_consent(v.student_person_id) AND v_previous IS NOT NULL) IS NOT TRUE THEN
    RETURN audit.record_write_decision('RETRACT','LEARNING_AFTER_CLASS_CARD',p_card_id,false,'SUPERVISOR_CONSENT_FAMILY_OR_STATE_DENIED');
  END IF;
  INSERT INTO learning.publication(publication_id,card_id,family_id,event_kind,supersedes_publication_id,acted_by_principal_id)
  VALUES(p_publication_id,p_card_id,v.family_id,'RETRACTED',v_previous,auth.current_principal_id());
  UPDATE learning.after_class_card SET status='RETRACTED',updated_at=clock_timestamp() WHERE card_id=p_card_id;
  RETURN audit.record_write_decision('RETRACT','LEARNING_AFTER_CLASS_CARD',p_card_id,true,'RETRACTED');
END
$fn$;

CREATE FUNCTION learning.save_stage_report(
  p_id uuid,p_enrollment_id uuid,p_period text,p_summary text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,core,learning,audit AS $fn$
DECLARE v learning.enrollment%ROWTYPE; v_class uuid;
BEGIN
  SELECT * INTO v FROM learning.enrollment WHERE enrollment_id=p_enrollment_id;
  SELECT ec.class_id INTO v_class FROM learning.enrollment_class ec WHERE ec.enrollment_id=p_enrollment_id AND ec.status='ACTIVE' LIMIT 1;
  IF (FOUND AND core.is_uuid_v7(p_id) AND length(btrim(p_period)) BETWEEN 1 AND 60
      AND length(btrim(p_summary)) BETWEEN 1 AND 4000
      AND learning.teacher_has_class_access(v_class,v.student_person_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SAVE','LEARNING_STAGE_REPORT',p_id,false,'TEACHER_ASSIGNMENT_OR_CONSENT_DENIED');
  END IF;
  INSERT INTO learning.stage_report(report_id,enrollment_id,family_id,student_person_id,author_teacher_person_id,period_label,summary_text)
  VALUES(p_id,v.enrollment_id,v.family_id,v.student_person_id,auth.current_actor_person_id(),p_period,p_summary) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN audit.record_write_decision('SAVE','LEARNING_STAGE_REPORT',p_id,false,'ALREADY_EXISTS'); END IF;
  RETURN audit.record_write_decision('SAVE','LEARNING_STAGE_REPORT',p_id,true,'DRAFT_SAVED');
END
$fn$;

CREATE FUNCTION learning.advance_stage_report(p_id uuid,p_next text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,auth,learning,audit AS $fn$
DECLARE v learning.stage_report%ROWTYPE; v_class uuid; v_allowed boolean;
BEGIN
  SELECT * INTO v FROM learning.stage_report WHERE report_id=p_id FOR UPDATE;
  SELECT class_id INTO v_class FROM learning.enrollment_class WHERE enrollment_id=v.enrollment_id AND status='ACTIVE' LIMIT 1;
  v_allowed := v.status='DRAFT' AND p_next='SUBMITTED' AND v.author_teacher_person_id=auth.current_actor_person_id()
      AND learning.teacher_has_class_access(v_class,v.student_person_id)
    OR p_next IN ('PUBLISHED','RETRACTED') AND learning.current_staff_kind()='SUPERVISOR'
      AND auth.current_family_id()=v.family_id AND learning.has_learning_consent(v.student_person_id)
      AND (v.status='SUBMITTED' AND p_next='PUBLISHED' OR v.status='PUBLISHED' AND p_next='RETRACTED'
        OR v.status='RETRACTED' AND p_next='PUBLISHED');
  IF (FOUND AND v_allowed) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','LEARNING_STAGE_REPORT',p_id,false,'STAFF_CONSENT_OR_STATE_DENIED');
  END IF;
  UPDATE learning.stage_report SET status=p_next,updated_at=clock_timestamp() WHERE report_id=p_id;
  RETURN audit.record_write_decision('ADVANCE','LEARNING_STAGE_REPORT',p_id,true,'STATE_ADVANCED');
END
$fn$;

CREATE FUNCTION learning.list_published_courses()
RETURNS TABLE(course_id uuid,course_code text,title text,course_version_id uuid,version_no integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,learning
AS $fn$
SELECT c.course_id,c.course_code,c.title,v.course_version_id,v.version_no
  FROM learning.course c JOIN learning.course_version v ON v.course_id=c.course_id
 WHERE c.status='PUBLISHED' AND v.status='ACTIVE'
   AND v.effective_from<=transaction_timestamp()
   AND (v.effective_until IS NULL OR v.effective_until>transaction_timestamp())
$fn$;

CREATE FUNCTION learning.read_published_card(p_card_id uuid)
RETURNS TABLE(card_id uuid,student_person_id uuid,summary_text text,published_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,audit,learning AS $fn$
DECLARE v learning.after_class_card%ROWTYPE; v_allowed boolean; v_at timestamptz;
BEGIN
  SELECT * INTO v FROM learning.after_class_card WHERE learning.after_class_card.card_id=p_card_id;
  v_allowed := FOUND AND v.status='PUBLISHED' AND learning.can_read_sensitive(v.family_id,v.student_person_id,v.class_id);
  PERFORM audit.record_access_event('READ','LEARNING_AFTER_CLASS_CARD',p_card_id,
    CASE WHEN v_allowed THEN 'ALLOW' ELSE 'DENY' END,
    CASE WHEN v_allowed THEN 'PUBLISHED_AND_AUTHORIZED' ELSE 'CONTEXT_CONSENT_ASSIGNMENT_OR_STATE_DENIED' END);
  IF v_allowed THEN
    SELECT p.acted_at INTO v_at FROM learning.publication p
      WHERE p.card_id=p_card_id AND p.event_kind='PUBLISHED'
      ORDER BY p.acted_at DESC LIMIT 1;
    RETURN QUERY SELECT v.card_id,v.student_person_id,v.summary_text,v_at;
  END IF;
END
$fn$;

CREATE FUNCTION learning.read_published_stage_report(p_report_id uuid)
RETURNS TABLE(report_id uuid,student_person_id uuid,period_label text,summary_text text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,audit,learning AS $fn$
DECLARE v learning.stage_report%ROWTYPE; v_class uuid; v_allowed boolean;
BEGIN
  SELECT * INTO v FROM learning.stage_report WHERE learning.stage_report.report_id=p_report_id;
  SELECT class_id INTO v_class FROM learning.enrollment_class WHERE enrollment_id=v.enrollment_id AND status='ACTIVE' LIMIT 1;
  v_allowed := FOUND AND v.status='PUBLISHED' AND learning.can_read_sensitive(v.family_id,v.student_person_id,v_class);
  PERFORM audit.record_access_event('READ','LEARNING_STAGE_REPORT',p_report_id,
    CASE WHEN v_allowed THEN 'ALLOW' ELSE 'DENY' END,
    CASE WHEN v_allowed THEN 'PUBLISHED_AND_AUTHORIZED' ELSE 'CONTEXT_CONSENT_ASSIGNMENT_OR_STATE_DENIED' END);
  IF v_allowed THEN RETURN QUERY SELECT v.report_id,v.student_person_id,v.period_label,v.summary_text; END IF;
END
$fn$;

-- Every Learning table has forced RLS. Runtime access is through audited functions only.
DO $rls$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='learning' LOOP
    EXECUTE format('ALTER TABLE learning.%I ENABLE ROW LEVEL SECURITY',r.tablename);
    EXECUTE format('ALTER TABLE learning.%I FORCE ROW LEVEL SECURITY',r.tablename);
    EXECUTE format('CREATE POLICY %I ON learning.%I FOR SELECT TO phoenix_canonical_app,phoenix_canonical_reader USING (false)',
      r.tablename||'_no_direct_read',r.tablename);
  END LOOP;
END
$rls$;

REVOKE ALL ON ALL TABLES IN SCHEMA learning FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA learning FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA learning FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader;
GRANT USAGE ON SCHEMA learning TO phoenix_canonical_app,phoenix_canonical_reader;

GRANT EXECUTE ON FUNCTION learning.register_staff_principal(uuid,uuid,text),
  learning.register_teacher(uuid),learning.create_course(uuid,text,text),
  learning.advance_course(uuid,text),
  learning.create_course_version(uuid,uuid,integer,timestamptz,timestamptz),
  learning.advance_course_version(uuid,text),
  learning.create_class(uuid,uuid,text,integer,date,date),learning.advance_class(uuid,text),
  learning.assign_teacher(uuid,uuid,uuid,text,timestamptz,timestamptz),
  learning.end_teacher_assignment(uuid,boolean),
  learning.create_schedule_slot(uuid,uuid,uuid,timestamptz,timestamptz,text),
  learning.advance_schedule_slot(uuid,text),
  learning.create_enrollment(uuid,uuid,uuid,uuid,uuid,text),
  learning.advance_enrollment(uuid,uuid,text,text),learning.place_enrollment_in_class(uuid,uuid),
  learning.record_attendance(uuid,uuid,uuid,text),
  learning.correct_attendance(uuid,uuid,text,text),
  learning.save_after_class_card(uuid,uuid,uuid,text),
  learning.submit_after_class_card(uuid),
  learning.publish_after_class_card(uuid,uuid),learning.retract_after_class_card(uuid,uuid),
  learning.save_stage_report(uuid,uuid,text,text),learning.advance_stage_report(uuid,text),
  learning.list_published_courses(),learning.read_published_card(uuid),
  learning.read_published_stage_report(uuid)
TO phoenix_canonical_app;
GRANT EXECUTE ON FUNCTION learning.list_published_courses(),
  learning.read_published_card(uuid),learning.read_published_stage_report(uuid)
TO phoenix_canonical_reader;

REVOKE EXECUTE ON FUNCTION learning.reject_history_change(),learning.protect_state_transition(),
  learning.normalize_assignment_insert(),learning.current_staff_kind(),
  learning.has_learning_consent(uuid),learning.teacher_has_class_access(uuid,uuid),
  learning.can_manage_learning(),learning.can_read_sensitive(uuid,uuid,uuid)
FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader;
REVOKE EXECUTE ON FUNCTION auth.validate_context_request(uuid,uuid,uuid,text),
  consent.actor_can_grant(uuid,text,text),core.create_guardian_authority(uuid,uuid,uuid,uuid,text,text,timestamptz,text)
FROM PUBLIC;

COMMIT;
