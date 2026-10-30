BEGIN;

-- Enterprise Database V2.0 / M0. Forward-only completion of the existing
-- Organization authority. Person, Family, Student and Principal stay unchanged.

ALTER TABLE integration.public_ids
  DROP CONSTRAINT public_ids_entity_kind_check,
  DROP CONSTRAINT public_ids_public_id_check;
ALTER TABLE integration.public_ids
  ADD CONSTRAINT public_ids_entity_kind_check CHECK (
    entity_kind IN ('PERSON','FAMILY','STUDENT_PROFILE','GUARDIAN_AUTHORITY','ORGANIZATION')
  ),
  ADD CONSTRAINT public_ids_public_id_check CHECK (
    public_id ~ '^(per|fam|stu|gdn|org)_[0-9a-f]{32}$'
  );

CREATE TABLE core.organization_identifiers (
  organization_identifier_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(organization_identifier_id)),
  organization_id uuid NOT NULL REFERENCES core.organizations,
  identifier_type text NOT NULL CHECK (identifier_type IN (
    'BUSINESS_REGISTRATION','TAX','EDUCATION_LICENSE','MEDICAL_LICENSE',
    'INSURANCE_LICENSE','OTHER_OFFICIAL'
  )),
  issuing_country_code text NOT NULL CHECK (issuing_country_code ~ '^[A-Z]{2}$'),
  issuer_name text NOT NULL CHECK (length(btrim(issuer_name)) BETWEEN 1 AND 300),
  identifier_digest text NOT NULL CHECK (identifier_digest ~ '^[0-9a-f]{64}$'),
  status text NOT NULL CHECK (status IN ('ACTIVE','REVOKED')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  revoked_at timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  revoked_by_principal_id uuid REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (
    (status='ACTIVE' AND revoked_at IS NULL AND revoked_by_principal_id IS NULL)
    OR (status='REVOKED' AND revoked_at IS NOT NULL AND revoked_by_principal_id IS NOT NULL)
  )
);
ALTER TABLE core.organization_identifiers
  ADD CONSTRAINT organization_identifier_value_no_overlap
  EXCLUDE USING gist (
    issuing_country_code WITH =,
    identifier_type WITH =,
    identifier_digest WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&
  ) WHERE (status='ACTIVE');
CREATE INDEX organization_identifiers_organization_status_idx
  ON core.organization_identifiers(organization_id,status,identifier_type);

CREATE TABLE core.organization_relationships (
  organization_relationship_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(organization_relationship_id)),
  source_organization_id uuid NOT NULL REFERENCES core.organizations,
  target_organization_id uuid NOT NULL REFERENCES core.organizations,
  relationship_type text NOT NULL CHECK (relationship_type IN (
    'AFFILIATE','PARTNER','REFERRER','SERVICE_PROVIDER','EDUCATION_PARTNER',
    'HEALTH_PROVIDER','INSURER'
  )),
  status text NOT NULL CHECK (status IN ('ACTIVE','ENDED')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  ended_by_principal_id uuid REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (source_organization_id <> target_organization_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (
    (status='ACTIVE' AND ended_by_principal_id IS NULL)
    OR (status='ENDED' AND valid_until IS NOT NULL AND ended_by_principal_id IS NOT NULL)
  )
);
ALTER TABLE core.organization_relationships
  ADD CONSTRAINT organization_relationships_no_overlap
  EXCLUDE USING gist (
    source_organization_id WITH =,
    target_organization_id WITH =,
    relationship_type WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&
  );
CREATE INDEX organization_relationships_target_status_idx
  ON core.organization_relationships(target_organization_id,status,relationship_type);

CREATE TABLE core.organization_name_history (
  organization_name_history_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(organization_name_history_id)),
  organization_id uuid NOT NULL REFERENCES core.organizations,
  legal_name text NOT NULL CHECK (length(btrim(legal_name)) BETWEEN 1 AND 300),
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 300),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  changed_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);
ALTER TABLE core.organization_name_history
  ADD CONSTRAINT organization_name_history_no_overlap
  EXCLUDE USING gist (
    organization_id WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&
  );
CREATE UNIQUE INDEX organization_name_history_one_current_uq
  ON core.organization_name_history(organization_id) WHERE valid_until IS NULL;

CREATE TABLE core.organization_events (
  organization_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(organization_event_id)),
  organization_id uuid NOT NULL REFERENCES core.organizations,
  event_kind text NOT NULL CHECK (event_kind IN (
    'CREATED','NAME_CHANGED','STATUS_CHANGED','IDENTIFIER_ADDED',
    'IDENTIFIER_REVOKED','RELATIONSHIP_ADDED','RELATIONSHIP_ENDED'
  )),
  related_resource_id uuid,
  from_status text,
  to_status text,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX organization_events_organization_time_idx
  ON core.organization_events(organization_id,occurred_at,organization_event_id);

INSERT INTO integration.public_ids(entity_kind,public_id,canonical_id,issued_at)
SELECT 'ORGANIZATION','org_'||replace(organization_id::text,'-',''),organization_id,created_at
FROM core.organizations
ON CONFLICT DO NOTHING;

INSERT INTO core.organization_name_history(
  organization_name_history_id,organization_id,legal_name,display_name,valid_from,
  changed_by_principal_id,created_at
)
SELECT organization_id,organization_id,legal_name,display_name,created_at,
       created_by_principal_id,created_at
FROM core.organizations
ON CONFLICT DO NOTHING;

CREATE FUNCTION core.reject_organization_history_change() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core AS $fn$
BEGIN
  RAISE EXCEPTION 'ORGANIZATION_HISTORY_IMMUTABLE';
END
$fn$;

CREATE FUNCTION core.protect_organization_identifier() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'ORGANIZATION_IDENTIFIER_DELETE_FORBIDDEN'; END IF;
  IF OLD.status<>'ACTIVE'
     OR NEW.organization_identifier_id<>OLD.organization_identifier_id
     OR NEW.organization_id<>OLD.organization_id
     OR NEW.identifier_type<>OLD.identifier_type
     OR NEW.issuing_country_code<>OLD.issuing_country_code
     OR NEW.issuer_name<>OLD.issuer_name
     OR NEW.identifier_digest<>OLD.identifier_digest
     OR NEW.valid_from<>OLD.valid_from
     OR NEW.valid_until IS NULL
     OR NEW.valid_until<>NEW.revoked_at
     OR NEW.created_by_principal_id<>OLD.created_by_principal_id
     OR NEW.created_at<>OLD.created_at
     OR NEW.status<>'REVOKED'
     OR NEW.revoked_at IS NULL
     OR NEW.revoked_by_principal_id IS NULL THEN
    RAISE EXCEPTION 'ORGANIZATION_IDENTIFIER_MUTATION_FORBIDDEN';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE FUNCTION core.protect_organization_relationship() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'ORGANIZATION_RELATIONSHIP_DELETE_FORBIDDEN'; END IF;
  IF OLD.status<>'ACTIVE'
     OR NEW.organization_relationship_id<>OLD.organization_relationship_id
     OR NEW.source_organization_id<>OLD.source_organization_id
     OR NEW.target_organization_id<>OLD.target_organization_id
     OR NEW.relationship_type<>OLD.relationship_type
     OR NEW.valid_from<>OLD.valid_from
     OR NEW.created_by_principal_id<>OLD.created_by_principal_id
     OR NEW.created_at<>OLD.created_at
     OR NEW.status<>'ENDED'
     OR NEW.valid_until IS NULL
     OR NEW.ended_by_principal_id IS NULL THEN
    RAISE EXCEPTION 'ORGANIZATION_RELATIONSHIP_MUTATION_FORBIDDEN';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER organization_events_immutable
BEFORE UPDATE OR DELETE ON core.organization_events
FOR EACH ROW EXECUTE FUNCTION core.reject_organization_history_change();
CREATE TRIGGER organization_name_history_delete_forbidden
BEFORE DELETE ON core.organization_name_history
FOR EACH ROW EXECUTE FUNCTION core.reject_organization_history_change();
CREATE TRIGGER organization_identifiers_protected
BEFORE UPDATE OR DELETE ON core.organization_identifiers
FOR EACH ROW EXECUTE FUNCTION core.protect_organization_identifier();
CREATE TRIGGER organization_relationships_protected
BEFORE UPDATE OR DELETE ON core.organization_relationships
FOR EACH ROW EXECUTE FUNCTION core.protect_organization_relationship();

CREATE OR REPLACE FUNCTION core.register_organization(
  p_organization_id uuid,p_legal_name text,p_display_name text,
  p_organization_type text,p_country_code text,p_registration_reference_digest text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,integration,audit
AS $fn$
BEGIN
  IF (core.is_enterprise_core_service() AND auth.current_family_id() IS NULL
      AND core.is_uuid_v7(p_organization_id)
      AND length(btrim(p_legal_name)) BETWEEN 1 AND 300
      AND length(btrim(p_display_name)) BETWEEN 1 AND 300
      AND p_organization_type IN ('ENTERPRISE','SCHOOL','UNIVERSITY',
        'MEDICAL_INSTITUTION','INSURANCE_COMPANY','PARTNER_ORGANIZATION','SERVICE_PROVIDER')
      AND p_country_code ~ '^[A-Z]{2}$'
      AND (p_registration_reference_digest IS NULL
        OR p_registration_reference_digest ~ '^[0-9a-f]{64}$')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','ORGANIZATION',p_organization_id,false,
      'ENTERPRISE_SERVICE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (
    SELECT 1 FROM core.organizations
     WHERE organization_id=p_organization_id
       OR (lower(legal_name)=lower(btrim(p_legal_name)) AND country_code=p_country_code)
       OR (p_registration_reference_digest IS NOT NULL
         AND country_code=p_country_code
         AND registration_reference_digest=p_registration_reference_digest)
  ) THEN
    RETURN audit.record_write_decision('CREATE','ORGANIZATION',p_organization_id,false,
      'CANONICAL_ORGANIZATION_ALREADY_EXISTS');
  END IF;
  INSERT INTO core.organizations(
    organization_id,legal_name,display_name,organization_type,country_code,
    registration_reference_digest,created_by_principal_id,updated_by_principal_id
  ) VALUES(
    p_organization_id,btrim(p_legal_name),btrim(p_display_name),p_organization_type,
    p_country_code,p_registration_reference_digest,auth.current_principal_id(),
    auth.current_principal_id()
  );
  INSERT INTO integration.public_ids(entity_kind,public_id,canonical_id)
    VALUES('ORGANIZATION','org_'||replace(p_organization_id::text,'-',''),p_organization_id);
  INSERT INTO core.organization_name_history(
    organization_name_history_id,organization_id,legal_name,display_name,valid_from,
    changed_by_principal_id
  ) VALUES(
    p_organization_id,p_organization_id,btrim(p_legal_name),btrim(p_display_name),
    transaction_timestamp(),auth.current_principal_id()
  );
  INSERT INTO core.organization_events(
    organization_event_id,organization_id,event_kind,related_resource_id,
    to_status,reason_code,actor_principal_id
  ) VALUES(
    p_organization_id,p_organization_id,'CREATED',p_organization_id,
    'ACTIVE','ORGANIZATION_CREATED',auth.current_principal_id()
  );
  RETURN audit.record_write_decision('CREATE','ORGANIZATION',p_organization_id,true,
    'CANONICAL_ORGANIZATION_CREATED');
END
$fn$;

CREATE FUNCTION core.rename_organization(
  p_organization_id uuid,p_history_id uuid,p_legal_name text,p_display_name text,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v core.organizations%ROWTYPE; v_now timestamptz:=clock_timestamp();
BEGIN
  SELECT * INTO v FROM core.organizations WHERE organization_id=p_organization_id FOR UPDATE;
  IF (FOUND AND core.is_enterprise_core_service() AND auth.current_family_id() IS NULL
      AND v.status<>'RETIRED' AND core.is_uuid_v7(p_history_id) AND core.is_uuid_v7(p_event_id)
      AND length(btrim(p_legal_name)) BETWEEN 1 AND 300
      AND length(btrim(p_display_name)) BETWEEN 1 AND 300
      AND (v.legal_name,v.display_name) IS DISTINCT FROM (btrim(p_legal_name),btrim(p_display_name))
      AND NOT EXISTS(SELECT 1 FROM core.organizations o
        WHERE o.organization_id<>p_organization_id AND o.country_code=v.country_code
          AND lower(o.legal_name)=lower(btrim(p_legal_name)))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('RENAME','ORGANIZATION',p_organization_id,false,
      'ENTERPRISE_SERVICE_STATE_OR_NAME_DENIED');
  END IF;
  UPDATE core.organization_name_history SET valid_until=v_now
   WHERE organization_id=p_organization_id AND valid_until IS NULL;
  INSERT INTO core.organization_name_history(
    organization_name_history_id,organization_id,legal_name,display_name,valid_from,
    changed_by_principal_id
  ) VALUES(p_history_id,p_organization_id,btrim(p_legal_name),btrim(p_display_name),v_now,
    auth.current_principal_id());
  UPDATE core.organizations SET legal_name=btrim(p_legal_name),display_name=btrim(p_display_name),
    updated_by_principal_id=auth.current_principal_id(),updated_at=v_now
   WHERE organization_id=p_organization_id;
  INSERT INTO core.organization_events(
    organization_event_id,organization_id,event_kind,related_resource_id,reason_code,actor_principal_id
  ) VALUES(p_event_id,p_organization_id,'NAME_CHANGED',p_history_id,
    'ORGANIZATION_NAME_CHANGED',auth.current_principal_id());
  RETURN audit.record_write_decision('RENAME','ORGANIZATION',p_organization_id,true,
    'ORGANIZATION_NAME_CHANGED');
END
$fn$;

CREATE FUNCTION core.transition_organization(
  p_organization_id uuid,p_next_status text,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v core.organizations%ROWTYPE; v_allowed boolean;
BEGIN
  SELECT * INTO v FROM core.organizations WHERE organization_id=p_organization_id FOR UPDATE;
  v_allowed:=FOUND AND core.is_enterprise_core_service() AND auth.current_family_id() IS NULL
    AND core.is_uuid_v7(p_event_id)
    AND ((v.status='ACTIVE' AND p_next_status IN ('INACTIVE','RETIRED'))
      OR (v.status='INACTIVE' AND p_next_status IN ('ACTIVE','RETIRED')));
  IF v_allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','ORGANIZATION',p_organization_id,false,
      'ENTERPRISE_SERVICE_OR_STATE_DENIED');
  END IF;
  UPDATE core.organizations SET status=p_next_status,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE organization_id=p_organization_id;
  INSERT INTO core.organization_events(
    organization_event_id,organization_id,event_kind,from_status,to_status,reason_code,
    actor_principal_id
  ) VALUES(p_event_id,p_organization_id,'STATUS_CHANGED',v.status,p_next_status,
    'ORGANIZATION_STATUS_CHANGED',auth.current_principal_id());
  RETURN audit.record_write_decision('TRANSITION','ORGANIZATION',p_organization_id,true,
    'ORGANIZATION_STATE_CHANGED');
END
$fn$;

CREATE FUNCTION core.register_organization_identifier(
  p_id uuid,p_organization_id uuid,p_type text,p_country text,p_issuer text,
  p_digest text,p_valid_until timestamptz,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v_now timestamptz:=clock_timestamp();
BEGIN
  IF (core.is_enterprise_core_service() AND auth.current_family_id() IS NULL
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event_id)
      AND p_type IN ('BUSINESS_REGISTRATION','TAX','EDUCATION_LICENSE','MEDICAL_LICENSE',
        'INSURANCE_LICENSE','OTHER_OFFICIAL')
      AND p_country ~ '^[A-Z]{2}$' AND length(btrim(p_issuer)) BETWEEN 1 AND 300
      AND p_digest ~ '^[0-9a-f]{64}$' AND (p_valid_until IS NULL OR p_valid_until>v_now)
      AND EXISTS(SELECT 1 FROM core.organizations
        WHERE organization_id=p_organization_id AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','ORGANIZATION_IDENTIFIER',p_id,false,
      'ENTERPRISE_SERVICE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM core.organization_identifiers
      WHERE issuing_country_code=p_country AND identifier_type=p_type
        AND identifier_digest=p_digest AND status='ACTIVE'
        AND (valid_until IS NULL OR valid_until>v_now)) THEN
    RETURN audit.record_write_decision('ADD','ORGANIZATION_IDENTIFIER',p_id,false,
      'ACTIVE_IDENTIFIER_ALREADY_EXISTS');
  END IF;
  INSERT INTO core.organization_identifiers(
    organization_identifier_id,organization_id,identifier_type,issuing_country_code,
    issuer_name,identifier_digest,status,valid_from,valid_until,created_by_principal_id
  ) VALUES(p_id,p_organization_id,p_type,p_country,btrim(p_issuer),p_digest,'ACTIVE',v_now,
    p_valid_until,auth.current_principal_id());
  INSERT INTO core.organization_events(
    organization_event_id,organization_id,event_kind,related_resource_id,reason_code,
    actor_principal_id
  ) VALUES(p_event_id,p_organization_id,'IDENTIFIER_ADDED',p_id,
    'ORGANIZATION_IDENTIFIER_ADDED',auth.current_principal_id());
  RETURN audit.record_write_decision('ADD','ORGANIZATION_IDENTIFIER',p_id,true,
    'ORGANIZATION_IDENTIFIER_ADDED');
EXCEPTION WHEN exclusion_violation OR unique_violation THEN
  RETURN audit.record_write_decision('ADD','ORGANIZATION_IDENTIFIER',p_id,false,
    'ACTIVE_IDENTIFIER_ALREADY_EXISTS');
END
$fn$;

CREATE FUNCTION core.revoke_organization_identifier(p_id uuid,p_event_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v core.organization_identifiers%ROWTYPE; v_now timestamptz:=clock_timestamp();
BEGIN
  SELECT * INTO v FROM core.organization_identifiers
   WHERE organization_identifier_id=p_id FOR UPDATE;
  IF (FOUND AND v.status='ACTIVE' AND core.is_enterprise_core_service()
      AND auth.current_family_id() IS NULL AND core.is_uuid_v7(p_event_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','ORGANIZATION_IDENTIFIER',p_id,false,
      'ENTERPRISE_SERVICE_OR_STATE_DENIED');
  END IF;
  UPDATE core.organization_identifiers SET status='REVOKED',valid_until=v_now,revoked_at=v_now,
    revoked_by_principal_id=auth.current_principal_id() WHERE organization_identifier_id=p_id;
  INSERT INTO core.organization_events(
    organization_event_id,organization_id,event_kind,related_resource_id,reason_code,
    actor_principal_id
  ) VALUES(p_event_id,v.organization_id,'IDENTIFIER_REVOKED',p_id,
    'ORGANIZATION_IDENTIFIER_REVOKED',auth.current_principal_id());
  RETURN audit.record_write_decision('REVOKE','ORGANIZATION_IDENTIFIER',p_id,true,
    'ORGANIZATION_IDENTIFIER_REVOKED');
END
$fn$;

CREATE FUNCTION core.create_organization_relationship(
  p_id uuid,p_source uuid,p_target uuid,p_type text,p_valid_until timestamptz,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v_now timestamptz:=clock_timestamp();
BEGIN
  IF (core.is_enterprise_core_service() AND auth.current_family_id() IS NULL
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event_id) AND p_source<>p_target
      AND p_type IN ('AFFILIATE','PARTNER','REFERRER','SERVICE_PROVIDER','EDUCATION_PARTNER',
        'HEALTH_PROVIDER','INSURER')
      AND (p_valid_until IS NULL OR p_valid_until>v_now)
      AND (SELECT count(*)=2 FROM core.organizations
        WHERE organization_id IN (p_source,p_target) AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','ORGANIZATION_RELATIONSHIP',p_id,false,
      'ENTERPRISE_SERVICE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO core.organization_relationships(
    organization_relationship_id,source_organization_id,target_organization_id,
    relationship_type,status,valid_from,valid_until,created_by_principal_id
  ) VALUES(p_id,p_source,p_target,p_type,'ACTIVE',v_now,p_valid_until,
    auth.current_principal_id());
  INSERT INTO core.organization_events(
    organization_event_id,organization_id,event_kind,related_resource_id,reason_code,
    actor_principal_id
  ) VALUES(p_event_id,p_source,'RELATIONSHIP_ADDED',p_id,
    'ORGANIZATION_RELATIONSHIP_ADDED',auth.current_principal_id());
  RETURN audit.record_write_decision('ADD','ORGANIZATION_RELATIONSHIP',p_id,true,
    'ORGANIZATION_RELATIONSHIP_ADDED');
EXCEPTION WHEN exclusion_violation OR unique_violation THEN
  RETURN audit.record_write_decision('ADD','ORGANIZATION_RELATIONSHIP',p_id,false,
    'OVERLAPPING_RELATIONSHIP_DENIED');
END
$fn$;

CREATE FUNCTION core.end_organization_relationship(p_id uuid,p_event_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v core.organization_relationships%ROWTYPE;
BEGIN
  SELECT * INTO v FROM core.organization_relationships
   WHERE organization_relationship_id=p_id FOR UPDATE;
  IF (FOUND AND v.status='ACTIVE' AND core.is_enterprise_core_service()
      AND auth.current_family_id() IS NULL AND core.is_uuid_v7(p_event_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('END','ORGANIZATION_RELATIONSHIP',p_id,false,
      'ENTERPRISE_SERVICE_OR_STATE_DENIED');
  END IF;
  UPDATE core.organization_relationships SET status='ENDED',valid_until=clock_timestamp(),
    ended_by_principal_id=auth.current_principal_id() WHERE organization_relationship_id=p_id;
  INSERT INTO core.organization_events(
    organization_event_id,organization_id,event_kind,related_resource_id,reason_code,
    actor_principal_id
  ) VALUES(p_event_id,v.source_organization_id,'RELATIONSHIP_ENDED',p_id,
    'ORGANIZATION_RELATIONSHIP_ENDED',auth.current_principal_id());
  RETURN audit.record_write_decision('END','ORGANIZATION_RELATIONSHIP',p_id,true,
    'ORGANIZATION_RELATIONSHIP_ENDED');
END
$fn$;

ALTER TABLE core.organization_identifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.organization_identifiers FORCE ROW LEVEL SECURITY;
ALTER TABLE core.organization_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.organization_relationships FORCE ROW LEVEL SECURITY;
ALTER TABLE core.organization_name_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.organization_name_history FORCE ROW LEVEL SECURITY;
ALTER TABLE core.organization_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.organization_events FORCE ROW LEVEL SECURITY;

CREATE POLICY organization_identifiers_enterprise_service ON core.organization_identifiers
  FOR ALL TO phoenix_canonical_app
  USING (core.is_enterprise_core_service()) WITH CHECK (core.is_enterprise_core_service());
CREATE POLICY organization_relationships_enterprise_service ON core.organization_relationships
  FOR ALL TO phoenix_canonical_app
  USING (core.is_enterprise_core_service()) WITH CHECK (core.is_enterprise_core_service());
CREATE POLICY organization_name_history_enterprise_service ON core.organization_name_history
  FOR ALL TO phoenix_canonical_app
  USING (core.is_enterprise_core_service()) WITH CHECK (core.is_enterprise_core_service());
CREATE POLICY organization_events_enterprise_service ON core.organization_events
  FOR ALL TO phoenix_canonical_app
  USING (core.is_enterprise_core_service()) WITH CHECK (core.is_enterprise_core_service());

REVOKE ALL ON core.organization_identifiers,core.organization_relationships,
  core.organization_name_history,core.organization_events
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE EXECUTE ON FUNCTION core.transition_organization(uuid,text) FROM phoenix_canonical_app;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA core FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  core.register_organization(uuid,text,text,text,text,text),
  core.rename_organization(uuid,uuid,text,text,uuid),
  core.transition_organization(uuid,text,uuid),
  core.register_organization_identifier(uuid,uuid,text,text,text,text,timestamptz,uuid),
  core.revoke_organization_identifier(uuid,uuid),
  core.create_organization_relationship(uuid,uuid,uuid,text,timestamptz,uuid),
  core.end_organization_relationship(uuid,uuid)
TO phoenix_canonical_app;

COMMIT;
