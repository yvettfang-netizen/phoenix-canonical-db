BEGIN;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_backup_runtime') THEN
    CREATE ROLE phoenix_canonical_backup_runtime NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
  END IF;
END
$roles$;
GRANT pg_read_all_data TO phoenix_canonical_backup_runtime WITH INHERIT TRUE, SET FALSE;
DO $database_grants$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO phoenix_canonical_backup_runtime', current_database());
END
$database_grants$;

-- F-01: bind a context to the backend PID and the backend start timestamp.
-- Existing context rows are ephemeral and are deliberately invalidated when this
-- migration is applied; no business data is touched.
ALTER TABLE auth.session_contexts
  ADD COLUMN IF NOT EXISTS backend_start timestamptz;
DELETE FROM auth.session_contexts;
ALTER TABLE auth.session_contexts
  ALTER COLUMN backend_start SET NOT NULL;
CREATE INDEX IF NOT EXISTS session_contexts_backend_identity_idx
  ON auth.session_contexts (backend_pid, backend_start);

ALTER TABLE casework.advisor_assignments
  ADD COLUMN IF NOT EXISTS lifecycle_status text NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE core.guardian_authorities
  ADD COLUMN IF NOT EXISTS lifecycle_status text NOT NULL DEFAULT 'ACTIVE';
UPDATE casework.advisor_assignments
   SET lifecycle_status = CASE WHEN revoked_at IS NOT NULL THEN 'REVOKED' WHEN valid_until <= clock_timestamp() THEN 'EXPIRED' ELSE 'ACTIVE' END;
UPDATE core.guardian_authorities
   SET lifecycle_status = CASE WHEN revoked_at IS NOT NULL THEN 'REVOKED' WHEN valid_until <= clock_timestamp() THEN 'EXPIRED' ELSE 'ACTIVE' END;
ALTER TABLE casework.advisor_assignments
  ADD CONSTRAINT advisor_assignment_lifecycle_status_ck
  CHECK (lifecycle_status IN ('ACTIVE','REVOKED','EXPIRED'));
ALTER TABLE core.guardian_authorities
  ADD CONSTRAINT guardian_authority_lifecycle_status_ck
  CHECK (lifecycle_status IN ('ACTIVE','REVOKED','EXPIRED'));
CREATE UNIQUE INDEX IF NOT EXISTS advisor_assignments_active_unique
  ON casework.advisor_assignments (case_id, advisor_person_id)
  WHERE lifecycle_status = 'ACTIVE';
CREATE UNIQUE INDEX IF NOT EXISTS guardian_authorities_active_unique
  ON core.guardian_authorities (family_id, guardian_person_id, subject_person_id, scope)
  WHERE lifecycle_status = 'ACTIVE';

CREATE OR REPLACE FUNCTION auth.current_backend_start() RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog
RETURN (SELECT backend_start FROM pg_catalog.pg_stat_activity WHERE pid = pg_backend_pid());

CREATE OR REPLACE FUNCTION auth.cleanup_stale_contexts() RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $fn$
DECLARE
  removed integer;
BEGIN
  DELETE FROM auth.session_contexts s
   WHERE s.expires_at <= clock_timestamp()
      OR NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_stat_activity a
         WHERE a.pid = s.backend_pid
           AND a.backend_start = s.backend_start
      );
  GET DIAGNOSTICS removed = ROW_COUNT;
  RETURN removed;
END
$fn$;

CREATE TABLE auth.context_exchange_tickets (
  ticket_id uuid PRIMARY KEY,
  principal_id uuid NOT NULL REFERENCES auth.principals,
  actor_person_id uuid NOT NULL REFERENCES core.people,
  family_id uuid NOT NULL REFERENCES core.families,
  channel text NOT NULL CHECK (channel IN ('FAMILY','ADVISOR','PARTNER','INTERNAL')),
  request_nonce uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  intended_principal_id uuid NOT NULL REFERENCES auth.principals,
  CHECK (expires_at <= issued_at + interval '60 seconds')
);
REVOKE ALL ON auth.context_exchange_tickets FROM PUBLIC, phoenix_canonical_app,
  phoenix_canonical_reader, phoenix_canonical_context_binder;

CREATE OR REPLACE FUNCTION auth.validate_context_request(
  p_principal_id uuid,
  p_actor_person_id uuid,
  p_family_id uuid,
  p_channel text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration, casework
AS $fn$
BEGIN
  IF p_channel NOT IN ('FAMILY','ADVISOR','PARTNER','INTERNAL') THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_INVALID';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.principals
     WHERE principal_id = p_principal_id
       AND person_id = p_actor_person_id
       AND status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'CONTEXT_PRINCIPAL_INVALID';
  END IF;
  IF p_channel = 'FAMILY' AND NOT EXISTS (
    SELECT 1 FROM core.family_memberships
     WHERE family_id = p_family_id AND person_id = p_actor_person_id
       AND valid_from <= clock_timestamp()
       AND (valid_until IS NULL OR valid_until > clock_timestamp())
  ) THEN
    RAISE EXCEPTION 'CONTEXT_FAMILY_MEMBERSHIP_INVALID';
  END IF;
  IF p_channel = 'ADVISOR' AND NOT EXISTS (
    SELECT 1
      FROM casework.cases c
      JOIN casework.advisor_assignments a ON a.case_id = c.case_id
     WHERE c.family_id = p_family_id
       AND a.advisor_person_id = p_actor_person_id
       AND a.valid_from <= clock_timestamp()
       AND a.valid_until > clock_timestamp()
       AND a.revoked_at IS NULL
       AND a.lifecycle_status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'CONTEXT_ADVISOR_ASSIGNMENT_INVALID';
  END IF;
  IF p_channel = 'PARTNER' AND NOT EXISTS (
    SELECT 1 FROM integration.channel_grants
     WHERE principal_id = p_principal_id AND family_id = p_family_id
       AND valid_from <= clock_timestamp() AND valid_until > clock_timestamp()
       AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_GRANT_INVALID';
  END IF;
  IF p_channel = 'INTERNAL' AND NOT EXISTS (
    SELECT 1 FROM auth.principals
     WHERE principal_id = p_principal_id AND principal_kind = 'SERVICE'
  ) THEN
    RAISE EXCEPTION 'CONTEXT_INTERNAL_PRINCIPAL_INVALID';
  END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION auth.current_principal_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (
  SELECT principal_id FROM auth.session_contexts
   WHERE backend_pid = pg_backend_pid()
     AND backend_start = auth.current_backend_start()
     AND expires_at > transaction_timestamp()
);
CREATE OR REPLACE FUNCTION auth.current_actor_person_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (
  SELECT actor_person_id FROM auth.session_contexts
   WHERE backend_pid = pg_backend_pid()
     AND backend_start = auth.current_backend_start()
     AND expires_at > transaction_timestamp()
);
CREATE OR REPLACE FUNCTION auth.current_family_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (
  SELECT family_id FROM auth.session_contexts
   WHERE backend_pid = pg_backend_pid()
     AND backend_start = auth.current_backend_start()
     AND expires_at > transaction_timestamp()
);
CREATE OR REPLACE FUNCTION auth.current_channel() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (
  SELECT channel FROM auth.session_contexts
   WHERE backend_pid = pg_backend_pid()
     AND backend_start = auth.current_backend_start()
     AND expires_at > transaction_timestamp()
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
DECLARE
  v_backend_start timestamptz;
BEGIN
  IF p_expires_at <= clock_timestamp() OR p_expires_at > clock_timestamp() + interval '1 day' THEN
    RAISE EXCEPTION 'CONTEXT_EXPIRY_INVALID';
  END IF;
  PERFORM auth.cleanup_stale_contexts();
  PERFORM auth.validate_context_request(p_principal_id, p_actor_person_id, p_family_id, p_channel);
  SELECT backend_start INTO v_backend_start
    FROM pg_catalog.pg_stat_activity WHERE pid = pg_backend_pid();
  IF v_backend_start IS NULL THEN RAISE EXCEPTION 'CONTEXT_BACKEND_NOT_FOUND'; END IF;
  INSERT INTO auth.session_contexts(backend_pid, backend_start, principal_id, actor_person_id, family_id, channel, request_nonce, expires_at)
  VALUES (pg_backend_pid(), v_backend_start, p_principal_id, p_actor_person_id, p_family_id, p_channel, p_request_nonce, p_expires_at)
  ON CONFLICT (backend_pid) DO UPDATE SET
    backend_start = excluded.backend_start,
    principal_id = excluded.principal_id,
    actor_person_id = excluded.actor_person_id,
    family_id = excluded.family_id,
    channel = excluded.channel,
    request_nonce = excluded.request_nonce,
    expires_at = excluded.expires_at,
    bound_at = clock_timestamp();
END
$fn$;

CREATE OR REPLACE FUNCTION auth.clear_context() RETURNS void
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $fn$
  DELETE FROM auth.session_contexts
   WHERE backend_pid = pg_backend_pid()
     AND backend_start = auth.current_backend_start()
$fn$;

-- F-02: a short-lived, one-use ticket transfers an approved context from the
-- binder connection to a separately authenticated application connection.
CREATE OR REPLACE FUNCTION auth.issue_context_ticket(
  p_principal_id uuid,
  p_actor_person_id uuid,
  p_family_id uuid,
  p_channel text,
  p_expires_at timestamptz,
  p_request_nonce uuid,
  p_intended_principal_id uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration, casework
AS $fn$
DECLARE
  v_ticket uuid := gen_random_uuid();
BEGIN
  IF p_expires_at <= clock_timestamp() OR p_expires_at > clock_timestamp() + interval '60 seconds' THEN
    RAISE EXCEPTION 'CONTEXT_TICKET_EXPIRY_INVALID';
  END IF;
  PERFORM auth.validate_context_request(p_principal_id, p_actor_person_id, p_family_id, p_channel);
  IF NOT EXISTS (SELECT 1 FROM auth.principals WHERE principal_id = p_intended_principal_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'CONTEXT_TICKET_TARGET_INVALID';
  END IF;
  INSERT INTO auth.context_exchange_tickets(ticket_id, principal_id, actor_person_id, family_id, channel, request_nonce, expires_at, intended_principal_id)
  VALUES (v_ticket, p_principal_id, p_actor_person_id, p_family_id, p_channel, p_request_nonce, p_expires_at, p_intended_principal_id);
  RETURN v_ticket;
END
$fn$;

CREATE OR REPLACE FUNCTION auth.redeem_context_ticket(
  p_ticket_id uuid,
  p_expected_principal_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, pg_catalog
AS $fn$
DECLARE
  v_ticket auth.context_exchange_tickets%ROWTYPE;
  v_backend_start timestamptz;
BEGIN
  PERFORM auth.cleanup_stale_contexts();
  DELETE FROM auth.context_exchange_tickets
   WHERE ticket_id = p_ticket_id
     AND intended_principal_id = p_expected_principal_id
     AND expires_at > clock_timestamp()
   RETURNING * INTO v_ticket;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED'; END IF;
  SELECT backend_start INTO v_backend_start
    FROM pg_catalog.pg_stat_activity WHERE pid = pg_backend_pid();
  IF v_backend_start IS NULL THEN RAISE EXCEPTION 'CONTEXT_BACKEND_NOT_FOUND'; END IF;
  INSERT INTO auth.session_contexts(backend_pid, backend_start, principal_id, actor_person_id, family_id, channel, request_nonce, expires_at)
  VALUES (pg_backend_pid(), v_backend_start, v_ticket.principal_id, v_ticket.actor_person_id, v_ticket.family_id, v_ticket.channel, v_ticket.request_nonce, v_ticket.expires_at)
  ON CONFLICT (backend_pid) DO UPDATE SET
    backend_start = excluded.backend_start,
    principal_id = excluded.principal_id,
    actor_person_id = excluded.actor_person_id,
    family_id = excluded.family_id,
    channel = excluded.channel,
    request_nonce = excluded.request_nonce,
    expires_at = excluded.expires_at,
    bound_at = clock_timestamp();
END
$fn$;

-- F-03/F-04: scope assignment, family, person and student reads by channel.
CREATE OR REPLACE FUNCTION core.can_read_subject_basics(p_person_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, casework, integration
RETURN CASE auth.current_channel()
  WHEN 'FAMILY' THEN core.current_actor_is_family_member() AND core.person_in_current_family(p_person_id)
  WHEN 'ADVISOR' THEN EXISTS (
    SELECT 1
      FROM casework.cases c
      JOIN casework.advisor_assignments a ON a.case_id = c.case_id
     WHERE c.family_id = auth.current_family_id()
       AND c.subject_person_id = p_person_id
       AND a.advisor_person_id = auth.current_actor_person_id()
       AND a.valid_from <= transaction_timestamp() AND a.valid_until > transaction_timestamp()
       AND a.revoked_at IS NULL AND a.lifecycle_status = 'ACTIVE'
  )
  WHEN 'PARTNER' THEN integration.has_active_channel_grant(p_person_id)
  ELSE false
END;

DROP POLICY IF EXISTS assignments_read ON casework.advisor_assignments;
CREATE POLICY assignments_read ON casework.advisor_assignments FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (
    EXISTS (
      SELECT 1 FROM casework.cases c
       WHERE c.case_id = advisor_assignments.case_id
         AND c.family_id = auth.current_family_id()
         AND (core.current_actor_is_family_member() OR advisor_person_id = auth.current_actor_person_id())
    )
  );

DROP POLICY IF EXISTS people_read ON core.people;
CREATE POLICY people_read ON core.people FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (core.person_in_current_family(person_id) AND core.can_read_subject_basics(person_id));
DROP POLICY IF EXISTS student_profiles_read ON core.student_profiles;
CREATE POLICY student_profiles_read ON core.student_profiles FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (core.can_read_subject_basics(person_id));
DROP POLICY IF EXISTS families_read ON core.families;
CREATE POLICY families_read ON core.families FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id() AND auth.current_channel() = 'FAMILY' AND core.current_actor_is_family_member());
DROP POLICY IF EXISTS memberships_read ON core.family_memberships;
CREATE POLICY memberships_read ON core.family_memberships FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id() AND core.can_read_subject_basics(person_id));
DROP POLICY IF EXISTS guardian_authorities_read ON core.guardian_authorities;
CREATE POLICY guardian_authorities_read ON core.guardian_authorities FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id() AND auth.current_channel() = 'FAMILY' AND
    (guardian_person_id = auth.current_actor_person_id() OR subject_person_id = auth.current_actor_person_id()));

-- F-05: audit rows are written only by SECURITY DEFINER authorization functions.
REVOKE EXECUTE ON FUNCTION audit.record_access_event(text,text,uuid,text,text)
  FROM PUBLIC, phoenix_canonical_app, phoenix_canonical_reader;
REVOKE INSERT ON audit.access_events FROM phoenix_canonical_app, phoenix_canonical_reader;

-- F-06: historical grants and assignments cannot be reactivated.  Current
-- records are the only rows covered by the partial uniqueness indexes.
DO $drop_unique$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT conrelid::regclass AS rel, conname
      FROM pg_constraint
     WHERE contype = 'u'
       AND conrelid IN ('consent.grants'::regclass, 'casework.advisor_assignments'::regclass, 'core.guardian_authorities'::regclass)
       AND pg_get_constraintdef(oid) IN (
         'UNIQUE (family_id, grantee_person_id, subject_person_id, purpose, data_class)',
         'UNIQUE (case_id, advisor_person_id)',
         'UNIQUE (family_id, guardian_person_id, subject_person_id, scope)'
       )
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.rel, r.conname);
  END LOOP;
END
$drop_unique$;
CREATE UNIQUE INDEX IF NOT EXISTS consent_grants_active_unique
  ON consent.grants (family_id, grantee_person_id, subject_person_id, purpose, data_class)
  WHERE status = 'ACTIVE';

CREATE OR REPLACE FUNCTION casework.protect_advisor_assignment() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF ROW(NEW.assignment_id, NEW.case_id, NEW.advisor_person_id, NEW.valid_from)
     IS DISTINCT FROM ROW(OLD.assignment_id, OLD.case_id, OLD.advisor_person_id, OLD.valid_from)
  THEN RAISE EXCEPTION 'ADVISOR_ASSIGNMENT_IDENTITY_IMMUTABLE'; END IF;
  IF OLD.lifecycle_status <> 'ACTIVE' AND NEW.lifecycle_status = 'ACTIVE' THEN
    RAISE EXCEPTION 'ADVISOR_ASSIGNMENT_REACTIVATION_DENIED';
  END IF;
  IF NEW.revoked_at IS NOT NULL THEN NEW.lifecycle_status := 'REVOKED';
  ELSIF NEW.valid_until <= clock_timestamp() THEN NEW.lifecycle_status := 'EXPIRED';
  ELSE NEW.lifecycle_status := 'ACTIVE'; END IF;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS protect_advisor_assignment ON casework.advisor_assignments;
CREATE TRIGGER protect_advisor_assignment BEFORE UPDATE ON casework.advisor_assignments
FOR EACH ROW EXECUTE FUNCTION casework.protect_advisor_assignment();

CREATE OR REPLACE FUNCTION core.protect_guardian_authority() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF ROW(NEW.authority_id, NEW.family_id, NEW.guardian_person_id, NEW.subject_person_id, NEW.scope, NEW.valid_from)
     IS DISTINCT FROM ROW(OLD.authority_id, OLD.family_id, OLD.guardian_person_id, OLD.subject_person_id, OLD.scope, OLD.valid_from)
  THEN RAISE EXCEPTION 'GUARDIAN_AUTHORITY_IDENTITY_IMMUTABLE'; END IF;
  IF OLD.lifecycle_status <> 'ACTIVE' AND NEW.lifecycle_status = 'ACTIVE' THEN
    RAISE EXCEPTION 'GUARDIAN_AUTHORITY_REACTIVATION_DENIED';
  END IF;
  IF NEW.revoked_at IS NOT NULL THEN NEW.lifecycle_status := 'REVOKED';
  ELSIF NEW.valid_until <= clock_timestamp() THEN NEW.lifecycle_status := 'EXPIRED';
  ELSE NEW.lifecycle_status := 'ACTIVE'; END IF;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS protect_guardian_authority ON core.guardian_authorities;
CREATE TRIGGER protect_guardian_authority BEFORE UPDATE ON core.guardian_authorities
FOR EACH ROW EXECUTE FUNCTION core.protect_guardian_authority();

CREATE OR REPLACE FUNCTION casework.is_current_advisor_for_case(p_case_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, casework
RETURN EXISTS (
  SELECT 1 FROM casework.advisor_assignments
   WHERE case_id = p_case_id AND advisor_person_id = auth.current_actor_person_id()
     AND valid_from <= transaction_timestamp() AND valid_until > transaction_timestamp()
     AND revoked_at IS NULL AND lifecycle_status = 'ACTIVE'
);

-- F-07: a manifest target must exist and carry the same family and subject.
CREATE OR REPLACE FUNCTION docs.validate_submission_target() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, docs, education, identity
AS $fn$
DECLARE v_family uuid; v_subject uuid;
BEGIN
  IF NEW.target_kind = 'EDUCATION_APPLICATION' THEN
    SELECT family_id, student_person_id INTO v_family, v_subject
      FROM education.applications WHERE application_id = NEW.target_id;
  ELSE
    SELECT family_id, subject_person_id INTO v_family, v_subject
      FROM identity.cases WHERE identity_case_id = NEW.target_id;
  END IF;
  IF v_family IS NULL OR v_subject IS NULL THEN RAISE EXCEPTION 'SUBMISSION_TARGET_NOT_FOUND'; END IF;
  IF v_family <> NEW.family_id OR v_subject <> NEW.subject_person_id THEN
    RAISE EXCEPTION 'SUBMISSION_TARGET_FAMILY_OR_SUBJECT_MISMATCH';
  END IF;
  RETURN NEW;
END
$fn$;
DROP TRIGGER IF EXISTS validate_submission_target ON docs.submission_manifests;
CREATE TRIGGER validate_submission_target BEFORE INSERT OR UPDATE OF family_id, subject_person_id, target_kind, target_id
ON docs.submission_manifests FOR EACH ROW EXECUTE FUNCTION docs.validate_submission_target();

-- F-09: guardian scope is exact-match. GENERAL does not cover IDENTITY_SENSITIVE.
CREATE OR REPLACE FUNCTION core.has_verified_guardian_authority(p_subject_person_id uuid, p_scope text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, core
RETURN EXISTS (
  SELECT 1 FROM core.guardian_authorities
   WHERE family_id = auth.current_family_id()
     AND guardian_person_id = auth.current_actor_person_id()
     AND subject_person_id = p_subject_person_id
     AND evidence_level = 'VERIFIED'
     AND scope = p_scope
     AND valid_from <= transaction_timestamp() AND valid_until > transaction_timestamp()
     AND revoked_at IS NULL AND lifecycle_status = 'ACTIVE'
);
CREATE OR REPLACE FUNCTION docs.can_read_document(p_subject_person_id uuid, p_data_class text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, integration
RETURN
  consent.has_active_consent(p_subject_person_id, 'DOCUMENT_READ', p_data_class)
  AND CASE auth.current_channel()
    WHEN 'FAMILY' THEN (
      auth.current_actor_person_id() = p_subject_person_id
      OR core.has_verified_guardian_authority(
        p_subject_person_id,
        CASE p_data_class WHEN 'EDUCATION' THEN 'EDUCATION' WHEN 'IDENTITY_SENSITIVE' THEN 'IDENTITY' ELSE 'GENERAL' END
      )
    )
    WHEN 'ADVISOR' THEN true
    WHEN 'PARTNER' THEN integration.has_active_channel_grant(p_subject_person_id)
    ELSE false
  END;

-- Health may inspect the migration ledger, but it receives no DDL capability.
GRANT SELECT ON canonical_migrations.applied TO phoenix_canonical_reader;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA auth FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth.current_backend_start(), auth.current_principal_id(), auth.current_actor_person_id(), auth.current_family_id(), auth.current_channel() TO phoenix_canonical_app, phoenix_canonical_reader;
GRANT EXECUTE ON FUNCTION auth.cleanup_stale_contexts(), auth.bind_context(uuid,uuid,uuid,text,timestamptz,uuid), auth.clear_context() TO phoenix_canonical_context_binder;
GRANT EXECUTE ON FUNCTION auth.clear_context() TO phoenix_canonical_app, phoenix_canonical_reader;
GRANT EXECUTE ON FUNCTION auth.issue_context_ticket(uuid,uuid,uuid,text,timestamptz,uuid,uuid) TO phoenix_canonical_context_binder;
GRANT EXECUTE ON FUNCTION auth.redeem_context_ticket(uuid,uuid) TO phoenix_canonical_app;

COMMIT;
