BEGIN;

CREATE SCHEMA IF NOT EXISTS auth;
REVOKE ALL ON SCHEMA auth FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA auth TO phoenix_canonical_migrator;
GRANT USAGE ON SCHEMA auth TO phoenix_canonical_app, phoenix_canonical_reader;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_context_binder') THEN
    CREATE ROLE phoenix_canonical_context_binder NOLOGIN NOINHERIT;
  END IF;
END
$roles$;
DO $database_grants$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO phoenix_canonical_context_binder', current_database());
END
$database_grants$;
GRANT USAGE ON SCHEMA auth TO phoenix_canonical_context_binder;

CREATE FUNCTION core.is_uuid_v7(value uuid) RETURNS boolean
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
RETURN substring(value::text, 15, 1) = '7' AND substring(value::text, 20, 1) IN ('8','9','a','b');

CREATE TABLE core.people (
  person_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(person_id)),
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 200),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE TABLE core.families (
  family_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(family_id)),
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 200),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE TABLE core.family_memberships (
  membership_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(membership_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  person_id uuid NOT NULL REFERENCES core.people,
  membership_role text NOT NULL CHECK (membership_role IN ('PRIMARY','MEMBER')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  UNIQUE (family_id, person_id)
);
CREATE TABLE core.student_profiles (
  person_id uuid PRIMARY KEY REFERENCES core.people,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE TABLE core.guardian_authorities (
  authority_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(authority_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  guardian_person_id uuid NOT NULL REFERENCES core.people,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  evidence_level text NOT NULL CHECK (evidence_level IN ('VERIFIED','SELF_DECLARED_LEGACY')),
  scope text NOT NULL CHECK (scope IN ('GENERAL','EDUCATION','IDENTITY')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK (guardian_person_id <> subject_person_id),
  CHECK (valid_until > valid_from),
  UNIQUE (family_id, guardian_person_id, subject_person_id, scope)
);

CREATE TABLE auth.principals (
  principal_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(principal_id)),
  person_id uuid NOT NULL UNIQUE REFERENCES core.people,
  principal_kind text NOT NULL CHECK (principal_kind IN ('FAMILY','ADVISOR','CHANNEL','SERVICE')),
  status text NOT NULL CHECK (status IN ('ACTIVE','DISABLED')),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE TABLE auth.session_contexts (
  backend_pid integer PRIMARY KEY,
  principal_id uuid NOT NULL REFERENCES auth.principals,
  actor_person_id uuid NOT NULL REFERENCES core.people,
  family_id uuid NOT NULL REFERENCES core.families,
  channel text NOT NULL CHECK (channel IN ('FAMILY','ADVISOR','PARTNER','INTERNAL')),
  request_nonce uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  bound_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE consent.grants (
  consent_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(consent_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  grantor_person_id uuid NOT NULL REFERENCES core.people,
  grantee_person_id uuid NOT NULL REFERENCES core.people,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  purpose text NOT NULL CHECK (purpose IN ('DOCUMENT_READ','EDUCATION_CASE','IDENTITY_CASE')),
  data_class text NOT NULL CHECK (data_class IN ('GENERAL','EDUCATION','IDENTITY_SENSITIVE')),
  status text NOT NULL CHECK (status IN ('ACTIVE','WITHDRAWN','EXPIRED')),
  granted_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  withdrawn_at timestamptz,
  CHECK (expires_at > granted_at),
  CHECK ((status = 'WITHDRAWN') = (withdrawn_at IS NOT NULL)),
  UNIQUE (family_id, grantee_person_id, subject_person_id, purpose, data_class)
);

CREATE TABLE integration.public_ids (
  entity_kind text NOT NULL CHECK (entity_kind IN ('PERSON','FAMILY','STUDENT_PROFILE','GUARDIAN_AUTHORITY')),
  public_id text NOT NULL CHECK (public_id ~ '^(per|fam|stu|gdn)_[0-9a-f]{32}$'),
  canonical_id uuid NOT NULL CHECK (core.is_uuid_v7(canonical_id)),
  issued_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  PRIMARY KEY (entity_kind, public_id),
  UNIQUE (entity_kind, canonical_id)
);
CREATE TABLE integration.legacy_id_mappings (
  mapping_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(mapping_id)),
  source_system text NOT NULL CHECK (length(btrim(source_system)) BETWEEN 1 AND 100),
  entity_kind text NOT NULL CHECK (entity_kind IN ('PERSON','FAMILY','STUDENT_PROFILE','GUARDIAN_AUTHORITY')),
  legacy_id text NOT NULL CHECK (length(btrim(legacy_id)) BETWEEN 1 AND 300),
  canonical_id uuid NOT NULL CHECK (core.is_uuid_v7(canonical_id)),
  mapping_status text NOT NULL CHECK (mapping_status IN ('PENDING','VERIFIED','REVOKED','SUPERSEDED')),
  evidence_ref text NOT NULL,
  decided_by uuid REFERENCES core.people,
  decided_at timestamptz,
  CHECK ((mapping_status = 'VERIFIED') = (decided_by IS NOT NULL AND decided_at IS NOT NULL))
);
CREATE UNIQUE INDEX one_verified_legacy_mapping
  ON integration.legacy_id_mappings(source_system, entity_kind, legacy_id)
  WHERE mapping_status = 'VERIFIED';
CREATE TABLE integration.channel_grants (
  channel_grant_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(channel_grant_id)),
  principal_id uuid NOT NULL REFERENCES auth.principals,
  family_id uuid NOT NULL REFERENCES core.families,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  channel text NOT NULL,
  valid_from timestamptz NOT NULL,
  valid_until timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK (valid_until > valid_from),
  UNIQUE (principal_id, family_id, subject_person_id, channel)
);

CREATE TABLE audit.access_events (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  backend_pid integer NOT NULL,
  principal_id uuid,
  actor_person_id uuid,
  family_id uuid,
  action text NOT NULL,
  resource_kind text NOT NULL,
  resource_id uuid,
  decision text NOT NULL CHECK (decision IN ('ALLOW','DENY')),
  reason_code text NOT NULL
);

CREATE FUNCTION auth.current_principal_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (SELECT principal_id FROM auth.session_contexts WHERE backend_pid = pg_backend_pid() AND expires_at > transaction_timestamp());
CREATE FUNCTION auth.current_actor_person_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (SELECT actor_person_id FROM auth.session_contexts WHERE backend_pid = pg_backend_pid() AND expires_at > transaction_timestamp());
CREATE FUNCTION auth.current_family_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (SELECT family_id FROM auth.session_contexts WHERE backend_pid = pg_backend_pid() AND expires_at > transaction_timestamp());
CREATE FUNCTION auth.current_channel() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (SELECT channel FROM auth.session_contexts WHERE backend_pid = pg_backend_pid() AND expires_at > transaction_timestamp());

CREATE FUNCTION auth.bind_context(
  p_principal_id uuid,
  p_actor_person_id uuid,
  p_family_id uuid,
  p_channel text,
  p_expires_at timestamptz,
  p_request_nonce uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration
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
  IF p_channel = 'PARTNER' AND NOT EXISTS (
    SELECT 1 FROM integration.channel_grants
    WHERE principal_id = p_principal_id AND family_id = p_family_id
      AND valid_from <= clock_timestamp() AND valid_until > clock_timestamp() AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_GRANT_INVALID';
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
CREATE FUNCTION auth.clear_context() RETURNS void
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $fn$ DELETE FROM auth.session_contexts WHERE backend_pid = pg_backend_pid() $fn$;

CREATE FUNCTION core.current_actor_is_family_member() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, core
RETURN EXISTS (
  SELECT 1 FROM core.family_memberships
  WHERE family_id = auth.current_family_id() AND person_id = auth.current_actor_person_id()
    AND valid_from <= transaction_timestamp()
    AND (valid_until IS NULL OR valid_until > transaction_timestamp())
);
CREATE FUNCTION core.person_in_current_family(p_person_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, core
RETURN EXISTS (
  SELECT 1 FROM core.family_memberships
  WHERE family_id = auth.current_family_id() AND person_id = p_person_id
    AND valid_from <= transaction_timestamp()
    AND (valid_until IS NULL OR valid_until > transaction_timestamp())
);
CREATE FUNCTION core.has_verified_guardian_authority(p_subject_person_id uuid, p_scope text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, core
RETURN EXISTS (
  SELECT 1 FROM core.guardian_authorities
  WHERE family_id = auth.current_family_id()
    AND guardian_person_id = auth.current_actor_person_id()
    AND subject_person_id = p_subject_person_id
    AND evidence_level = 'VERIFIED'
    AND scope IN ('GENERAL', p_scope)
    AND valid_from <= transaction_timestamp() AND valid_until > transaction_timestamp()
    AND revoked_at IS NULL
);
CREATE FUNCTION consent.has_active_consent(p_subject_person_id uuid, p_purpose text, p_data_class text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, consent
RETURN EXISTS (
  SELECT 1 FROM consent.grants
  WHERE family_id = auth.current_family_id()
    AND grantee_person_id = auth.current_actor_person_id()
    AND subject_person_id = p_subject_person_id
    AND purpose = p_purpose AND data_class = p_data_class
    AND status = 'ACTIVE' AND expires_at > transaction_timestamp()
);
CREATE FUNCTION audit.record_access_event(
  p_action text, p_resource_kind text, p_resource_id uuid, p_decision text, p_reason_code text
) RETURNS void
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, audit
AS $fn$
  INSERT INTO audit.access_events(backend_pid, principal_id, actor_person_id, family_id, action, resource_kind, resource_id, decision, reason_code)
  VALUES (pg_backend_pid(), auth.current_principal_id(), auth.current_actor_person_id(), auth.current_family_id(), p_action, p_resource_kind, p_resource_id, p_decision, p_reason_code)
$fn$;

CREATE FUNCTION consent.protect_grant() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF ROW(NEW.consent_id,NEW.family_id,NEW.grantor_person_id,NEW.grantee_person_id,NEW.subject_person_id,NEW.purpose,NEW.data_class,NEW.granted_at,NEW.expires_at)
     IS DISTINCT FROM
     ROW(OLD.consent_id,OLD.family_id,OLD.grantor_person_id,OLD.grantee_person_id,OLD.subject_person_id,OLD.purpose,OLD.data_class,OLD.granted_at,OLD.expires_at) THEN
    RAISE EXCEPTION 'CONSENT_IDENTITY_IMMUTABLE';
  END IF;
  IF OLD.status <> 'ACTIVE' OR NEW.status NOT IN ('WITHDRAWN','EXPIRED') THEN
    RAISE EXCEPTION 'CONSENT_TRANSITION_INVALID';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER protect_consent_grant BEFORE UPDATE ON consent.grants
FOR EACH ROW EXECUTE FUNCTION consent.protect_grant();

ALTER TABLE core.people ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.families ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.family_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.student_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.guardian_authorities ENABLE ROW LEVEL SECURITY;
ALTER TABLE consent.grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE integration.channel_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.access_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY people_read ON core.people FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (core.person_in_current_family(person_id));
CREATE POLICY families_read ON core.families FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id());
CREATE POLICY memberships_read ON core.family_memberships FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id());
CREATE POLICY student_profiles_read ON core.student_profiles FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (core.person_in_current_family(person_id));
CREATE POLICY guardian_authorities_read ON core.guardian_authorities FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id() AND (guardian_person_id = auth.current_actor_person_id() OR subject_person_id = auth.current_actor_person_id()));
CREATE POLICY consent_read ON consent.grants FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (family_id = auth.current_family_id() AND (grantor_person_id = auth.current_actor_person_id() OR grantee_person_id = auth.current_actor_person_id() OR subject_person_id = auth.current_actor_person_id()));
CREATE POLICY channel_grants_read ON integration.channel_grants FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (principal_id = auth.current_principal_id() AND family_id = auth.current_family_id());
CREATE POLICY audit_read ON audit.access_events FOR SELECT TO phoenix_canonical_reader
  USING (family_id = auth.current_family_id());

REVOKE ALL ON auth.session_contexts, auth.principals FROM PUBLIC, phoenix_canonical_app, phoenix_canonical_reader;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA auth, core, consent, audit FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth.bind_context(uuid,uuid,uuid,text,timestamptz,uuid), auth.clear_context() TO phoenix_canonical_context_binder;
GRANT EXECUTE ON FUNCTION auth.current_principal_id(), auth.current_actor_person_id(), auth.current_family_id(), auth.current_channel() TO phoenix_canonical_app, phoenix_canonical_reader;
GRANT EXECUTE ON FUNCTION core.current_actor_is_family_member(), core.person_in_current_family(uuid), core.has_verified_guardian_authority(uuid,text), consent.has_active_consent(uuid,text,text) TO phoenix_canonical_app, phoenix_canonical_reader;
GRANT EXECUTE ON FUNCTION audit.record_access_event(text,text,uuid,text,text) TO phoenix_canonical_app;

GRANT SELECT ON core.people, core.families, core.family_memberships, core.student_profiles, core.guardian_authorities, consent.grants, integration.channel_grants TO phoenix_canonical_app, phoenix_canonical_reader;
GRANT SELECT ON audit.access_events TO phoenix_canonical_reader;
GRANT INSERT ON audit.access_events TO phoenix_canonical_app;

COMMIT;
