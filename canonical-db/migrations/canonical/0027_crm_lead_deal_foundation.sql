BEGIN;

-- Enterprise V2.0 / P1 CRM. Leads may exist before identity resolution; no
-- contact attribute is treated as a canonical Person/Family identity key.
CREATE TABLE crm.campaigns (
  campaign_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(campaign_id)),
  campaign_code text NOT NULL UNIQUE CHECK (campaign_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
  campaign_name text NOT NULL CHECK (length(btrim(campaign_name)) BETWEEN 1 AND 300),
  status text NOT NULL CHECK (status IN ('PLANNED','ACTIVE','PAUSED','CLOSED')),
  start_at timestamptz,
  end_at timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (end_at IS NULL OR start_at IS NULL OR end_at>start_at)
);

CREATE TABLE crm.lead_sources (
  lead_source_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(lead_source_id)),
  source_system text NOT NULL CHECK (source_system ~ '^[a-z][a-z0-9_-]{1,39}$'),
  source_channel text NOT NULL CHECK (source_channel IN (
    'WEBSITE','WECHAT','FEISHU','REFERRAL','PARTNER','EVENT','PHONE','EMAIL','OTHER'
  )),
  campaign_id uuid REFERENCES crm.campaigns,
  partner_organization_id uuid REFERENCES core.organizations,
  status text NOT NULL CHECK (status IN ('ACTIVE','INACTIVE')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE NULLS NOT DISTINCT(source_system,source_channel,campaign_id,partner_organization_id)
);

CREATE TABLE crm.leads (
  lead_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(lead_id)),
  lead_source_id uuid NOT NULL REFERENCES crm.lead_sources,
  campaign_id uuid REFERENCES crm.campaigns,
  partner_organization_id uuid REFERENCES core.organizations,
  contact_person_id uuid REFERENCES core.people,
  family_id uuid REFERENCES core.families,
  lead_status text NOT NULL CHECK (lead_status IN (
    'NEW','CONTACTED','QUALIFYING','QUALIFIED','DISQUALIFIED','CONVERTED','MERGED'
  )),
  qualification_status text NOT NULL CHECK (qualification_status IN (
    'UNVERIFIED','PENDING','QUALIFIED','UNQUALIFIED'
  )),
  assigned_principal_id uuid REFERENCES auth.principals,
  merged_into_lead_id uuid REFERENCES crm.leads,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK ((lead_status='MERGED')=(merged_into_lead_id IS NOT NULL)),
  CHECK (merged_into_lead_id IS NULL OR merged_into_lead_id<>lead_id)
);
CREATE INDEX leads_family_status_idx ON crm.leads(family_id,lead_status,updated_at DESC);
CREATE INDEX leads_source_created_idx ON crm.leads(lead_source_id,created_at DESC);
CREATE INDEX leads_assigned_status_idx ON crm.leads(assigned_principal_id,lead_status);

CREATE TABLE crm.lead_events (
  lead_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(lead_event_id)),
  lead_id uuid NOT NULL REFERENCES crm.leads,
  event_kind text NOT NULL CHECK (event_kind IN (
    'CREATED','STATUS_CHANGED','IDENTITY_LINKED','IDENTITY_VERIFIED',
    'IDENTITY_REVOKED','MERGED','ASSIGNED','CONSULTATION','DEAL_CREATED'
  )),
  from_status text,
  to_status text,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX lead_events_lead_time_idx ON crm.lead_events(lead_id,occurred_at,lead_event_id);

CREATE TABLE crm.lead_identity_links (
  lead_identity_link_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(lead_identity_link_id)),
  lead_id uuid NOT NULL REFERENCES crm.leads,
  target_kind text NOT NULL CHECK (target_kind IN ('PERSON','FAMILY','CLIENT')),
  person_id uuid REFERENCES core.people,
  family_id uuid REFERENCES core.families,
  client_id uuid REFERENCES crm.clients,
  status text NOT NULL CHECK (status IN ('PENDING','VERIFIED','REVOKED')),
  evidence_sha256 text NOT NULL CHECK (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  linked_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  verified_by_principal_id uuid REFERENCES auth.principals,
  revoked_by_principal_id uuid REFERENCES auth.principals,
  linked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  verified_at timestamptz,
  revoked_at timestamptz,
  CHECK (
    (target_kind='PERSON' AND person_id IS NOT NULL AND family_id IS NULL AND client_id IS NULL)
    OR (target_kind='FAMILY' AND person_id IS NULL AND family_id IS NOT NULL AND client_id IS NULL)
    OR (target_kind='CLIENT' AND person_id IS NULL AND family_id IS NULL AND client_id IS NOT NULL)
  ),
  CHECK (
    (status='PENDING' AND verified_by_principal_id IS NULL AND verified_at IS NULL
      AND revoked_by_principal_id IS NULL AND revoked_at IS NULL)
    OR (status='VERIFIED' AND verified_by_principal_id IS NOT NULL AND verified_at IS NOT NULL
      AND revoked_by_principal_id IS NULL AND revoked_at IS NULL)
    OR (status='REVOKED' AND revoked_by_principal_id IS NOT NULL AND revoked_at IS NOT NULL)
  )
);
CREATE UNIQUE INDEX lead_identity_person_current_uq
  ON crm.lead_identity_links(lead_id,person_id)
  WHERE target_kind='PERSON' AND status IN ('PENDING','VERIFIED');
CREATE UNIQUE INDEX lead_identity_family_current_uq
  ON crm.lead_identity_links(lead_id,family_id)
  WHERE target_kind='FAMILY' AND status IN ('PENDING','VERIFIED');
CREATE UNIQUE INDEX lead_identity_client_current_uq
  ON crm.lead_identity_links(lead_id,client_id)
  WHERE target_kind='CLIENT' AND status IN ('PENDING','VERIFIED');

ALTER TABLE crm.clients ADD CONSTRAINT clients_id_family_uq UNIQUE(client_id,family_id);

CREATE TABLE crm.consultations (
  consultation_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(consultation_id)),
  lead_id uuid REFERENCES crm.leads,
  client_id uuid,
  family_id uuid,
  subject_person_id uuid REFERENCES core.people,
  business_domain text NOT NULL CHECK (business_domain IN (
    'EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN'
  )),
  status text NOT NULL CHECK (status IN ('SCHEDULED','IN_PROGRESS','COMPLETED','CANCELLED','NO_SHOW')),
  owner_principal_id uuid NOT NULL REFERENCES auth.principals,
  scheduled_at timestamptz NOT NULL,
  started_at timestamptz,
  completed_at timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (lead_id IS NOT NULL OR client_id IS NOT NULL),
  CHECK ((client_id IS NULL AND family_id IS NULL)
      OR (client_id IS NOT NULL AND family_id IS NOT NULL)),
  FOREIGN KEY(client_id,family_id) REFERENCES crm.clients(client_id,family_id)
);
CREATE INDEX consultations_owner_schedule_idx ON crm.consultations(owner_principal_id,scheduled_at);

CREATE TABLE crm.client_relationships (
  client_relationship_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(client_relationship_id)),
  client_id uuid NOT NULL,
  family_id uuid NOT NULL,
  relationship_type text NOT NULL CHECK (relationship_type IN (
    'PRIMARY_CONTACT','FAMILY_ADMIN','REFERRER','PARTNER','ADVISOR','BILLING_CONTACT'
  )),
  related_person_id uuid REFERENCES core.people,
  related_organization_id uuid REFERENCES core.organizations,
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK ((related_person_id IS NOT NULL)<>(related_organization_id IS NOT NULL)),
  CHECK (valid_until IS NULL OR valid_until>valid_from),
  FOREIGN KEY(client_id,family_id) REFERENCES crm.clients(client_id,family_id)
);
ALTER TABLE crm.client_relationships ADD CONSTRAINT client_person_relationship_no_overlap
  EXCLUDE USING gist (client_id WITH =,relationship_type WITH =,related_person_id WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&)
  WHERE (related_person_id IS NOT NULL);
ALTER TABLE crm.client_relationships ADD CONSTRAINT client_organization_relationship_no_overlap
  EXCLUDE USING gist (client_id WITH =,relationship_type WITH =,related_organization_id WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&)
  WHERE (related_organization_id IS NOT NULL);

CREATE TABLE crm.deals (
  deal_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(deal_id)),
  client_id uuid NOT NULL,
  family_id uuid NOT NULL,
  primary_lead_id uuid REFERENCES crm.leads,
  deal_name text NOT NULL CHECK (length(btrim(deal_name)) BETWEEN 1 AND 300),
  business_domain text NOT NULL CHECK (business_domain IN (
    'EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN'
  )),
  deal_status text NOT NULL CHECK (deal_status IN (
    'DRAFT','QUALIFYING','PROPOSAL','NEGOTIATION','WON','LOST','CANCELLED'
  )),
  estimated_amount numeric(18,2) CHECK (estimated_amount IS NULL OR estimated_amount>=0),
  currency text CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
  expected_close_at timestamptz,
  owner_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  updated_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  FOREIGN KEY(client_id,family_id) REFERENCES crm.clients(client_id,family_id),
  CHECK ((estimated_amount IS NULL)=(currency IS NULL))
);
CREATE INDEX deals_client_status_idx ON crm.deals(client_id,deal_status,updated_at DESC);
CREATE INDEX deals_owner_status_idx ON crm.deals(owner_principal_id,deal_status);

CREATE TABLE crm.deal_items (
  deal_item_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(deal_item_id)),
  deal_id uuid NOT NULL REFERENCES crm.deals,
  item_code text NOT NULL CHECK (item_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
  item_name text NOT NULL CHECK (length(btrim(item_name)) BETWEEN 1 AND 300),
  business_domain text NOT NULL CHECK (business_domain IN (
    'EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE'
  )),
  compass_kind text CHECK (compass_kind IN (
    'CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS'
  )),
  quantity numeric(12,3) NOT NULL CHECK (quantity>0),
  estimated_amount numeric(18,2) NOT NULL CHECK (estimated_amount>=0),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE(deal_id,item_code)
);

CREATE TABLE crm.referrals (
  referral_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(referral_id)),
  lead_id uuid REFERENCES crm.leads,
  client_id uuid REFERENCES crm.clients,
  referrer_person_id uuid REFERENCES core.people,
  referrer_organization_id uuid REFERENCES core.organizations,
  status text NOT NULL CHECK (status IN ('RECORDED','CONFIRMED','REVOKED')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  revoked_at timestamptz,
  CHECK (lead_id IS NOT NULL OR client_id IS NOT NULL),
  CHECK ((referrer_person_id IS NOT NULL)<>(referrer_organization_id IS NOT NULL)),
  CHECK ((status='REVOKED')=(revoked_at IS NOT NULL))
);

CREATE TABLE crm.follow_ups (
  follow_up_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(follow_up_id)),
  target_kind text NOT NULL CHECK (target_kind IN ('LEAD','DEAL','CLIENT')),
  lead_id uuid REFERENCES crm.leads,
  deal_id uuid REFERENCES crm.deals,
  client_id uuid REFERENCES crm.clients,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 300),
  status text NOT NULL CHECK (status IN ('PENDING','COMPLETED','CANCELLED')),
  assigned_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (
    (target_kind='LEAD' AND lead_id IS NOT NULL AND deal_id IS NULL AND client_id IS NULL)
    OR (target_kind='DEAL' AND lead_id IS NULL AND deal_id IS NOT NULL AND client_id IS NULL)
    OR (target_kind='CLIENT' AND lead_id IS NULL AND deal_id IS NULL AND client_id IS NOT NULL)
  ),
  CHECK ((status='COMPLETED')=(completed_at IS NOT NULL))
);

CREATE FUNCTION crm.is_crm_service() RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth
RETURN coalesce(auth.is_internal_service() AND EXISTS (
  SELECT 1 FROM auth.principals p
   WHERE p.principal_id=auth.current_principal_id()
     AND p.principal_kind='SERVICE' AND p.person_id IS NULL
     AND p.status='ACTIVE' AND p.service_label='canonical_crm_v2'
),false);

CREATE FUNCTION crm.record_lead_event(
  p_event_id uuid,p_lead_id uuid,p_event_kind text,p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm
AS $fn$
BEGIN
  IF (crm.is_crm_service() AND core.is_uuid_v7(p_event_id)
      AND p_event_kind IN ('CREATED','STATUS_CHANGED','IDENTITY_LINKED','IDENTITY_VERIFIED',
        'IDENTITY_REVOKED','MERGED','ASSIGNED','CONSULTATION','DEAL_CREATED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN
    RAISE EXCEPTION 'CRM_EVENT_CONTEXT_OR_INPUT_DENIED';
  END IF;
  INSERT INTO crm.lead_events(lead_event_id,lead_id,event_kind,from_status,to_status,
    reason_code,actor_principal_id)
  VALUES(p_event_id,p_lead_id,p_event_kind,p_from,p_to,p_reason,auth.current_principal_id());
END
$fn$;

CREATE FUNCTION crm.reject_lead_event_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,crm AS $fn$
BEGIN RAISE EXCEPTION 'CRM_LEAD_EVENT_IMMUTABLE'; END
$fn$;
CREATE TRIGGER reject_lead_event_update BEFORE UPDATE OR DELETE ON crm.lead_events
FOR EACH ROW EXECUTE FUNCTION crm.reject_lead_event_change();

CREATE FUNCTION crm.register_campaign(
  p_id uuid,p_code text,p_name text,p_status text,p_start timestamptz,p_end timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
BEGIN
  IF (crm.is_crm_service() AND auth.current_family_id() IS NULL AND core.is_uuid_v7(p_id)
      AND p_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'
      AND length(btrim(p_name)) BETWEEN 1 AND 300
      AND p_status IN ('PLANNED','ACTIVE','PAUSED','CLOSED')
      AND (p_end IS NULL OR p_start IS NULL OR p_end>p_start)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_CAMPAIGN',p_id,false,'CRM_SERVICE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.campaigns WHERE campaign_id=p_id OR campaign_code=p_code) THEN
    RETURN audit.record_write_decision('CREATE','CRM_CAMPAIGN',p_id,false,'CAMPAIGN_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.campaigns(campaign_id,campaign_code,campaign_name,status,start_at,end_at,
    created_by_principal_id,updated_by_principal_id)
  VALUES(p_id,p_code,btrim(p_name),p_status,p_start,p_end,auth.current_principal_id(),auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','CRM_CAMPAIGN',p_id,true,'CAMPAIGN_CREATED');
END $fn$;

CREATE FUNCTION crm.register_lead_source(
  p_id uuid,p_system text,p_channel text,p_campaign uuid,p_partner uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
BEGIN
  IF (crm.is_crm_service() AND auth.current_family_id() IS NULL AND core.is_uuid_v7(p_id)
      AND p_system ~ '^[a-z][a-z0-9_-]{1,39}$'
      AND p_channel IN ('WEBSITE','WECHAT','FEISHU','REFERRAL','PARTNER','EVENT','PHONE','EMAIL','OTHER')
      AND (p_campaign IS NULL OR EXISTS(SELECT 1 FROM crm.campaigns WHERE campaign_id=p_campaign))
      AND (p_partner IS NULL OR EXISTS(SELECT 1 FROM core.organizations WHERE organization_id=p_partner))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_LEAD_SOURCE',p_id,false,'CRM_SERVICE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.lead_sources WHERE lead_source_id=p_id OR
      (source_system=p_system AND source_channel=p_channel
       AND campaign_id IS NOT DISTINCT FROM p_campaign
       AND partner_organization_id IS NOT DISTINCT FROM p_partner)) THEN
    RETURN audit.record_write_decision('CREATE','CRM_LEAD_SOURCE',p_id,false,'LEAD_SOURCE_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.lead_sources(lead_source_id,source_system,source_channel,campaign_id,
    partner_organization_id,status,created_by_principal_id)
  VALUES(p_id,p_system,p_channel,p_campaign,p_partner,'ACTIVE',auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','CRM_LEAD_SOURCE',p_id,true,'LEAD_SOURCE_CREATED');
END $fn$;

CREATE FUNCTION crm.create_lead(
  p_id uuid,p_source uuid,p_contact_person uuid,p_family uuid,p_assignee uuid,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v_source crm.lead_sources%ROWTYPE;
BEGIN
  SELECT * INTO v_source FROM crm.lead_sources WHERE lead_source_id=p_source AND status='ACTIVE';
  IF (FOUND AND crm.is_crm_service() AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event_id)
      AND ((p_family IS NULL AND auth.current_family_id() IS NULL)
        OR (p_family IS NOT NULL AND auth.current_family_id()=p_family
          AND EXISTS(SELECT 1 FROM core.families WHERE family_id=p_family)))
      AND (p_contact_person IS NULL OR EXISTS(SELECT 1 FROM core.people WHERE person_id=p_contact_person))
      AND (p_contact_person IS NULL OR p_family IS NULL OR EXISTS(
        SELECT 1 FROM core.family_memberships WHERE family_id=p_family AND person_id=p_contact_person
          AND valid_from<=clock_timestamp() AND (valid_until IS NULL OR valid_until>clock_timestamp())))
      AND (p_assignee IS NULL OR EXISTS(SELECT 1 FROM auth.principals
        WHERE principal_id=p_assignee AND status='ACTIVE'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_LEAD',p_id,false,'CRM_SCOPE_IDENTITY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.leads WHERE lead_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','CRM_LEAD',p_id,false,'LEAD_ID_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.leads(lead_id,lead_source_id,campaign_id,partner_organization_id,
    contact_person_id,family_id,lead_status,qualification_status,assigned_principal_id,
    created_by_principal_id,updated_by_principal_id)
  VALUES(p_id,p_source,v_source.campaign_id,v_source.partner_organization_id,p_contact_person,
    p_family,'NEW','UNVERIFIED',p_assignee,auth.current_principal_id(),auth.current_principal_id());
  PERFORM crm.record_lead_event(p_event_id,p_id,'CREATED',NULL,'NEW','LEAD_CREATED');
  RETURN audit.record_write_decision('CREATE','CRM_LEAD',p_id,true,'UNVERIFIED_LEAD_CREATED');
END $fn$;

CREATE FUNCTION crm.link_lead_identity(
  p_link_id uuid,p_lead_id uuid,p_target_kind text,p_target_id uuid,
  p_evidence_sha256 text,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v_lead crm.leads%ROWTYPE; v_target_family uuid;
BEGIN
  SELECT * INTO v_lead FROM crm.leads WHERE lead_id=p_lead_id FOR UPDATE;
  IF NOT FOUND OR p_target_kind NOT IN ('PERSON','FAMILY','CLIENT') THEN
    RETURN audit.record_write_decision('LINK','CRM_LEAD_IDENTITY',p_link_id,false,'LEAD_OR_TARGET_KIND_DENIED');
  END IF;
  IF p_target_kind='FAMILY' THEN v_target_family:=p_target_id;
  ELSIF p_target_kind='CLIENT' THEN SELECT family_id INTO v_target_family FROM crm.clients WHERE client_id=p_target_id;
  ELSE v_target_family:=v_lead.family_id; END IF;
  IF (crm.is_crm_service() AND core.is_uuid_v7(p_link_id) AND core.is_uuid_v7(p_event_id)
      AND p_evidence_sha256 ~ '^[0-9a-f]{64}$'
      AND ((v_target_family IS NULL AND auth.current_family_id() IS NULL)
        OR auth.current_family_id()=v_target_family)
      AND (v_lead.family_id IS NULL OR v_target_family IS NULL OR v_lead.family_id=v_target_family)
      AND CASE p_target_kind
        WHEN 'PERSON' THEN EXISTS(SELECT 1 FROM core.people WHERE person_id=p_target_id)
        WHEN 'FAMILY' THEN EXISTS(SELECT 1 FROM core.families WHERE family_id=p_target_id)
        WHEN 'CLIENT' THEN v_target_family IS NOT NULL ELSE false END) IS NOT TRUE THEN
    RETURN audit.record_write_decision('LINK','CRM_LEAD_IDENTITY',p_link_id,false,'CRM_SCOPE_TARGET_OR_EVIDENCE_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.lead_identity_links WHERE lead_identity_link_id=p_link_id
      OR (lead_id=p_lead_id AND status IN ('PENDING','VERIFIED') AND
        CASE p_target_kind WHEN 'PERSON' THEN person_id=p_target_id
          WHEN 'FAMILY' THEN family_id=p_target_id WHEN 'CLIENT' THEN client_id=p_target_id END)) THEN
    RETURN audit.record_write_decision('LINK','CRM_LEAD_IDENTITY',p_link_id,false,'CURRENT_LINK_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.lead_identity_links(lead_identity_link_id,lead_id,target_kind,person_id,family_id,
    client_id,status,evidence_sha256,linked_by_principal_id)
  VALUES(p_link_id,p_lead_id,p_target_kind,
    CASE WHEN p_target_kind='PERSON' THEN p_target_id END,
    CASE WHEN p_target_kind='FAMILY' THEN p_target_id END,
    CASE WHEN p_target_kind='CLIENT' THEN p_target_id END,
    'PENDING',p_evidence_sha256,auth.current_principal_id());
  PERFORM crm.record_lead_event(p_event_id,p_lead_id,'IDENTITY_LINKED',NULL,'PENDING','IDENTITY_LINK_PENDING');
  RETURN audit.record_write_decision('LINK','CRM_LEAD_IDENTITY',p_link_id,true,'IDENTITY_LINK_PENDING');
END $fn$;

CREATE FUNCTION crm.verify_lead_identity(p_link_id uuid,p_event_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.lead_identity_links%ROWTYPE; v_family uuid;
BEGIN
  SELECT * INTO v FROM crm.lead_identity_links WHERE lead_identity_link_id=p_link_id FOR UPDATE;
  SELECT coalesce(v.family_id,c.family_id,l.family_id) INTO v_family
    FROM crm.leads l LEFT JOIN crm.clients c ON c.client_id=v.client_id WHERE l.lead_id=v.lead_id;
  IF (FOUND AND v.status='PENDING' AND crm.is_crm_service()
      AND auth.current_principal_id()<>v.linked_by_principal_id
      AND core.is_uuid_v7(p_event_id)
      AND ((v_family IS NULL AND auth.current_family_id() IS NULL) OR auth.current_family_id()=v_family)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('VERIFY','CRM_LEAD_IDENTITY',p_link_id,false,'DISTINCT_REVIEWER_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.lead_identity_links SET status='VERIFIED',verified_by_principal_id=auth.current_principal_id(),
    verified_at=clock_timestamp() WHERE lead_identity_link_id=p_link_id;
  UPDATE crm.leads SET family_id=coalesce(family_id,v_family),
    qualification_status='QUALIFIED',lead_status='QUALIFIED',
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE lead_id=v.lead_id AND lead_status<>'MERGED';
  PERFORM crm.record_lead_event(p_event_id,v.lead_id,'IDENTITY_VERIFIED','PENDING','VERIFIED','IDENTITY_LINK_VERIFIED');
  RETURN audit.record_write_decision('VERIFY','CRM_LEAD_IDENTITY',p_link_id,true,'DISTINCT_REVIEWER_VERIFIED');
END $fn$;

CREATE FUNCTION crm.revoke_lead_identity(p_link_id uuid,p_event_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.lead_identity_links%ROWTYPE; v_family uuid;
BEGIN
  SELECT * INTO v FROM crm.lead_identity_links WHERE lead_identity_link_id=p_link_id FOR UPDATE;
  SELECT coalesce(v.family_id,c.family_id,l.family_id) INTO v_family
    FROM crm.leads l LEFT JOIN crm.clients c ON c.client_id=v.client_id WHERE l.lead_id=v.lead_id;
  IF (FOUND AND v.status IN ('PENDING','VERIFIED') AND crm.is_crm_service()
      AND core.is_uuid_v7(p_event_id)
      AND ((v_family IS NULL AND auth.current_family_id() IS NULL) OR auth.current_family_id()=v_family)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVOKE','CRM_LEAD_IDENTITY',p_link_id,false,'CRM_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.lead_identity_links SET status='REVOKED',revoked_by_principal_id=auth.current_principal_id(),
    revoked_at=clock_timestamp() WHERE lead_identity_link_id=p_link_id;
  PERFORM crm.record_lead_event(p_event_id,v.lead_id,'IDENTITY_REVOKED',v.status,'REVOKED','IDENTITY_LINK_REVOKED');
  RETURN audit.record_write_decision('REVOKE','CRM_LEAD_IDENTITY',p_link_id,true,'IDENTITY_LINK_REVOKED');
END $fn$;

CREATE FUNCTION crm.merge_lead(p_source uuid,p_target uuid,p_event_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE s crm.leads%ROWTYPE; t crm.leads%ROWTYPE; v_family uuid;
BEGIN
  IF p_source=p_target THEN RETURN audit.record_write_decision('MERGE','CRM_LEAD',p_source,false,'SELF_MERGE_DENIED'); END IF;
  SELECT * INTO s FROM crm.leads WHERE lead_id=p_source FOR UPDATE;
  SELECT * INTO t FROM crm.leads WHERE lead_id=p_target FOR UPDATE;
  v_family:=coalesce(s.family_id,t.family_id);
  IF (s.lead_id IS NOT NULL AND t.lead_id IS NOT NULL AND s.lead_status<>'MERGED' AND t.lead_status<>'MERGED'
      AND crm.is_crm_service() AND core.is_uuid_v7(p_event_id)
      AND (s.family_id IS NULL OR t.family_id IS NULL OR s.family_id=t.family_id)
      AND ((v_family IS NULL AND auth.current_family_id() IS NULL) OR auth.current_family_id()=v_family)
      AND NOT EXISTS (
        SELECT 1 FROM crm.lead_identity_links a JOIN crm.lead_identity_links b
          ON a.target_kind=b.target_kind AND a.lead_id=p_source AND b.lead_id=p_target
         AND a.status='VERIFIED' AND b.status='VERIFIED'
         AND (a.person_id IS DISTINCT FROM b.person_id OR a.family_id IS DISTINCT FROM b.family_id
           OR a.client_id IS DISTINCT FROM b.client_id)
      )) IS NOT TRUE THEN
    RETURN audit.record_write_decision('MERGE','CRM_LEAD',p_source,false,'CRM_SCOPE_STATE_OR_IDENTITY_CONFLICT');
  END IF;
  UPDATE crm.leads SET lead_status='MERGED',merged_into_lead_id=p_target,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE lead_id=p_source;
  PERFORM crm.record_lead_event(p_event_id,p_source,'MERGED',s.lead_status,'MERGED','AUDITED_LEAD_MERGE');
  RETURN audit.record_write_decision('MERGE','CRM_LEAD',p_source,true,'AUDITED_LEAD_MERGE');
END $fn$;

CREATE FUNCTION crm.create_deal(
  p_id uuid,p_client uuid,p_family uuid,p_primary_lead uuid,p_name text,p_domain text,
  p_amount numeric,p_currency text,p_expected_close timestamptz,p_owner uuid,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
BEGIN
  IF (crm.is_crm_service() AND auth.current_family_id()=p_family
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event_id)
      AND EXISTS(SELECT 1 FROM crm.clients WHERE client_id=p_client AND family_id=p_family
        AND lifecycle_status IN ('ACTIVE','PAUSED'))
      AND (p_primary_lead IS NULL OR EXISTS(SELECT 1 FROM crm.lead_identity_links
        WHERE lead_id=p_primary_lead AND target_kind='CLIENT' AND client_id=p_client AND status='VERIFIED'))
      AND length(btrim(p_name)) BETWEEN 1 AND 300
      AND p_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN')
      AND p_amount>=0 AND p_currency ~ '^[A-Z]{3}$'
      AND EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_owner AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_DEAL',p_id,false,'CRM_CLIENT_LEAD_SCOPE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.deals WHERE deal_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','CRM_DEAL',p_id,false,'DEAL_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.deals(deal_id,client_id,family_id,primary_lead_id,deal_name,business_domain,
    deal_status,estimated_amount,currency,expected_close_at,owner_principal_id,
    created_by_principal_id,updated_by_principal_id)
  VALUES(p_id,p_client,p_family,p_primary_lead,btrim(p_name),p_domain,'DRAFT',p_amount,p_currency,
    p_expected_close,p_owner,auth.current_principal_id(),auth.current_principal_id());
  IF p_primary_lead IS NOT NULL THEN
    PERFORM crm.record_lead_event(p_event_id,p_primary_lead,'DEAL_CREATED',NULL,'DRAFT','DEAL_CREATED_FROM_VERIFIED_LEAD');
  END IF;
  RETURN audit.record_write_decision('CREATE','CRM_DEAL',p_id,true,'DEAL_CREATED');
END $fn$;

CREATE FUNCTION crm.add_deal_item(
  p_id uuid,p_deal uuid,p_code text,p_name text,p_domain text,p_compass text,
  p_quantity numeric,p_amount numeric,p_currency text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v_family uuid;
BEGIN
  SELECT family_id INTO v_family FROM crm.deals WHERE deal_id=p_deal;
  IF (FOUND AND crm.is_crm_service() AND auth.current_family_id()=v_family
      AND core.is_uuid_v7(p_id) AND p_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'
      AND length(btrim(p_name)) BETWEEN 1 AND 300
      AND p_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE')
      AND (p_compass IS NULL OR p_compass IN ('CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS'))
      AND p_quantity>0 AND p_amount>=0 AND p_currency ~ '^[A-Z]{3}$') IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_DEAL_ITEM',p_id,false,'CRM_DEAL_SCOPE_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.deal_items WHERE deal_item_id=p_id OR (deal_id=p_deal AND item_code=p_code)) THEN
    RETURN audit.record_write_decision('CREATE','CRM_DEAL_ITEM',p_id,false,'DEAL_ITEM_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.deal_items(deal_item_id,deal_id,item_code,item_name,business_domain,compass_kind,
    quantity,estimated_amount,currency,created_by_principal_id)
  VALUES(p_id,p_deal,p_code,btrim(p_name),p_domain,p_compass,p_quantity,p_amount,p_currency,auth.current_principal_id());
  RETURN audit.record_write_decision('CREATE','CRM_DEAL_ITEM',p_id,true,'DEAL_ITEM_CREATED');
END $fn$;

-- All P1 tables are fail-closed to direct runtime access. RLS remains a second
-- boundary for future approved read APIs; current writes are functions only.
ALTER TABLE crm.campaigns ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.campaigns FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_sources ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.lead_sources FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.leads ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.leads FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_events ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.lead_events FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_identity_links ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.lead_identity_links FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.consultations ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.consultations FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.client_relationships ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.client_relationships FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.deals ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.deals FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.deal_items ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.deal_items FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.referrals ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.referrals FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.follow_ups ENABLE ROW LEVEL SECURITY; ALTER TABLE crm.follow_ups FORCE ROW LEVEL SECURITY;

CREATE POLICY campaigns_crm_service ON crm.campaigns FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND auth.current_family_id() IS NULL)
  WITH CHECK (crm.is_crm_service() AND auth.current_family_id() IS NULL);
CREATE POLICY lead_sources_crm_service ON crm.lead_sources FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND auth.current_family_id() IS NULL)
  WITH CHECK (crm.is_crm_service() AND auth.current_family_id() IS NULL);
CREATE POLICY leads_crm_scope ON crm.leads FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND ((family_id IS NULL AND auth.current_family_id() IS NULL) OR family_id=auth.current_family_id()))
  WITH CHECK (crm.is_crm_service() AND ((family_id IS NULL AND auth.current_family_id() IS NULL) OR family_id=auth.current_family_id()));
CREATE POLICY lead_events_crm_service ON crm.lead_events FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service()) WITH CHECK (crm.is_crm_service());
CREATE POLICY lead_identity_links_crm_service ON crm.lead_identity_links FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service()) WITH CHECK (crm.is_crm_service());
CREATE POLICY consultations_crm_scope ON crm.consultations FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND ((family_id IS NULL AND auth.current_family_id() IS NULL) OR family_id=auth.current_family_id()))
  WITH CHECK (crm.is_crm_service() AND ((family_id IS NULL AND auth.current_family_id() IS NULL) OR family_id=auth.current_family_id()));
CREATE POLICY client_relationships_crm_scope ON crm.client_relationships FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND family_id=auth.current_family_id())
  WITH CHECK (crm.is_crm_service() AND family_id=auth.current_family_id());
CREATE POLICY deals_crm_scope ON crm.deals FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND family_id=auth.current_family_id())
  WITH CHECK (crm.is_crm_service() AND family_id=auth.current_family_id());
CREATE POLICY deal_items_crm_service ON crm.deal_items FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service()) WITH CHECK (crm.is_crm_service());
CREATE POLICY referrals_crm_service ON crm.referrals FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service()) WITH CHECK (crm.is_crm_service());
CREATE POLICY follow_ups_crm_service ON crm.follow_ups FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service()) WITH CHECK (crm.is_crm_service());

REVOKE ALL ON ALL TABLES IN SCHEMA crm
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crm FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.is_crm_service(),
  crm.register_campaign(uuid,text,text,text,timestamptz,timestamptz),
  crm.register_lead_source(uuid,text,text,uuid,uuid),
  crm.create_lead(uuid,uuid,uuid,uuid,uuid,uuid),
  crm.link_lead_identity(uuid,uuid,text,uuid,text,uuid),
  crm.verify_lead_identity(uuid,uuid),crm.revoke_lead_identity(uuid,uuid),
  crm.merge_lead(uuid,uuid,uuid),
  crm.create_deal(uuid,uuid,uuid,uuid,text,text,numeric,text,timestamptz,uuid,uuid),
  crm.add_deal_item(uuid,uuid,text,text,text,text,numeric,numeric,text)
TO phoenix_canonical_app;

COMMIT;
