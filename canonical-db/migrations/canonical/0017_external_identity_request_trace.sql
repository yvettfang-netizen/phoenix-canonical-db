BEGIN;

-- FD-6 rule 3 (addendum V1.3; instruction D7): an external identity (issuer +
-- subject) maps to exactly one login principal. Mappings are created and
-- disabled only through the SERVICE management API; unknown identities resolve
-- to nothing (no auto-provisioning); a disabled mapping or principal stops
-- resolving at once. Only the context binder may resolve.
CREATE TABLE auth.external_identities (
  external_identity_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(external_identity_id)),
  issuer text NOT NULL CHECK (length(btrim(issuer)) BETWEEN 1 AND 500),
  subject text NOT NULL CHECK (length(btrim(subject)) BETWEEN 1 AND 500),
  principal_id uuid NOT NULL REFERENCES auth.principals,
  status text NOT NULL CHECK (status IN ('ACTIVE','DISABLED')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by_principal_id uuid REFERENCES auth.principals,
  disabled_at timestamptz,
  disabled_by_principal_id uuid REFERENCES auth.principals,
  CHECK ((status = 'DISABLED') = (disabled_at IS NOT NULL))
);
CREATE UNIQUE INDEX external_identities_active_unique
  ON auth.external_identities(issuer, subject) WHERE status = 'ACTIVE';
ALTER TABLE auth.external_identities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON auth.external_identities FROM PUBLIC, phoenix_canonical_app,
  phoenix_canonical_reader, phoenix_canonical_context_binder;

CREATE FUNCTION auth.register_external_identity(p_id uuid,p_issuer text,p_subject text,p_principal_id uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, audit
AS $fn$
DECLARE v_principal auth.principals%ROWTYPE;
BEGIN
  SELECT * INTO v_principal FROM auth.principals WHERE principal_id=p_principal_id;
  IF (FOUND AND auth.is_internal_service() AND core.is_uuid_v7(p_id)
      AND v_principal.status='ACTIVE'
      AND v_principal.principal_kind IN ('FAMILY','ADVISOR','CHANNEL')
      AND (v_principal.principal_kind<>'FAMILY' OR (auth.current_family_id() IS NOT NULL
        AND core.person_in_current_family(v_principal.person_id)))
      AND length(btrim(p_issuer)) BETWEEN 1 AND 500
      AND length(btrim(p_subject)) BETWEEN 1 AND 500) IS NOT TRUE THEN
    RETURN audit.record_write_decision('MAP','EXTERNAL_IDENTITY',p_id,false,'SERVICE_PRINCIPAL_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM auth.external_identities WHERE external_identity_id=p_id) THEN
    RETURN audit.record_write_decision('MAP','EXTERNAL_IDENTITY',p_id,false,'ALREADY_EXISTS');
  END IF;
  IF EXISTS(SELECT 1 FROM auth.external_identities
             WHERE issuer=p_issuer AND subject=p_subject AND status='ACTIVE') THEN
    RETURN audit.record_write_decision('MAP','EXTERNAL_IDENTITY',p_id,false,'ALREADY_ACTIVE');
  END IF;
  INSERT INTO auth.external_identities(external_identity_id,issuer,subject,principal_id,status,created_by_principal_id)
    VALUES(p_id,p_issuer,p_subject,p_principal_id,'ACTIVE',auth.current_principal_id());
  RETURN audit.record_write_decision('MAP','EXTERNAL_IDENTITY',p_id,true,'SERVICE_MAPPED');
END
$fn$;

CREATE FUNCTION auth.disable_external_identity(p_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, audit
AS $fn$
DECLARE v_map auth.external_identities%ROWTYPE; v_principal auth.principals%ROWTYPE;
BEGIN
  SELECT * INTO v_map FROM auth.external_identities WHERE external_identity_id=p_id FOR UPDATE;
  IF FOUND THEN SELECT * INTO v_principal FROM auth.principals WHERE principal_id=v_map.principal_id; END IF;
  IF (v_map.external_identity_id IS NOT NULL AND auth.is_internal_service() AND v_map.status='ACTIVE'
      AND (v_principal.principal_kind<>'FAMILY' OR core.person_in_current_family(v_principal.person_id))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('UNMAP','EXTERNAL_IDENTITY',p_id,false,'SERVICE_FAMILY_OR_STATUS_DENIED');
  END IF;
  UPDATE auth.external_identities SET status='DISABLED',disabled_at=clock_timestamp(),
    disabled_by_principal_id=auth.current_principal_id() WHERE external_identity_id=p_id;
  RETURN audit.record_write_decision('UNMAP','EXTERNAL_IDENTITY',p_id,true,'SERVICE_DISABLED');
END
$fn$;

-- Binder-only lookup. NULL means: refuse the request (unknown, disabled, or
-- the principal itself is not ACTIVE).
CREATE FUNCTION auth.resolve_external_identity(p_issuer text,p_subject text) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (
  SELECT e.principal_id FROM auth.external_identities e
  JOIN auth.principals p ON p.principal_id = e.principal_id
  WHERE e.issuer = p_issuer AND e.subject = p_subject
    AND e.status = 'ACTIVE' AND p.status = 'ACTIVE'
);

-- FD-6 rule 7: the request number given to the ticket (request_nonce) travels
-- into the bound context, the audit row and the PHOENIX_AUDIT log line, so the
-- gateway log can be matched to database decisions. The new log field is
-- appended at the end of the line to keep existing parsers working.
CREATE FUNCTION auth.current_request_nonce() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN (
  SELECT request_nonce FROM auth.session_contexts
   WHERE backend_pid = pg_backend_pid()
     AND backend_start = auth.current_backend_start()
     AND expires_at > transaction_timestamp()
);
ALTER TABLE audit.access_events ADD COLUMN request_nonce uuid;

CREATE OR REPLACE FUNCTION audit.record_write_decision(
  p_action text,p_resource_kind text,p_resource_id uuid,
  p_allowed boolean,p_reason_code text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,audit
AS $fn$
DECLARE v_attempt uuid := gen_random_uuid();
        v_at timestamptz := clock_timestamp();
        v_principal uuid := auth.current_principal_id();
        v_nonce uuid := auth.current_request_nonce();
        v_decision text := CASE WHEN p_allowed IS TRUE THEN 'ALLOW' ELSE 'DENY' END;
BEGIN
  RAISE LOG 'PHOENIX_AUDIT attempt_id=% action=% resource_kind=% resource_id=% decision=% reason=% principal_id=% backend_pid=% occurred_at=% request_nonce=%',
    v_attempt,p_action,p_resource_kind,coalesce(p_resource_id::text,'NULL'),
    v_decision,p_reason_code,coalesce(v_principal::text,'NULL'),pg_backend_pid(),v_at,
    coalesce(v_nonce::text,'NULL');
  INSERT INTO audit.access_events(attempt_id,occurred_at,backend_pid,principal_id,
    actor_person_id,family_id,action,resource_kind,resource_id,decision,reason_code,request_nonce)
  VALUES(v_attempt,v_at,pg_backend_pid(),v_principal,
    auth.current_actor_person_id(),auth.current_family_id(),
    p_action,p_resource_kind,p_resource_id,v_decision,p_reason_code,v_nonce);
  RETURN p_allowed IS TRUE;
END
$fn$;

REVOKE EXECUTE ON FUNCTION auth.register_external_identity(uuid,text,text,uuid),
  auth.disable_external_identity(uuid),auth.resolve_external_identity(text,text),
  auth.current_request_nonce(),audit.record_write_decision(text,text,uuid,boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth.register_external_identity(uuid,text,text,uuid),
  auth.disable_external_identity(uuid) TO phoenix_canonical_app;
GRANT EXECUTE ON FUNCTION auth.resolve_external_identity(text,text) TO phoenix_canonical_context_binder;

COMMIT;
