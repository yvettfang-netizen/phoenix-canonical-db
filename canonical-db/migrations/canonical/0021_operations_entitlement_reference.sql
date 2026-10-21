BEGIN;

CREATE SCHEMA operations_ref;
REVOKE ALL ON SCHEMA operations_ref FROM PUBLIC;
GRANT USAGE,CREATE ON SCHEMA operations_ref TO phoenix_canonical_migrator;
GRANT USAGE ON SCHEMA operations_ref TO phoenix_canonical_app;

CREATE TABLE operations_ref.entitlement_ref (
  entitlement_ref_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(entitlement_ref_id)),
  source_system text NOT NULL CHECK (
    source_system='phoenix_operations'
    AND source_system ~ '^[a-z][a-z0-9_-]{1,39}$'),
  external_entitlement_id text NOT NULL CHECK (
    length(external_entitlement_id) BETWEEN 1 AND 200
    AND external_entitlement_id=btrim(external_entitlement_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  subject_person_id uuid NOT NULL REFERENCES core.people,
  product_kind text NOT NULL CHECK (
    product_kind IN ('EDUCATION_SERVICE','COURSE','ASKWISE')),
  course_id uuid,
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  status text NOT NULL CHECK (status IN ('ACTIVE','REVOKED','EXPIRED')),
  revoked_at timestamptz,
  source_version bigint NOT NULL CHECK (source_version > 0),
  last_source_event_id text NOT NULL CHECK (
    length(last_source_event_id) BETWEEN 1 AND 200
    AND last_source_event_id=btrim(last_source_event_id)),
  source_occurred_at timestamptz NOT NULL,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT entitlement_source_reference_unique
    UNIQUE (source_system,external_entitlement_id),
  CONSTRAINT entitlement_scope_identity_unique
    UNIQUE (entitlement_ref_id,family_id,subject_person_id),
  CONSTRAINT entitlement_course_scope_match CHECK (
    (product_kind='COURSE' AND course_id IS NOT NULL AND core.is_uuid_v7(course_id))
    OR (product_kind<>'COURSE' AND course_id IS NULL)),
  CONSTRAINT entitlement_validity_interval CHECK (
    valid_until IS NULL OR valid_until > valid_from),
  CONSTRAINT entitlement_revocation_state CHECK (
    (status='REVOKED' AND revoked_at IS NOT NULL)
    OR (status IN ('ACTIVE','EXPIRED') AND revoked_at IS NULL))
);

CREATE TABLE operations_ref.entitlement_event (
  source_system text NOT NULL CHECK (source_system='phoenix_operations'),
  source_event_id text NOT NULL CHECK (
    length(source_event_id) BETWEEN 1 AND 200
    AND source_event_id=btrim(source_event_id)),
  entitlement_ref_id uuid NOT NULL REFERENCES operations_ref.entitlement_ref,
  event_kind text NOT NULL CHECK (event_kind IN ('GRANT','REVOKE')),
  source_version bigint NOT NULL CHECK (source_version > 0),
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  recorded_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  PRIMARY KEY (source_system,source_event_id),
  UNIQUE (entitlement_ref_id,source_version)
);

CREATE INDEX entitlement_subject_product_idx
  ON operations_ref.entitlement_ref(subject_person_id,product_kind);
CREATE INDEX entitlement_family_subject_idx
  ON operations_ref.entitlement_ref(family_id,subject_person_id);
CREATE INDEX entitlement_validity_idx
  ON operations_ref.entitlement_ref(status,valid_from,valid_until);
CREATE INDEX entitlement_event_ref_time_idx
  ON operations_ref.entitlement_event(entitlement_ref_id,occurred_at);

CREATE FUNCTION operations_ref.is_operations_service() RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,operations_ref
RETURN coalesce(
  auth.is_internal_service()
  AND EXISTS (
    SELECT 1 FROM auth.principals p
     WHERE p.principal_id=auth.current_principal_id()
       AND p.principal_kind='SERVICE' AND p.status='ACTIVE'
       AND p.service_label='operations_entitlement_service'),false);

CREATE FUNCTION operations_ref.protect_entitlement_ref() RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog,operations_ref
AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'ENTITLEMENT_DELETE_FORBIDDEN'; END IF;
  IF ROW(NEW.entitlement_ref_id,NEW.source_system,NEW.external_entitlement_id,
         NEW.family_id,NEW.subject_person_id,NEW.product_kind,NEW.course_id,
         NEW.valid_from,NEW.valid_until,NEW.created_by_principal_id,NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.entitlement_ref_id,OLD.source_system,OLD.external_entitlement_id,
         OLD.family_id,OLD.subject_person_id,OLD.product_kind,OLD.course_id,
         OLD.valid_from,OLD.valid_until,OLD.created_by_principal_id,OLD.created_at) THEN
    RAISE EXCEPTION 'ENTITLEMENT_IDENTITY_OR_VALIDITY_IMMUTABLE';
  END IF;
  IF OLD.status<>'ACTIVE' THEN RAISE EXCEPTION 'ENTITLEMENT_TERMINAL_STATE_IMMUTABLE'; END IF;
  IF NEW.status='REVOKED' THEN
    IF NEW.revoked_at IS NULL OR NEW.source_version<=OLD.source_version
       OR NEW.last_source_event_id=OLD.last_source_event_id
       OR NEW.source_occurred_at<OLD.source_occurred_at
       OR NEW.updated_by_principal_id IS NULL OR NEW.updated_at<OLD.updated_at THEN
      RAISE EXCEPTION 'ENTITLEMENT_REVOCATION_INVALID';
    END IF;
  ELSIF NEW.status='EXPIRED' THEN
    IF OLD.valid_until IS NULL OR OLD.valid_until>clock_timestamp()
       OR NEW.revoked_at IS NOT NULL OR NEW.source_version<>OLD.source_version
       OR NEW.last_source_event_id<>OLD.last_source_event_id
       OR NEW.source_occurred_at<>OLD.source_occurred_at
       OR NEW.updated_by_principal_id IS NULL OR NEW.updated_at<OLD.updated_at THEN
      RAISE EXCEPTION 'ENTITLEMENT_EXPIRY_INVALID';
    END IF;
  ELSE
    RAISE EXCEPTION 'ENTITLEMENT_TRANSITION_INVALID';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE FUNCTION operations_ref.protect_entitlement_event() RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  RAISE EXCEPTION 'ENTITLEMENT_EVENT_IMMUTABLE';
END
$fn$;

CREATE TRIGGER protect_entitlement_ref_mutation
BEFORE UPDATE OR DELETE ON operations_ref.entitlement_ref
FOR EACH ROW EXECUTE FUNCTION operations_ref.protect_entitlement_ref();
CREATE TRIGGER protect_entitlement_event_mutation
BEFORE UPDATE OR DELETE ON operations_ref.entitlement_event
FOR EACH ROW EXECUTE FUNCTION operations_ref.protect_entitlement_event();

CREATE FUNCTION operations_ref.register_entitlement(
  p_entitlement_ref_id uuid,p_source_system text,p_external_entitlement_id text,
  p_source_event_id text,p_source_version bigint,p_family_id uuid,p_subject_person_id uuid,
  p_product_kind text,p_course_id uuid,p_valid_from timestamptz,p_valid_until timestamptz,
  p_occurred_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,operations_ref,audit
AS $fn$
DECLARE v_event operations_ref.entitlement_event%ROWTYPE;
        v_ref operations_ref.entitlement_ref%ROWTYPE;
        v_allowed boolean;
BEGIN
  SELECT * INTO v_event FROM operations_ref.entitlement_event
   WHERE source_system=p_source_system AND source_event_id=p_source_event_id;
  IF FOUND THEN
    SELECT * INTO v_ref FROM operations_ref.entitlement_ref
     WHERE entitlement_ref_id=v_event.entitlement_ref_id;
    v_allowed := v_event.event_kind='GRANT'
      AND v_event.entitlement_ref_id=p_entitlement_ref_id
      AND v_event.source_version=p_source_version
      AND v_event.occurred_at=p_occurred_at
      AND v_ref.external_entitlement_id=p_external_entitlement_id
      AND v_ref.family_id=p_family_id AND v_ref.subject_person_id=p_subject_person_id
      AND v_ref.product_kind=p_product_kind
      AND v_ref.course_id IS NOT DISTINCT FROM p_course_id
      AND v_ref.valid_from=p_valid_from
      AND v_ref.valid_until IS NOT DISTINCT FROM p_valid_until;
    RETURN audit.record_write_decision('REGISTER','OPERATIONS_ENTITLEMENT',p_entitlement_ref_id,
      v_allowed,CASE WHEN v_allowed THEN 'SOURCE_EVENT_IDEMPOTENT' ELSE 'SOURCE_EVENT_CONFLICT' END);
  END IF;

  v_allowed := operations_ref.is_operations_service()
    AND auth.current_family_id()=p_family_id
    AND core.is_uuid_v7(p_entitlement_ref_id)
    AND p_source_system='phoenix_operations'
    AND length(btrim(p_external_entitlement_id)) BETWEEN 1 AND 200
    AND p_external_entitlement_id=btrim(p_external_entitlement_id)
    AND length(btrim(p_source_event_id)) BETWEEN 1 AND 200
    AND p_source_event_id=btrim(p_source_event_id)
    AND p_source_version>0
    AND p_product_kind IN ('EDUCATION_SERVICE','COURSE','ASKWISE')
    AND ((p_product_kind='COURSE' AND core.is_uuid_v7(p_course_id))
      OR (p_product_kind<>'COURSE' AND p_course_id IS NULL))
    AND p_valid_from IS NOT NULL AND (p_valid_until IS NULL OR p_valid_until>p_valid_from)
    AND p_occurred_at IS NOT NULL
    AND EXISTS (SELECT 1 FROM core.people WHERE person_id=p_subject_person_id)
    AND EXISTS (SELECT 1 FROM core.family_memberships
      WHERE family_id=p_family_id AND person_id=p_subject_person_id
        AND valid_from<=clock_timestamp()
        AND (valid_until IS NULL OR valid_until>clock_timestamp()))
    AND NOT EXISTS (SELECT 1 FROM operations_ref.entitlement_ref
      WHERE source_system=p_source_system
        AND external_entitlement_id=p_external_entitlement_id);
  IF v_allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('REGISTER','OPERATIONS_ENTITLEMENT',p_entitlement_ref_id,
      false,'SERVICE_SOURCE_SUBJECT_SCOPE_OR_INPUT_DENIED');
  END IF;

  INSERT INTO operations_ref.entitlement_ref(
    entitlement_ref_id,source_system,external_entitlement_id,family_id,subject_person_id,
    product_kind,course_id,valid_from,valid_until,status,source_version,
    last_source_event_id,source_occurred_at,created_by_principal_id,updated_by_principal_id)
  VALUES(p_entitlement_ref_id,p_source_system,p_external_entitlement_id,p_family_id,
    p_subject_person_id,p_product_kind,p_course_id,p_valid_from,p_valid_until,'ACTIVE',
    p_source_version,p_source_event_id,p_occurred_at,auth.current_principal_id(),
    auth.current_principal_id());
  INSERT INTO operations_ref.entitlement_event(source_system,source_event_id,
    entitlement_ref_id,event_kind,source_version,occurred_at,recorded_by_principal_id)
  VALUES(p_source_system,p_source_event_id,p_entitlement_ref_id,'GRANT',p_source_version,
    p_occurred_at,auth.current_principal_id());
  RETURN audit.record_write_decision('REGISTER','OPERATIONS_ENTITLEMENT',p_entitlement_ref_id,
    true,'OPERATIONS_SOURCE_REGISTERED');
END
$fn$;

CREATE FUNCTION operations_ref.revoke_entitlement(
  p_source_system text,p_external_entitlement_id text,p_source_event_id text,
  p_source_version bigint,p_occurred_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,operations_ref,audit
AS $fn$
DECLARE v_event operations_ref.entitlement_event%ROWTYPE;
        v_ref operations_ref.entitlement_ref%ROWTYPE;
        v_allowed boolean;
BEGIN
  SELECT * INTO v_event FROM operations_ref.entitlement_event
   WHERE source_system=p_source_system AND source_event_id=p_source_event_id;
  IF FOUND THEN
    SELECT * INTO v_ref FROM operations_ref.entitlement_ref
     WHERE entitlement_ref_id=v_event.entitlement_ref_id;
    v_allowed := v_event.event_kind='REVOKE'
      AND v_ref.source_system=p_source_system
      AND v_ref.external_entitlement_id=p_external_entitlement_id
      AND v_event.source_version=p_source_version
      AND v_event.occurred_at=p_occurred_at;
    RETURN audit.record_write_decision('REVOKE','OPERATIONS_ENTITLEMENT',v_event.entitlement_ref_id,
      v_allowed,CASE WHEN v_allowed THEN 'SOURCE_EVENT_IDEMPOTENT' ELSE 'SOURCE_EVENT_CONFLICT' END);
  END IF;

  SELECT * INTO v_ref FROM operations_ref.entitlement_ref
   WHERE source_system=p_source_system AND external_entitlement_id=p_external_entitlement_id
   FOR UPDATE;
  v_allowed := FOUND AND operations_ref.is_operations_service()
    AND auth.current_family_id()=v_ref.family_id
    AND p_source_system='phoenix_operations'
    AND length(btrim(p_source_event_id)) BETWEEN 1 AND 200
    AND p_source_event_id=btrim(p_source_event_id)
    AND v_ref.status='ACTIVE'
    AND (v_ref.valid_until IS NULL OR v_ref.valid_until>clock_timestamp())
    AND p_source_version>v_ref.source_version
    AND p_occurred_at>=v_ref.source_occurred_at;
  IF v_allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','OPERATIONS_ENTITLEMENT',v_ref.entitlement_ref_id,
      false,'SERVICE_SOURCE_VERSION_OR_STATE_DENIED');
  END IF;

  UPDATE operations_ref.entitlement_ref SET status='REVOKED',revoked_at=p_occurred_at,
    source_version=p_source_version,last_source_event_id=p_source_event_id,
    source_occurred_at=p_occurred_at,updated_by_principal_id=auth.current_principal_id(),
    updated_at=clock_timestamp()
   WHERE entitlement_ref_id=v_ref.entitlement_ref_id;
  INSERT INTO operations_ref.entitlement_event(source_system,source_event_id,
    entitlement_ref_id,event_kind,source_version,occurred_at,recorded_by_principal_id)
  VALUES(p_source_system,p_source_event_id,v_ref.entitlement_ref_id,'REVOKE',p_source_version,
    p_occurred_at,auth.current_principal_id());
  RETURN audit.record_write_decision('REVOKE','OPERATIONS_ENTITLEMENT',v_ref.entitlement_ref_id,
    true,'OPERATIONS_SOURCE_REVOKED');
END
$fn$;

CREATE FUNCTION operations_ref.expire_entitlements() RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,operations_ref,audit
AS $fn$
DECLARE v_ref uuid; v_count integer := 0;
BEGIN
  IF operations_ref.is_operations_service() IS NOT TRUE THEN
    PERFORM audit.record_write_decision('EXPIRE','OPERATIONS_ENTITLEMENT',NULL,false,
      'OPERATIONS_SERVICE_REQUIRED');
    RETURN 0;
  END IF;
  FOR v_ref IN
    UPDATE operations_ref.entitlement_ref SET status='EXPIRED',
      updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
     WHERE family_id=auth.current_family_id() AND status='ACTIVE'
       AND valid_until IS NOT NULL AND valid_until<=clock_timestamp()
     RETURNING entitlement_ref_id
  LOOP
    v_count := v_count+1;
    PERFORM audit.record_write_decision('EXPIRE','OPERATIONS_ENTITLEMENT',v_ref,true,
      'VALIDITY_INTERVAL_ENDED');
  END LOOP;
  RETURN v_count;
END
$fn$;

CREATE FUNCTION operations_ref.check_entitlement(
  p_family_id uuid,p_subject_person_id uuid,p_product_kind text,p_course_id uuid
) RETURNS TABLE(allowed boolean,reason_code text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,operations_ref,audit
AS $fn$
DECLARE v_ref operations_ref.entitlement_ref%ROWTYPE;
BEGIN
  IF (auth.write_context_is_live() AND auth.current_family_id()=p_family_id
      AND core.person_in_current_family(p_subject_person_id)
      AND auth.current_channel() IN ('FAMILY','INTERNAL')) IS NOT TRUE THEN
    allowed:=false; reason_code:='CONTEXT_OR_SUBJECT_DENIED';
    PERFORM audit.record_access_event('CHECK','OPERATIONS_ENTITLEMENT',NULL,'DENY',reason_code);
    RETURN NEXT; RETURN;
  END IF;
  SELECT * INTO v_ref FROM operations_ref.entitlement_ref
   WHERE family_id=p_family_id AND subject_person_id=p_subject_person_id
     AND product_kind=p_product_kind AND course_id IS NOT DISTINCT FROM p_course_id
   ORDER BY CASE
     WHEN status='ACTIVE' AND valid_from<=clock_timestamp()
       AND (valid_until IS NULL OR valid_until>clock_timestamp()) THEN 0
     WHEN status='REVOKED' THEN 1
     WHEN status='EXPIRED' OR (valid_until IS NOT NULL AND valid_until<=clock_timestamp()) THEN 2
     ELSE 3 END,
     created_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    allowed:=false; reason_code:='ENTITLEMENT_MISSING';
  ELSIF v_ref.status='REVOKED' THEN
    allowed:=false; reason_code:='ENTITLEMENT_REVOKED';
  ELSIF v_ref.status='EXPIRED' OR (v_ref.valid_until IS NOT NULL AND v_ref.valid_until<=clock_timestamp()) THEN
    allowed:=false; reason_code:='ENTITLEMENT_EXPIRED';
  ELSIF v_ref.valid_from>clock_timestamp() THEN
    allowed:=false; reason_code:='ENTITLEMENT_NOT_YET_VALID';
  ELSE
    allowed:=true; reason_code:='ENTITLEMENT_ACTIVE';
  END IF;
  PERFORM audit.record_access_event('CHECK','OPERATIONS_ENTITLEMENT',v_ref.entitlement_ref_id,
    CASE WHEN allowed THEN 'ALLOW' ELSE 'DENY' END,reason_code);
  RETURN NEXT;
END
$fn$;

CREATE FUNCTION operations_ref.has_valid_entitlement(
  p_family_id uuid,p_subject_person_id uuid,p_product_kind text,p_course_id uuid
) RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,operations_ref
RETURN (SELECT allowed FROM operations_ref.check_entitlement(
  p_family_id,p_subject_person_id,p_product_kind,p_course_id));

ALTER TABLE operations_ref.entitlement_ref ENABLE ROW LEVEL SECURITY;
ALTER TABLE operations_ref.entitlement_ref FORCE ROW LEVEL SECURITY;
ALTER TABLE operations_ref.entitlement_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE operations_ref.entitlement_event FORCE ROW LEVEL SECURITY;

REVOKE ALL ON ALL TABLES IN SCHEMA operations_ref
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA operations_ref FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  operations_ref.register_entitlement(uuid,text,text,text,bigint,uuid,uuid,text,uuid,timestamptz,timestamptz,timestamptz),
  operations_ref.revoke_entitlement(text,text,text,bigint,timestamptz),
  operations_ref.expire_entitlements(),
  operations_ref.check_entitlement(uuid,uuid,text,uuid),
  operations_ref.has_valid_entitlement(uuid,uuid,text,uuid)
TO phoenix_canonical_app;

COMMIT;
