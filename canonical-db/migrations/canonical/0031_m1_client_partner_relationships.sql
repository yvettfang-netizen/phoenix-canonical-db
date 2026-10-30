BEGIN;

-- Enterprise Database V2.0 / M1. Forward-only Client-party and Partner
-- relationships. Family, Person and Organization remain the authorities.
CREATE TABLE crm.client_parties (
  client_party_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(client_party_id)),
  client_id uuid NOT NULL,
  family_id uuid NOT NULL,
  party_kind text NOT NULL CHECK (party_kind IN ('PERSON','ORGANIZATION')),
  person_id uuid REFERENCES core.people,
  organization_id uuid REFERENCES core.organizations,
  party_role text NOT NULL CHECK (party_role IN (
    'PAYER','CONTRACT_PARTY','CLIENT_CONTACT','SERVICE_RECIPIENT','AUTHORIZED_REPRESENTATIVE'
  )),
  status text NOT NULL CHECK (status IN ('ACTIVE','ENDED')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  ended_by_principal_id uuid REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  FOREIGN KEY(client_id,family_id) REFERENCES crm.clients(client_id,family_id),
  CHECK (
    (party_kind='PERSON' AND person_id IS NOT NULL AND organization_id IS NULL)
    OR (party_kind='ORGANIZATION' AND person_id IS NULL AND organization_id IS NOT NULL)
  ),
  CHECK (valid_until IS NULL OR valid_until>valid_from),
  CHECK (
    (status='ACTIVE' AND ended_by_principal_id IS NULL)
    OR (status='ENDED' AND valid_until IS NOT NULL AND ended_by_principal_id IS NOT NULL)
  )
);
ALTER TABLE crm.client_parties ADD CONSTRAINT client_person_party_no_overlap
  EXCLUDE USING gist (
    client_id WITH =,party_role WITH =,person_id WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&
  ) WHERE (person_id IS NOT NULL);
ALTER TABLE crm.client_parties ADD CONSTRAINT client_organization_party_no_overlap
  EXCLUDE USING gist (
    client_id WITH =,party_role WITH =,organization_id WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&
  ) WHERE (organization_id IS NOT NULL);
CREATE INDEX client_parties_client_status_idx
  ON crm.client_parties(client_id,status,party_role);

CREATE TABLE crm.client_relationship_events (
  client_relationship_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(client_relationship_event_id)),
  client_id uuid NOT NULL REFERENCES crm.clients,
  client_party_id uuid REFERENCES crm.client_parties,
  event_kind text NOT NULL CHECK (event_kind IN (
    'CLIENT_CREATED','CLIENT_STATUS_CHANGED','PARTY_ADDED','PARTY_ENDED'
  )),
  from_status text,
  to_status text,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX client_relationship_events_client_time_idx
  ON crm.client_relationship_events(client_id,occurred_at,client_relationship_event_id);

CREATE TABLE crm.partner_relationships (
  partner_relationship_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(partner_relationship_id)),
  partner_kind text NOT NULL CHECK (partner_kind IN ('PERSON','ORGANIZATION')),
  partner_person_id uuid REFERENCES core.people,
  partner_organization_id uuid REFERENCES core.organizations,
  relationship_type text NOT NULL CHECK (relationship_type IN (
    'REFERRAL_PARTNER','CHANNEL_PARTNER','SERVICE_PARTNER','INSTITUTIONAL_PARTNER'
  )),
  lead_source_id uuid REFERENCES crm.lead_sources,
  status text NOT NULL CHECK (status IN ('ACTIVE','ENDED')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  ended_by_principal_id uuid REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (
    (partner_kind='PERSON' AND partner_person_id IS NOT NULL AND partner_organization_id IS NULL)
    OR (partner_kind='ORGANIZATION' AND partner_person_id IS NULL AND partner_organization_id IS NOT NULL)
  ),
  CHECK (
    relationship_type NOT IN ('REFERRAL_PARTNER','CHANNEL_PARTNER') OR lead_source_id IS NOT NULL
  ),
  CHECK (valid_until IS NULL OR valid_until>valid_from),
  CHECK (
    (status='ACTIVE' AND ended_by_principal_id IS NULL)
    OR (status='ENDED' AND valid_until IS NOT NULL AND ended_by_principal_id IS NOT NULL)
  )
);
ALTER TABLE crm.partner_relationships ADD CONSTRAINT partner_person_relationship_no_overlap
  EXCLUDE USING gist (
    partner_person_id WITH =,relationship_type WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&
  ) WHERE (partner_person_id IS NOT NULL);
ALTER TABLE crm.partner_relationships ADD CONSTRAINT partner_organization_relationship_no_overlap
  EXCLUDE USING gist (
    partner_organization_id WITH =,relationship_type WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&
  ) WHERE (partner_organization_id IS NOT NULL);
CREATE INDEX partner_relationships_source_status_idx
  ON crm.partner_relationships(lead_source_id,status,relationship_type);

CREATE TABLE crm.partner_relationship_events (
  partner_relationship_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(partner_relationship_event_id)),
  partner_relationship_id uuid NOT NULL REFERENCES crm.partner_relationships,
  event_kind text NOT NULL CHECK (event_kind IN ('RELATIONSHIP_CREATED','RELATIONSHIP_ENDED')),
  from_status text,
  to_status text,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX partner_relationship_events_relationship_time_idx
  ON crm.partner_relationship_events(partner_relationship_id,occurred_at,partner_relationship_event_id);

CREATE FUNCTION crm.reject_relationship_history_change() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,crm AS $fn$
BEGIN
  RAISE EXCEPTION 'CRM_RELATIONSHIP_HISTORY_IMMUTABLE';
END
$fn$;

CREATE FUNCTION crm.protect_client_party() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,crm AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'CLIENT_PARTY_DELETE_FORBIDDEN'; END IF;
  IF OLD.status<>'ACTIVE' OR NEW.status<>'ENDED'
     OR NEW.client_party_id<>OLD.client_party_id OR NEW.client_id<>OLD.client_id
     OR NEW.family_id<>OLD.family_id OR NEW.party_kind<>OLD.party_kind
     OR NEW.person_id IS DISTINCT FROM OLD.person_id
     OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.party_role<>OLD.party_role OR NEW.valid_from<>OLD.valid_from
     OR NEW.valid_until IS NULL OR NEW.ended_by_principal_id IS NULL
     OR NEW.created_by_principal_id<>OLD.created_by_principal_id
     OR NEW.created_at<>OLD.created_at THEN
    RAISE EXCEPTION 'CLIENT_PARTY_MUTATION_FORBIDDEN';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE FUNCTION crm.protect_partner_relationship() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,crm AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'PARTNER_RELATIONSHIP_DELETE_FORBIDDEN'; END IF;
  IF OLD.status<>'ACTIVE' OR NEW.status<>'ENDED'
     OR NEW.partner_relationship_id<>OLD.partner_relationship_id
     OR NEW.partner_kind<>OLD.partner_kind
     OR NEW.partner_person_id IS DISTINCT FROM OLD.partner_person_id
     OR NEW.partner_organization_id IS DISTINCT FROM OLD.partner_organization_id
     OR NEW.relationship_type<>OLD.relationship_type
     OR NEW.lead_source_id IS DISTINCT FROM OLD.lead_source_id
     OR NEW.valid_from<>OLD.valid_from OR NEW.valid_until IS NULL
     OR NEW.ended_by_principal_id IS NULL
     OR NEW.created_by_principal_id<>OLD.created_by_principal_id
     OR NEW.created_at<>OLD.created_at THEN
    RAISE EXCEPTION 'PARTNER_RELATIONSHIP_MUTATION_FORBIDDEN';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER client_relationship_events_immutable
  BEFORE UPDATE OR DELETE ON crm.client_relationship_events
  FOR EACH ROW EXECUTE FUNCTION crm.reject_relationship_history_change();
CREATE TRIGGER partner_relationship_events_immutable
  BEFORE UPDATE OR DELETE ON crm.partner_relationship_events
  FOR EACH ROW EXECUTE FUNCTION crm.reject_relationship_history_change();
CREATE TRIGGER client_parties_protected
  BEFORE UPDATE OR DELETE ON crm.client_parties
  FOR EACH ROW EXECUTE FUNCTION crm.protect_client_party();
CREATE TRIGGER partner_relationships_protected
  BEFORE UPDATE OR DELETE ON crm.partner_relationships
  FOR EACH ROW EXECUTE FUNCTION crm.protect_partner_relationship();

CREATE FUNCTION crm.record_client_relationship_event(
  p_event_id uuid,p_client_id uuid,p_party_id uuid,p_kind text,
  p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm
AS $fn$
BEGIN
  INSERT INTO crm.client_relationship_events(
    client_relationship_event_id,client_id,client_party_id,event_kind,
    from_status,to_status,reason_code,actor_principal_id
  ) VALUES(p_event_id,p_client_id,p_party_id,p_kind,p_from,p_to,p_reason,auth.current_principal_id());
END
$fn$;

CREATE FUNCTION crm.record_partner_relationship_event(
  p_event_id uuid,p_relationship_id uuid,p_kind text,p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm
AS $fn$
BEGIN
  INSERT INTO crm.partner_relationship_events(
    partner_relationship_event_id,partner_relationship_id,event_kind,
    from_status,to_status,reason_code,actor_principal_id
  ) VALUES(p_event_id,p_relationship_id,p_kind,p_from,p_to,p_reason,auth.current_principal_id());
END
$fn$;

CREATE FUNCTION crm.create_client(
  p_client_id uuid,p_family_id uuid,p_client_code text,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
BEGIN
  IF (core.is_enterprise_core_service() AND auth.current_family_id()=p_family_id
      AND core.is_uuid_v7(p_client_id) AND core.is_uuid_v7(p_event_id)
      AND p_client_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'
      AND EXISTS(SELECT 1 FROM core.families WHERE family_id=p_family_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_CLIENT',p_client_id,false,
      'ENTERPRISE_SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.clients
      WHERE client_id=p_client_id OR client_code=p_client_code
        OR (family_id=p_family_id AND lifecycle_status IN ('ACTIVE','PAUSED')
          AND relationship_ended_at IS NULL)) THEN
    RETURN audit.record_write_decision('CREATE','CRM_CLIENT',p_client_id,false,
      'ACTIVE_CLIENT_RELATIONSHIP_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.clients(
    client_id,family_id,client_code,lifecycle_status,relationship_started_at,
    created_by_principal_id,updated_by_principal_id
  ) VALUES(p_client_id,p_family_id,p_client_code,'ACTIVE',clock_timestamp(),
    auth.current_principal_id(),auth.current_principal_id());
  PERFORM crm.record_client_relationship_event(p_event_id,p_client_id,NULL,
    'CLIENT_CREATED',NULL,'ACTIVE','FAMILY_CLIENT_RELATIONSHIP_CREATED');
  RETURN audit.record_write_decision('CREATE','CRM_CLIENT',p_client_id,true,
    'FAMILY_CLIENT_RELATIONSHIP_CREATED');
END
$fn$;

CREATE FUNCTION crm.transition_client(p_client_id uuid,p_next_status text,p_event_id uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v crm.clients%ROWTYPE; v_allowed boolean;
BEGIN
  SELECT * INTO v FROM crm.clients WHERE client_id=p_client_id FOR UPDATE;
  v_allowed:=FOUND AND core.is_enterprise_core_service()
    AND auth.current_family_id()=v.family_id AND core.is_uuid_v7(p_event_id)
    AND ((v.lifecycle_status='ACTIVE' AND p_next_status IN ('PAUSED','ENDED'))
      OR (v.lifecycle_status='PAUSED' AND p_next_status IN ('ACTIVE','ENDED')));
  IF v_allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','CRM_CLIENT',p_client_id,false,
      'ENTERPRISE_SERVICE_FAMILY_OR_STATE_DENIED');
  END IF;
  UPDATE crm.clients SET lifecycle_status=p_next_status,
    relationship_ended_at=CASE WHEN p_next_status='ENDED' THEN clock_timestamp() END,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE client_id=p_client_id;
  PERFORM crm.record_client_relationship_event(p_event_id,p_client_id,NULL,
    'CLIENT_STATUS_CHANGED',v.lifecycle_status,p_next_status,'CLIENT_LIFECYCLE_CHANGED');
  RETURN audit.record_write_decision('TRANSITION','CRM_CLIENT',p_client_id,true,
    'CLIENT_LIFECYCLE_CHANGED');
END
$fn$;

CREATE FUNCTION crm.add_client_party(
  p_id uuid,p_client uuid,p_kind text,p_subject uuid,p_role text,p_valid_until timestamptz,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v crm.clients%ROWTYPE; v_now timestamptz:=clock_timestamp();
BEGIN
  SELECT * INTO v FROM crm.clients WHERE client_id=p_client FOR UPDATE;
  IF (FOUND AND v.lifecycle_status IN ('ACTIVE','PAUSED') AND crm.is_crm_service()
      AND auth.current_family_id()=v.family_id AND core.is_uuid_v7(p_id)
      AND core.is_uuid_v7(p_event_id) AND p_kind IN ('PERSON','ORGANIZATION')
      AND p_role IN ('PAYER','CONTRACT_PARTY','CLIENT_CONTACT','SERVICE_RECIPIENT','AUTHORIZED_REPRESENTATIVE')
      AND (p_valid_until IS NULL OR p_valid_until>v_now)
      AND CASE p_kind
        WHEN 'PERSON' THEN EXISTS(SELECT 1 FROM core.family_memberships
          WHERE family_id=v.family_id AND person_id=p_subject AND valid_from<=v_now
            AND (valid_until IS NULL OR valid_until>v_now))
        WHEN 'ORGANIZATION' THEN EXISTS(SELECT 1 FROM core.organizations
          WHERE organization_id=p_subject AND status='ACTIVE') ELSE false END) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','CRM_CLIENT_PARTY',p_id,false,
      'CRM_CLIENT_SCOPE_SUBJECT_OR_INPUT_DENIED');
  END IF;
  INSERT INTO crm.client_parties(
    client_party_id,client_id,family_id,party_kind,person_id,organization_id,
    party_role,status,valid_from,valid_until,created_by_principal_id
  ) VALUES(p_id,p_client,v.family_id,p_kind,
    CASE WHEN p_kind='PERSON' THEN p_subject END,
    CASE WHEN p_kind='ORGANIZATION' THEN p_subject END,
    p_role,'ACTIVE',v_now,p_valid_until,auth.current_principal_id());
  PERFORM crm.record_client_relationship_event(p_event_id,p_client,p_id,
    'PARTY_ADDED',NULL,'ACTIVE','CLIENT_PARTY_ADDED');
  RETURN audit.record_write_decision('ADD','CRM_CLIENT_PARTY',p_id,true,'CLIENT_PARTY_ADDED');
EXCEPTION WHEN exclusion_violation OR unique_violation THEN
  RETURN audit.record_write_decision('ADD','CRM_CLIENT_PARTY',p_id,false,
    'OVERLAPPING_CLIENT_PARTY_DENIED');
END
$fn$;

CREATE FUNCTION crm.end_client_party(p_id uuid,p_event_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v crm.client_parties%ROWTYPE; v_now timestamptz:=clock_timestamp();
BEGIN
  SELECT * INTO v FROM crm.client_parties WHERE client_party_id=p_id FOR UPDATE;
  IF (FOUND AND v.status='ACTIVE' AND crm.is_crm_service()
      AND auth.current_family_id()=v.family_id AND core.is_uuid_v7(p_event_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('END','CRM_CLIENT_PARTY',p_id,false,
      'CRM_CLIENT_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.client_parties SET status='ENDED',valid_until=least(coalesce(v.valid_until,v_now),v_now),
    ended_by_principal_id=auth.current_principal_id() WHERE client_party_id=p_id;
  PERFORM crm.record_client_relationship_event(p_event_id,v.client_id,p_id,
    'PARTY_ENDED','ACTIVE','ENDED','CLIENT_PARTY_ENDED');
  RETURN audit.record_write_decision('END','CRM_CLIENT_PARTY',p_id,true,'CLIENT_PARTY_ENDED');
END
$fn$;

CREATE FUNCTION crm.create_partner_relationship(
  p_id uuid,p_kind text,p_subject uuid,p_type text,p_source uuid,p_valid_until timestamptz,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v_now timestamptz:=clock_timestamp();
BEGIN
  IF (crm.is_crm_service() AND auth.current_family_id() IS NULL
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event_id)
      AND p_kind IN ('PERSON','ORGANIZATION')
      AND p_type IN ('REFERRAL_PARTNER','CHANNEL_PARTNER','SERVICE_PARTNER','INSTITUTIONAL_PARTNER')
      AND (p_valid_until IS NULL OR p_valid_until>v_now)
      AND (p_type NOT IN ('REFERRAL_PARTNER','CHANNEL_PARTNER') OR p_source IS NOT NULL)
      AND (p_source IS NULL OR EXISTS(SELECT 1 FROM crm.lead_sources
        WHERE lead_source_id=p_source AND status='ACTIVE'))
      AND CASE p_kind
        WHEN 'PERSON' THEN EXISTS(SELECT 1 FROM core.people WHERE person_id=p_subject)
        WHEN 'ORGANIZATION' THEN EXISTS(SELECT 1 FROM core.organizations
          WHERE organization_id=p_subject AND status='ACTIVE') ELSE false END) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADD','CRM_PARTNER_RELATIONSHIP',p_id,false,
      'CRM_PARTNER_SUBJECT_SOURCE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO crm.partner_relationships(
    partner_relationship_id,partner_kind,partner_person_id,partner_organization_id,
    relationship_type,lead_source_id,status,valid_from,valid_until,created_by_principal_id
  ) VALUES(p_id,p_kind,
    CASE WHEN p_kind='PERSON' THEN p_subject END,
    CASE WHEN p_kind='ORGANIZATION' THEN p_subject END,
    p_type,p_source,'ACTIVE',v_now,p_valid_until,auth.current_principal_id());
  PERFORM crm.record_partner_relationship_event(p_event_id,p_id,'RELATIONSHIP_CREATED',
    NULL,'ACTIVE','PARTNER_RELATIONSHIP_CREATED');
  RETURN audit.record_write_decision('ADD','CRM_PARTNER_RELATIONSHIP',p_id,true,
    'PARTNER_RELATIONSHIP_CREATED');
EXCEPTION WHEN exclusion_violation OR unique_violation THEN
  RETURN audit.record_write_decision('ADD','CRM_PARTNER_RELATIONSHIP',p_id,false,
    'OVERLAPPING_PARTNER_RELATIONSHIP_DENIED');
END
$fn$;

CREATE FUNCTION crm.end_partner_relationship(p_id uuid,p_event_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v crm.partner_relationships%ROWTYPE; v_now timestamptz:=clock_timestamp();
BEGIN
  SELECT * INTO v FROM crm.partner_relationships WHERE partner_relationship_id=p_id FOR UPDATE;
  IF (FOUND AND v.status='ACTIVE' AND crm.is_crm_service()
      AND auth.current_family_id() IS NULL AND core.is_uuid_v7(p_event_id)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('END','CRM_PARTNER_RELATIONSHIP',p_id,false,
      'CRM_PARTNER_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.partner_relationships SET status='ENDED',valid_until=least(coalesce(v.valid_until,v_now),v_now),
    ended_by_principal_id=auth.current_principal_id() WHERE partner_relationship_id=p_id;
  PERFORM crm.record_partner_relationship_event(p_event_id,p_id,'RELATIONSHIP_ENDED',
    'ACTIVE','ENDED','PARTNER_RELATIONSHIP_ENDED');
  RETURN audit.record_write_decision('END','CRM_PARTNER_RELATIONSHIP',p_id,true,
    'PARTNER_RELATIONSHIP_ENDED');
END
$fn$;

ALTER TABLE crm.client_parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.client_parties FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.client_relationship_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.client_relationship_events FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.partner_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.partner_relationships FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.partner_relationship_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.partner_relationship_events FORCE ROW LEVEL SECURITY;

CREATE POLICY client_parties_crm_scope ON crm.client_parties FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND family_id=auth.current_family_id())
  WITH CHECK (crm.is_crm_service() AND family_id=auth.current_family_id());
CREATE POLICY client_relationship_events_crm_scope ON crm.client_relationship_events
  FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.clients c
    WHERE c.client_id=client_relationship_events.client_id AND c.family_id=auth.current_family_id()))
  WITH CHECK (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.clients c
    WHERE c.client_id=client_relationship_events.client_id AND c.family_id=auth.current_family_id()));
CREATE POLICY partner_relationships_crm_service ON crm.partner_relationships
  FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND auth.current_family_id() IS NULL)
  WITH CHECK (crm.is_crm_service() AND auth.current_family_id() IS NULL);
CREATE POLICY partner_relationship_events_crm_service ON crm.partner_relationship_events
  FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND auth.current_family_id() IS NULL)
  WITH CHECK (crm.is_crm_service() AND auth.current_family_id() IS NULL);

REVOKE ALL ON crm.client_parties,crm.client_relationship_events,
  crm.partner_relationships,crm.partner_relationship_events
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE EXECUTE ON FUNCTION crm.create_client(uuid,uuid,text),
  crm.transition_client(uuid,text) FROM phoenix_canonical_app;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crm FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  crm.create_client(uuid,uuid,text,uuid),
  crm.transition_client(uuid,text,uuid),
  crm.add_client_party(uuid,uuid,text,uuid,text,timestamptz,uuid),
  crm.end_client_party(uuid,uuid),
  crm.create_partner_relationship(uuid,text,uuid,text,uuid,timestamptz,uuid),
  crm.end_partner_relationship(uuid,uuid)
TO phoenix_canonical_app;

COMMIT;
