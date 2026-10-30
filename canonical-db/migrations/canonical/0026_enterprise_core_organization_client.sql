BEGIN;

-- Phoenix Canonical PostgreSQL V2.0 / P0.
-- Preserve the existing Person, Family and Student authorities.  The original
-- pair-wise UNIQUE constraint is atomically replaced by a temporal exclusion
-- constraint so a finished relationship remains in history and a later,
-- non-overlapping relationship can be established.
DO $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='core.family_memberships'::regclass
       AND conname='family_memberships_family_id_person_id_key'
       AND contype='u'
  ) THEN
    RAISE EXCEPTION 'EXPECTED_LEGACY_FAMILY_MEMBERSHIP_UNIQUE_CONSTRAINT_MISSING';
  END IF;
END
$guard$;

ALTER TABLE core.family_memberships
  DROP CONSTRAINT family_memberships_family_id_person_id_key;
ALTER TABLE core.family_memberships
  ADD CONSTRAINT family_memberships_no_overlapping_relationship
  EXCLUDE USING gist (
    family_id WITH =,
    person_id WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&
  );

CREATE OR REPLACE FUNCTION core.add_family_member(
  p_membership_id uuid,p_family_id uuid,p_person_id uuid,p_membership_role text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v_from timestamptz := transaction_timestamp();
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_membership_id)
      AND p_membership_role IN ('PRIMARY','MEMBER')
      AND EXISTS (SELECT 1 FROM core.people WHERE person_id=p_person_id)
      AND EXISTS (SELECT 1 FROM core.families WHERE family_id=p_family_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','FAMILY_MEMBERSHIP',p_membership_id,false,
      'SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (
    SELECT 1 FROM core.family_memberships
     WHERE family_id=p_family_id AND person_id=p_person_id
       AND tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)')
           && tstzrange(v_from,'infinity'::timestamptz,'[)')
  ) THEN
    RETURN audit.record_write_decision('CREATE','FAMILY_MEMBERSHIP',p_membership_id,false,
      'OVERLAPPING_RELATIONSHIP_DENIED');
  END IF;
  INSERT INTO core.family_memberships(
    membership_id,family_id,person_id,membership_role,valid_from
  ) VALUES(p_membership_id,p_family_id,p_person_id,p_membership_role,v_from);
  RETURN audit.record_write_decision('CREATE','FAMILY_MEMBERSHIP',p_membership_id,true,
    'NON_OVERLAPPING_RELATIONSHIP_CREATED');
EXCEPTION
  WHEN exclusion_violation OR unique_violation THEN
    RETURN audit.record_write_decision('CREATE','FAMILY_MEMBERSHIP',p_membership_id,false,
      'RELATIONSHIP_CONFLICT_DENIED');
END
$fn$;

CREATE SCHEMA crm;
REVOKE ALL ON SCHEMA crm FROM PUBLIC;
GRANT USAGE,CREATE ON SCHEMA crm TO phoenix_canonical_migrator;
GRANT USAGE ON SCHEMA crm TO phoenix_canonical_app;

CREATE TABLE core.organizations (
  organization_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(organization_id)),
  legal_name text NOT NULL CHECK (length(btrim(legal_name)) BETWEEN 1 AND 300),
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 300),
  organization_type text NOT NULL CHECK (organization_type IN (
    'ENTERPRISE','SCHOOL','UNIVERSITY','MEDICAL_INSTITUTION',
    'INSURANCE_COMPANY','PARTNER_ORGANIZATION','SERVICE_PROVIDER'
  )),
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  -- Store only a lowercase SHA-256 digest. The registration identifier itself
  -- belongs in an approved protected secret/document store, never ordinary audit.
  registration_reference_digest text CHECK (
    registration_reference_digest IS NULL
    OR registration_reference_digest ~ '^[0-9a-f]{64}$'
  ),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','RETIRED')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);
CREATE UNIQUE INDEX organizations_legal_country_uq
  ON core.organizations((lower(legal_name)),country_code);
CREATE UNIQUE INDEX organizations_registration_digest_uq
  ON core.organizations(country_code,registration_reference_digest)
  WHERE registration_reference_digest IS NOT NULL;
CREATE INDEX organizations_type_status_idx
  ON core.organizations(organization_type,status);

CREATE TABLE crm.clients (
  client_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(client_id)),
  family_id uuid NOT NULL REFERENCES core.families,
  client_code text NOT NULL UNIQUE CHECK (
    client_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'
  ),
  lifecycle_status text NOT NULL DEFAULT 'ACTIVE'
    CHECK (lifecycle_status IN ('ACTIVE','PAUSED','ENDED')),
  relationship_started_at timestamptz NOT NULL,
  relationship_ended_at timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (
    (lifecycle_status IN ('ACTIVE','PAUSED') AND relationship_ended_at IS NULL)
    OR (lifecycle_status='ENDED' AND relationship_ended_at IS NOT NULL
        AND relationship_ended_at>=relationship_started_at)
  )
);
CREATE UNIQUE INDEX clients_one_current_relationship_per_family_uq
  ON crm.clients(family_id)
  WHERE lifecycle_status IN ('ACTIVE','PAUSED') AND relationship_ended_at IS NULL;
CREATE INDEX clients_family_history_idx
  ON crm.clients(family_id,relationship_started_at DESC);
CREATE INDEX clients_lifecycle_status_idx
  ON crm.clients(lifecycle_status,updated_at DESC);

CREATE FUNCTION core.is_enterprise_core_service() RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth
RETURN coalesce(
  auth.is_internal_service()
  AND EXISTS (
    SELECT 1 FROM auth.principals p
     WHERE p.principal_id=auth.current_principal_id()
       AND p.principal_kind='SERVICE' AND p.person_id IS NULL
       AND p.status='ACTIVE' AND p.service_label='canonical_enterprise_v2_core'
  ),false
);

CREATE FUNCTION core.register_organization(
  p_organization_id uuid,p_legal_name text,p_display_name text,
  p_organization_type text,p_country_code text,p_registration_reference_digest text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
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
  RETURN audit.record_write_decision('CREATE','ORGANIZATION',p_organization_id,true,
    'CANONICAL_ORGANIZATION_CREATED');
END
$fn$;

CREATE FUNCTION core.transition_organization(
  p_organization_id uuid,p_next_status text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v_item core.organizations%ROWTYPE; v_allowed boolean;
BEGIN
  SELECT * INTO v_item FROM core.organizations
   WHERE organization_id=p_organization_id FOR UPDATE;
  v_allowed := FOUND AND core.is_enterprise_core_service()
    AND auth.current_family_id() IS NULL
    AND ((v_item.status='ACTIVE' AND p_next_status IN ('INACTIVE','RETIRED'))
      OR (v_item.status='INACTIVE' AND p_next_status IN ('ACTIVE','RETIRED')));
  IF v_allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','ORGANIZATION',p_organization_id,false,
      'ENTERPRISE_SERVICE_OR_STATE_DENIED');
  END IF;
  UPDATE core.organizations SET status=p_next_status,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE organization_id=p_organization_id;
  RETURN audit.record_write_decision('TRANSITION','ORGANIZATION',p_organization_id,true,
    'ORGANIZATION_STATE_CHANGED');
END
$fn$;

CREATE FUNCTION crm.create_client(
  p_client_id uuid,p_family_id uuid,p_client_code text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
BEGIN
  IF (core.is_enterprise_core_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_client_id)
      AND p_client_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'
      AND EXISTS (SELECT 1 FROM core.families WHERE family_id=p_family_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_CLIENT',p_client_id,false,
      'ENTERPRISE_SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS (
    SELECT 1 FROM crm.clients
     WHERE client_id=p_client_id OR client_code=p_client_code
       OR (family_id=p_family_id AND lifecycle_status IN ('ACTIVE','PAUSED')
           AND relationship_ended_at IS NULL)
  ) THEN
    RETURN audit.record_write_decision('CREATE','CRM_CLIENT',p_client_id,false,
      'ACTIVE_CLIENT_RELATIONSHIP_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.clients(
    client_id,family_id,client_code,lifecycle_status,relationship_started_at,
    created_by_principal_id,updated_by_principal_id
  ) VALUES(
    p_client_id,p_family_id,p_client_code,'ACTIVE',clock_timestamp(),
    auth.current_principal_id(),auth.current_principal_id()
  );
  RETURN audit.record_write_decision('CREATE','CRM_CLIENT',p_client_id,true,
    'FAMILY_CLIENT_RELATIONSHIP_CREATED');
END
$fn$;

CREATE FUNCTION crm.transition_client(p_client_id uuid,p_next_status text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v_item crm.clients%ROWTYPE; v_allowed boolean;
BEGIN
  SELECT * INTO v_item FROM crm.clients WHERE client_id=p_client_id FOR UPDATE;
  v_allowed := FOUND AND core.is_enterprise_core_service()
    AND auth.current_family_id()=v_item.family_id
    AND ((v_item.lifecycle_status='ACTIVE' AND p_next_status IN ('PAUSED','ENDED'))
      OR (v_item.lifecycle_status='PAUSED' AND p_next_status IN ('ACTIVE','ENDED')));
  IF v_allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','CRM_CLIENT',p_client_id,false,
      'ENTERPRISE_SERVICE_FAMILY_OR_STATE_DENIED');
  END IF;
  UPDATE crm.clients SET lifecycle_status=p_next_status,
    relationship_ended_at=CASE WHEN p_next_status='ENDED' THEN clock_timestamp() ELSE NULL END,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE client_id=p_client_id;
  RETURN audit.record_write_decision('TRANSITION','CRM_CLIENT',p_client_id,true,
    'CLIENT_LIFECYCLE_CHANGED');
END
$fn$;

ALTER TABLE core.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.organizations FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.clients FORCE ROW LEVEL SECURITY;

CREATE POLICY organizations_enterprise_service ON core.organizations
  FOR ALL TO phoenix_canonical_app
  USING (core.is_enterprise_core_service())
  WITH CHECK (core.is_enterprise_core_service());
CREATE POLICY clients_enterprise_family_service ON crm.clients
  FOR ALL TO phoenix_canonical_app
  USING (core.is_enterprise_core_service() AND family_id=auth.current_family_id())
  WITH CHECK (core.is_enterprise_core_service() AND family_id=auth.current_family_id());

REVOKE ALL ON core.organizations,crm.clients
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE EXECUTE ON FUNCTION core.is_enterprise_core_service(),
  core.register_organization(uuid,text,text,text,text,text),
  core.transition_organization(uuid,text),
  crm.create_client(uuid,uuid,text),crm.transition_client(uuid,text)
  FROM PUBLIC,phoenix_canonical_reader,phoenix_canonical_context_binder;
GRANT EXECUTE ON FUNCTION core.is_enterprise_core_service(),
  core.register_organization(uuid,text,text,text,text,text),
  core.transition_organization(uuid,text),
  crm.create_client(uuid,uuid,text),crm.transition_client(uuid,text)
  TO phoenix_canonical_app;

COMMIT;
