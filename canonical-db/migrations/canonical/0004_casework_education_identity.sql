BEGIN;

CREATE TABLE casework.cases (
  case_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(case_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 300),
  status text NOT NULL CHECK (status IN ('OPEN','PAUSED','CLOSED')),
  resource_kind text CHECK (resource_kind IN ('EDUCATION_APPLICATION','IDENTITY_CASE')),
  resource_id uuid CHECK (resource_id IS NULL OR core.is_uuid_v7(resource_id)),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK ((resource_kind IS NULL) = (resource_id IS NULL))
);
CREATE TABLE casework.advisor_assignments (
  assignment_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(assignment_id)),
  case_id uuid NOT NULL REFERENCES casework.cases,
  advisor_person_id uuid NOT NULL REFERENCES core.people,
  valid_from timestamptz NOT NULL,
  valid_until timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK (valid_until > valid_from),
  UNIQUE (case_id, advisor_person_id)
);

CREATE TABLE education.applications (
  application_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(application_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  student_person_id uuid NOT NULL REFERENCES core.student_profiles(person_id),
  institution_label text NOT NULL CHECK (length(btrim(institution_label)) BETWEEN 1 AND 300),
  program_label text NOT NULL CHECK (length(btrim(program_label)) BETWEEN 1 AND 300),
  cycle_label text NOT NULL CHECK (length(btrim(cycle_label)) BETWEEN 1 AND 100),
  status text NOT NULL CHECK (status IN ('DRAFT','READY','SUBMITTED','DECIDED','WITHDRAWN')),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE TABLE education.application_status_events (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  application_id uuid NOT NULL REFERENCES education.applications,
  from_status text,
  to_status text NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  changed_by uuid REFERENCES core.people
);
CREATE TABLE education.external_facts (
  fact_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(fact_id)),
  application_id uuid NOT NULL REFERENCES education.applications,
  fact_kind text NOT NULL CHECK (fact_kind IN ('OFFICIAL_RECEIPT','DECISION')),
  source_name text NOT NULL,
  external_reference text NOT NULL,
  observed_at timestamptz NOT NULL,
  UNIQUE (application_id, fact_kind, source_name, external_reference)
);

CREATE TABLE identity.cases (
  identity_case_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(identity_case_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  case_kind text NOT NULL CHECK (length(btrim(case_kind)) BETWEEN 1 AND 100),
  status text NOT NULL CHECK (status IN ('DRAFT','EVIDENCE_PENDING','UNDER_REVIEW','RESOLVED','CLOSED')),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE TABLE identity.case_status_events (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  identity_case_id uuid NOT NULL REFERENCES identity.cases,
  from_status text,
  to_status text NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  changed_by uuid REFERENCES core.people
);
CREATE TABLE identity.external_facts (
  fact_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(fact_id)),
  identity_case_id uuid NOT NULL REFERENCES identity.cases,
  fact_kind text NOT NULL CHECK (fact_kind IN ('OFFICIAL_RECEIPT','DECISION')),
  source_name text NOT NULL,
  external_reference text NOT NULL,
  observed_at timestamptz NOT NULL,
  UNIQUE (identity_case_id, fact_kind, source_name, external_reference)
);

CREATE FUNCTION casework.has_active_advisor_assignment(p_resource_kind text, p_resource_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, casework
RETURN EXISTS (
  SELECT 1
  FROM casework.cases c
  JOIN casework.advisor_assignments a ON a.case_id = c.case_id
  WHERE c.family_id = auth.current_family_id()
    AND c.resource_kind = p_resource_kind AND c.resource_id = p_resource_id
    AND a.advisor_person_id = auth.current_actor_person_id()
    AND a.valid_from <= transaction_timestamp() AND a.valid_until > transaction_timestamp()
    AND a.revoked_at IS NULL
);
CREATE FUNCTION casework.is_current_advisor_for_case(p_case_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, casework
RETURN EXISTS (
  SELECT 1 FROM casework.advisor_assignments
  WHERE case_id = p_case_id AND advisor_person_id = auth.current_actor_person_id()
    AND valid_from <= transaction_timestamp() AND valid_until > transaction_timestamp()
    AND revoked_at IS NULL
);
CREATE FUNCTION integration.has_active_channel_grant(p_subject_person_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, integration
RETURN EXISTS (
  SELECT 1 FROM integration.channel_grants
  WHERE principal_id = auth.current_principal_id()
    AND family_id = auth.current_family_id()
    AND subject_person_id = p_subject_person_id
    AND channel = auth.current_channel()
    AND valid_from <= transaction_timestamp() AND valid_until > transaction_timestamp()
    AND revoked_at IS NULL
);

CREATE OR REPLACE FUNCTION auth.bind_context(
  p_principal_id uuid,
  p_actor_person_id uuid,
  p_family_id uuid,
  p_channel text,
  p_expires_at timestamptz,
  p_request_nonce uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration, casework
AS $fn$
BEGIN
  IF p_expires_at <= clock_timestamp() OR p_expires_at > clock_timestamp() + interval '1 day' THEN
    RAISE EXCEPTION 'CONTEXT_EXPIRY_INVALID';
  END IF;
  IF p_channel NOT IN ('FAMILY','ADVISOR','PARTNER','INTERNAL') THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_INVALID';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.principals
    WHERE principal_id = p_principal_id AND person_id = p_actor_person_id AND status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'CONTEXT_PRINCIPAL_INVALID';
  END IF;
  IF p_channel = 'FAMILY' AND NOT EXISTS (
    SELECT 1 FROM core.family_memberships
    WHERE family_id = p_family_id AND person_id = p_actor_person_id
      AND valid_from <= clock_timestamp() AND (valid_until IS NULL OR valid_until > clock_timestamp())
  ) THEN
    RAISE EXCEPTION 'CONTEXT_FAMILY_MEMBERSHIP_INVALID';
  END IF;
  IF p_channel = 'ADVISOR' AND NOT EXISTS (
    SELECT 1 FROM casework.cases c JOIN casework.advisor_assignments a ON a.case_id = c.case_id
    WHERE c.family_id = p_family_id AND a.advisor_person_id = p_actor_person_id
      AND a.valid_from <= clock_timestamp() AND a.valid_until > clock_timestamp() AND a.revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'CONTEXT_ADVISOR_ASSIGNMENT_INVALID';
  END IF;
  IF p_channel = 'PARTNER' AND NOT EXISTS (
    SELECT 1 FROM integration.channel_grants
    WHERE principal_id = p_principal_id AND family_id = p_family_id
      AND valid_from <= clock_timestamp() AND valid_until > clock_timestamp() AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_GRANT_INVALID';
  END IF;
  IF p_channel = 'INTERNAL' AND NOT EXISTS (
    SELECT 1 FROM auth.principals WHERE principal_id = p_principal_id AND principal_kind = 'SERVICE'
  ) THEN
    RAISE EXCEPTION 'CONTEXT_INTERNAL_PRINCIPAL_INVALID';
  END IF;
  INSERT INTO auth.session_contexts(backend_pid, principal_id, actor_person_id, family_id, channel, request_nonce, expires_at)
  VALUES (pg_backend_pid(), p_principal_id, p_actor_person_id, p_family_id, p_channel, p_request_nonce, p_expires_at)
  ON CONFLICT (backend_pid) DO UPDATE SET
    principal_id = excluded.principal_id,
    actor_person_id = excluded.actor_person_id,
    family_id = excluded.family_id,
    channel = excluded.channel,
    request_nonce = excluded.request_nonce,
    expires_at = excluded.expires_at,
    bound_at = clock_timestamp();
END
$fn$;

CREATE FUNCTION education.audit_application_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, education
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO education.application_status_events(application_id, from_status, to_status, changed_by)
    VALUES (NEW.application_id, CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END, NEW.status, auth.current_actor_person_id());
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER audit_application_status AFTER INSERT OR UPDATE ON education.applications
FOR EACH ROW EXECUTE FUNCTION education.audit_application_status();
CREATE FUNCTION education.touch_application() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END
$fn$;
CREATE TRIGGER touch_application BEFORE UPDATE ON education.applications
FOR EACH ROW EXECUTE FUNCTION education.touch_application();

CREATE FUNCTION identity.audit_case_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, identity
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO identity.case_status_events(identity_case_id, from_status, to_status, changed_by)
    VALUES (NEW.identity_case_id, CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END, NEW.status, auth.current_actor_person_id());
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER audit_identity_status AFTER INSERT OR UPDATE ON identity.cases
FOR EACH ROW EXECUTE FUNCTION identity.audit_case_status();
CREATE FUNCTION identity.touch_case() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END
$fn$;
CREATE TRIGGER touch_identity_case BEFORE UPDATE ON identity.cases
FOR EACH ROW EXECUTE FUNCTION identity.touch_case();

ALTER TABLE casework.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE casework.advisor_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.application_status_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE education.external_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.case_status_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.external_facts ENABLE ROW LEVEL SECURITY;

CREATE POLICY cases_read ON casework.cases FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (
    family_id = auth.current_family_id()
    AND (
      core.current_actor_is_family_member()
      OR casework.is_current_advisor_for_case(case_id)
    )
  );
CREATE POLICY assignments_read ON casework.advisor_assignments FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (
    advisor_person_id = auth.current_actor_person_id()
    OR core.current_actor_is_family_member()
  );
CREATE POLICY applications_read ON education.applications FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (
    family_id = auth.current_family_id()
    AND (
      core.current_actor_is_family_member()
      OR (
        casework.has_active_advisor_assignment('EDUCATION_APPLICATION', application_id)
        AND consent.has_active_consent(student_person_id, 'EDUCATION_CASE', 'EDUCATION')
      )
    )
  );
CREATE POLICY application_events_read ON education.application_status_events FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (EXISTS (SELECT 1 FROM education.applications a WHERE a.application_id = application_status_events.application_id));
CREATE POLICY education_facts_read ON education.external_facts FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (EXISTS (SELECT 1 FROM education.applications a WHERE a.application_id = external_facts.application_id));
CREATE POLICY identity_cases_read ON identity.cases FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (
    family_id = auth.current_family_id()
    AND (
      core.current_actor_is_family_member()
      OR (
        casework.has_active_advisor_assignment('IDENTITY_CASE', identity_case_id)
        AND consent.has_active_consent(subject_person_id, 'IDENTITY_CASE', 'IDENTITY_SENSITIVE')
      )
      OR (
        integration.has_active_channel_grant(subject_person_id)
        AND consent.has_active_consent(subject_person_id, 'IDENTITY_CASE', 'IDENTITY_SENSITIVE')
      )
    )
  );
CREATE POLICY identity_events_read ON identity.case_status_events FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (EXISTS (SELECT 1 FROM identity.cases c WHERE c.identity_case_id = case_status_events.identity_case_id));
CREATE POLICY identity_facts_read ON identity.external_facts FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (EXISTS (SELECT 1 FROM identity.cases c WHERE c.identity_case_id = external_facts.identity_case_id));

REVOKE INSERT ON audit.access_events FROM phoenix_canonical_app;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA casework, education, identity, integration FROM PUBLIC;
GRANT EXECUTE ON FUNCTION casework.has_active_advisor_assignment(text,uuid), casework.is_current_advisor_for_case(uuid), integration.has_active_channel_grant(uuid) TO phoenix_canonical_app, phoenix_canonical_reader;

GRANT SELECT ON casework.cases, casework.advisor_assignments, education.applications, education.application_status_events, education.external_facts, identity.cases, identity.case_status_events, identity.external_facts TO phoenix_canonical_app, phoenix_canonical_reader;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA education, identity TO phoenix_canonical_app;

COMMIT;
