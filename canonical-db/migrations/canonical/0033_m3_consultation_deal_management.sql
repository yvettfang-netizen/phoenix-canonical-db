BEGIN;

-- V2.0 M3 extends the existing CRM authority. It does not introduce payment,
-- contract, Person, Family, Client or Principal masters.

ALTER TABLE crm.consultations
  ADD COLUMN consultation_type text,
  ADD COLUMN compass_kind text,
  ADD COLUMN result_code text,
  ADD COLUMN next_action_code text,
  ADD CONSTRAINT consultations_type_check CHECK (consultation_type IS NULL OR consultation_type IN (
    'DISCOVERY','COMPASS_REVIEW','NEEDS_ANALYSIS','PROPOSAL_REVIEW','FOLLOW_UP'
  )),
  ADD CONSTRAINT consultations_compass_check CHECK (compass_kind IS NULL OR compass_kind IN (
    'CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS'
  )),
  ADD CONSTRAINT consultations_result_code_check CHECK (
    result_code IS NULL OR result_code ~ '^[A-Z0-9_]{2,80}$'
  ),
  ADD CONSTRAINT consultations_next_action_code_check CHECK (
    next_action_code IS NULL OR next_action_code ~ '^[A-Z0-9_]{2,80}$'
  );

ALTER TABLE crm.deals
  DROP CONSTRAINT deals_deal_status_check,
  ADD CONSTRAINT deals_deal_status_check CHECK (deal_status IN (
    'DRAFT','QUALIFYING','OPEN','QUALIFIED','PROPOSAL','NEGOTIATION','WON','LOST','CANCELLED'
  )),
  ADD COLUMN partner_referral_id uuid REFERENCES crm.referrals,
  ADD COLUMN won_lost_reason_code text,
  ADD CONSTRAINT deals_won_lost_reason_check CHECK (
    (deal_status IN ('WON','LOST') AND won_lost_reason_code ~ '^[A-Z0-9_]{2,80}$')
    OR (deal_status NOT IN ('WON','LOST') AND won_lost_reason_code IS NULL)
  );

ALTER TABLE crm.deal_items
  DROP CONSTRAINT deal_items_compass_kind_check,
  ADD CONSTRAINT deal_items_compass_kind_check CHECK (compass_kind IN (
    'CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS'
  ));

CREATE TABLE crm.consultation_events (
  consultation_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(consultation_event_id)),
  consultation_id uuid NOT NULL REFERENCES crm.consultations,
  event_kind text NOT NULL CHECK (event_kind IN ('CREATED','STATUS_CHANGED','OWNER_CHANGED')),
  from_status text,
  to_status text,
  from_owner_principal_id uuid REFERENCES auth.principals,
  to_owner_principal_id uuid REFERENCES auth.principals,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX consultation_events_consultation_idx
  ON crm.consultation_events(consultation_id,occurred_at);

CREATE TABLE crm.deal_events (
  deal_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(deal_event_id)),
  deal_id uuid NOT NULL REFERENCES crm.deals,
  event_kind text NOT NULL CHECK (event_kind IN (
    'CREATED','STATUS_CHANGED','AMOUNT_CHANGED','OWNER_CHANGED','SCOPE_ADDED','PROJECT_CANDIDATE_ADDED'
  )),
  from_status text,
  to_status text,
  old_amount numeric(18,2),
  new_amount numeric(18,2),
  old_owner_principal_id uuid REFERENCES auth.principals,
  new_owner_principal_id uuid REFERENCES auth.principals,
  scope_code text,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX deal_events_deal_idx ON crm.deal_events(deal_id,occurred_at);

CREATE TABLE crm.sales_assignments (
  sales_assignment_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(sales_assignment_id)),
  deal_id uuid NOT NULL REFERENCES crm.deals,
  principal_id uuid NOT NULL REFERENCES auth.principals,
  assignment_role text NOT NULL CHECK (assignment_role IN ('PRIMARY_OWNER','CONTRIBUTOR')),
  status text NOT NULL CHECK (status IN ('ACTIVE','REVOKED')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  assigned_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  revoked_by_principal_id uuid REFERENCES auth.principals,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  CHECK (valid_until IS NULL OR valid_until>valid_from),
  CHECK ((status='REVOKED')=(valid_until IS NOT NULL AND revoked_by_principal_id IS NOT NULL))
);
ALTER TABLE crm.sales_assignments ADD CONSTRAINT sales_primary_owner_no_overlap
  EXCLUDE USING gist (deal_id WITH =,assignment_role WITH =,
    tstzrange(valid_from,coalesce(valid_until,'infinity'::timestamptz),'[)') WITH &&)
  WHERE (assignment_role='PRIMARY_OWNER');
CREATE INDEX sales_assignments_principal_idx
  ON crm.sales_assignments(principal_id,status,valid_until);

CREATE TABLE crm.deal_project_candidates (
  deal_project_candidate_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(deal_project_candidate_id)),
  deal_id uuid NOT NULL REFERENCES crm.deals,
  candidate_code text NOT NULL CHECK (candidate_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
  business_domain text NOT NULL CHECK (business_domain IN (
    'EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE'
  )),
  compass_kind text CHECK (compass_kind IN (
    'CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS'
  )),
  status text NOT NULL CHECK (status IN ('PROPOSED','APPROVED','DISMISSED')),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT transaction_timestamp(),
  UNIQUE(deal_id,candidate_code)
);

CREATE FUNCTION crm.reject_m3_history_change() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'CRM_M3_HISTORY_IMMUTABLE';
END
$fn$;

CREATE TRIGGER consultation_events_immutable BEFORE UPDATE OR DELETE ON crm.consultation_events
  FOR EACH ROW EXECUTE FUNCTION crm.reject_m3_history_change();
CREATE TRIGGER deal_events_immutable BEFORE UPDATE OR DELETE ON crm.deal_events
  FOR EACH ROW EXECUTE FUNCTION crm.reject_m3_history_change();

CREATE FUNCTION crm.record_consultation_event(
  p_event uuid,p_consultation uuid,p_kind text,p_from text,p_to text,
  p_old_owner uuid,p_new_owner uuid,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm AS $fn$
BEGIN
  IF (crm.is_crm_service() AND core.is_uuid_v7(p_event)
      AND p_kind IN ('CREATED','STATUS_CHANGED','OWNER_CHANGED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN
    RAISE EXCEPTION 'CRM_CONSULTATION_EVENT_DENIED';
  END IF;
  INSERT INTO crm.consultation_events(
    consultation_event_id,consultation_id,event_kind,from_status,to_status,
    from_owner_principal_id,to_owner_principal_id,reason_code,actor_principal_id
  ) VALUES(p_event,p_consultation,p_kind,p_from,p_to,p_old_owner,p_new_owner,
    p_reason,auth.current_principal_id());
END
$fn$;

CREATE FUNCTION crm.record_deal_event(
  p_event uuid,p_deal uuid,p_kind text,p_from text,p_to text,
  p_old_amount numeric,p_new_amount numeric,p_old_owner uuid,p_new_owner uuid,
  p_scope text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm AS $fn$
BEGIN
  IF (crm.is_crm_service() AND core.is_uuid_v7(p_event)
      AND p_kind IN ('CREATED','STATUS_CHANGED','AMOUNT_CHANGED','OWNER_CHANGED','SCOPE_ADDED','PROJECT_CANDIDATE_ADDED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN
    RAISE EXCEPTION 'CRM_DEAL_EVENT_DENIED';
  END IF;
  INSERT INTO crm.deal_events(
    deal_event_id,deal_id,event_kind,from_status,to_status,old_amount,new_amount,
    old_owner_principal_id,new_owner_principal_id,scope_code,reason_code,actor_principal_id
  ) VALUES(p_event,p_deal,p_kind,p_from,p_to,p_old_amount,p_new_amount,p_old_owner,
    p_new_owner,p_scope,p_reason,auth.current_principal_id());
END
$fn$;

CREATE FUNCTION crm.create_consultation(
  p_id uuid,p_lead uuid,p_client uuid,p_family uuid,p_subject uuid,p_domain text,
  p_type text,p_compass text,p_owner uuid,p_scheduled timestamptz,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE l crm.leads%ROWTYPE;
BEGIN
  IF p_lead IS NOT NULL THEN SELECT * INTO l FROM crm.leads WHERE lead_id=p_lead; END IF;
  IF (crm.is_crm_service() AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND ((p_family IS NULL AND auth.current_family_id() IS NULL) OR p_family=auth.current_family_id())
      AND (p_lead IS NOT NULL OR p_client IS NOT NULL)
      AND (p_lead IS NULL OR l.lead_id IS NOT NULL)
      AND (p_client IS NULL OR EXISTS(SELECT 1 FROM crm.clients
        WHERE client_id=p_client AND family_id=p_family AND lifecycle_status IN ('ACTIVE','PAUSED')))
      AND (p_lead IS NULL OR l.family_id IS NOT DISTINCT FROM p_family)
      AND (p_subject IS NULL OR EXISTS(SELECT 1 FROM core.family_memberships
        WHERE family_id=p_family AND person_id=p_subject AND valid_from<=clock_timestamp()
          AND (valid_until IS NULL OR valid_until>clock_timestamp())))
      AND p_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN')
      AND p_type IN ('DISCOVERY','COMPASS_REVIEW','NEEDS_ANALYSIS','PROPOSAL_REVIEW','FOLLOW_UP')
      AND (p_compass IS NULL OR p_compass IN ('CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS'))
      AND EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_owner AND status='ACTIVE')
      AND p_scheduled>clock_timestamp()-interval '1 minute') IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_CONSULTATION',p_id,false,
      'CRM_SCOPE_SUBJECT_OWNER_OR_INPUT_DENIED');
  END IF;
  INSERT INTO crm.consultations(
    consultation_id,lead_id,client_id,family_id,subject_person_id,business_domain,status,
    owner_principal_id,scheduled_at,created_by_principal_id,consultation_type,compass_kind
  ) VALUES(p_id,p_lead,p_client,p_family,p_subject,p_domain,'SCHEDULED',p_owner,
    p_scheduled,auth.current_principal_id(),p_type,p_compass);
  PERFORM crm.record_consultation_event(p_event,p_id,'CREATED',NULL,'SCHEDULED',NULL,p_owner,
    'CONSULTATION_CREATED');
  RETURN audit.record_write_decision('CREATE','CRM_CONSULTATION',p_id,true,'CONSULTATION_CREATED');
EXCEPTION WHEN unique_violation THEN
  RETURN audit.record_write_decision('CREATE','CRM_CONSULTATION',p_id,false,'CONSULTATION_EXISTS');
END
$fn$;

CREATE FUNCTION crm.transition_consultation(
  p_id uuid,p_next text,p_result text,p_next_action text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.consultations%ROWTYPE; ok boolean;
BEGIN
  SELECT * INTO v FROM crm.consultations WHERE consultation_id=p_id FOR UPDATE;
  ok:=FOUND AND crm.is_crm_service() AND core.is_uuid_v7(p_event)
    AND ((v.family_id IS NULL AND auth.current_family_id() IS NULL) OR v.family_id=auth.current_family_id())
    AND ((v.status='SCHEDULED' AND p_next IN ('IN_PROGRESS','CANCELLED','NO_SHOW'))
      OR (v.status='IN_PROGRESS' AND p_next IN ('COMPLETED','CANCELLED')))
    AND (p_next<>'COMPLETED' OR (p_result ~ '^[A-Z0-9_]{2,80}$'
      AND p_next_action ~ '^[A-Z0-9_]{2,80}$'));
  IF ok IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','CRM_CONSULTATION',p_id,false,
      'CRM_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.consultations SET status=p_next,result_code=CASE WHEN p_next='COMPLETED' THEN p_result END,
    next_action_code=CASE WHEN p_next='COMPLETED' THEN p_next_action END,
    started_at=CASE WHEN p_next='IN_PROGRESS' THEN clock_timestamp() ELSE started_at END,
    completed_at=CASE WHEN p_next='COMPLETED' THEN clock_timestamp() ELSE completed_at END,
    updated_at=clock_timestamp() WHERE consultation_id=p_id;
  PERFORM crm.record_consultation_event(p_event,p_id,'STATUS_CHANGED',v.status,p_next,
    NULL,NULL,'CONSULTATION_STATUS_CHANGED');
  RETURN audit.record_write_decision('TRANSITION','CRM_CONSULTATION',p_id,true,
    'CONSULTATION_STATUS_CHANGED');
END
$fn$;

CREATE FUNCTION crm.create_managed_deal(
  p_id uuid,p_assignment uuid,p_client uuid,p_family uuid,p_primary_lead uuid,
  p_consultation uuid,p_name text,p_domain text,p_amount numeric,p_currency text,
  p_expected_close timestamptz,p_owner uuid,p_referral uuid,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
BEGIN
  IF (crm.is_crm_service() AND auth.current_family_id()=p_family
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_assignment) AND core.is_uuid_v7(p_event)
      AND EXISTS(SELECT 1 FROM crm.clients WHERE client_id=p_client AND family_id=p_family
        AND lifecycle_status IN ('ACTIVE','PAUSED'))
      AND (p_primary_lead IS NULL OR EXISTS(SELECT 1 FROM crm.lead_identity_links
        WHERE lead_id=p_primary_lead AND target_kind='CLIENT' AND client_id=p_client AND status='VERIFIED'))
      AND (p_consultation IS NULL OR EXISTS(SELECT 1 FROM crm.consultations
        WHERE consultation_id=p_consultation AND family_id=p_family
          AND (client_id=p_client OR lead_id=p_primary_lead)))
      AND (p_referral IS NULL OR EXISTS(SELECT 1 FROM crm.referrals r
        WHERE r.referral_id=p_referral AND r.status='CONFIRMED'
          AND (r.client_id=p_client OR r.lead_id=p_primary_lead)))
      AND length(btrim(p_name)) BETWEEN 1 AND 300
      AND p_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE','MULTI_DOMAIN')
      AND p_amount>=0 AND p_currency ~ '^[A-Z]{3}$'
      AND EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_owner AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_DEAL',p_id,false,
      'CRM_CLIENT_CONSULTATION_REFERRAL_OWNER_OR_INPUT_DENIED');
  END IF;
  INSERT INTO crm.deals(
    deal_id,client_id,family_id,primary_lead_id,deal_name,business_domain,deal_status,
    estimated_amount,currency,expected_close_at,owner_principal_id,partner_referral_id,
    created_by_principal_id,updated_by_principal_id
  ) VALUES(p_id,p_client,p_family,p_primary_lead,btrim(p_name),p_domain,'OPEN',p_amount,
    p_currency,p_expected_close,p_owner,p_referral,auth.current_principal_id(),auth.current_principal_id());
  INSERT INTO crm.sales_assignments(
    sales_assignment_id,deal_id,principal_id,assignment_role,status,valid_from,
    assigned_by_principal_id,reason_code
  ) VALUES(p_assignment,p_id,p_owner,'PRIMARY_OWNER','ACTIVE',clock_timestamp(),
    auth.current_principal_id(),'INITIAL_DEAL_OWNER');
  PERFORM crm.record_deal_event(p_event,p_id,'CREATED',NULL,'OPEN',NULL,p_amount,NULL,p_owner,
    p_domain,'MANAGED_DEAL_CREATED');
  RETURN audit.record_write_decision('CREATE','CRM_DEAL',p_id,true,'MANAGED_DEAL_CREATED');
EXCEPTION WHEN unique_violation THEN
  RETURN audit.record_write_decision('CREATE','CRM_DEAL',p_id,false,'DEAL_OR_ASSIGNMENT_EXISTS');
END
$fn$;

CREATE FUNCTION crm.transition_deal(p_id uuid,p_next text,p_reason text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.deals%ROWTYPE; ok boolean;
BEGIN
  SELECT * INTO v FROM crm.deals WHERE deal_id=p_id FOR UPDATE;
  ok:=FOUND AND crm.is_crm_service() AND auth.current_family_id()=v.family_id
    AND core.is_uuid_v7(p_event) AND p_reason ~ '^[A-Z0-9_]{2,80}$'
    AND ((v.deal_status='OPEN' AND p_next IN ('QUALIFIED','CANCELLED'))
      OR (v.deal_status='QUALIFIED' AND p_next IN ('PROPOSAL','LOST','CANCELLED'))
      OR (v.deal_status='PROPOSAL' AND p_next IN ('NEGOTIATION','LOST','CANCELLED'))
      OR (v.deal_status='NEGOTIATION' AND p_next IN ('WON','LOST','CANCELLED')));
  IF ok IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','CRM_DEAL',p_id,false,'CRM_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.deals SET deal_status=p_next,
    won_lost_reason_code=CASE WHEN p_next IN ('WON','LOST') THEN p_reason END,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE deal_id=p_id;
  PERFORM crm.record_deal_event(p_event,p_id,'STATUS_CHANGED',v.deal_status,p_next,NULL,NULL,
    NULL,NULL,NULL,p_reason);
  RETURN audit.record_write_decision('TRANSITION','CRM_DEAL',p_id,true,'DEAL_STATUS_CHANGED');
END
$fn$;

CREATE FUNCTION crm.revise_deal_amount(
  p_id uuid,p_amount numeric,p_currency text,p_reason text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.deals%ROWTYPE;
BEGIN
  SELECT * INTO v FROM crm.deals WHERE deal_id=p_id FOR UPDATE;
  IF (FOUND AND crm.is_crm_service() AND auth.current_family_id()=v.family_id
      AND v.deal_status NOT IN ('WON','LOST','CANCELLED') AND core.is_uuid_v7(p_event)
      AND p_amount>=0 AND p_currency ~ '^[A-Z]{3}$' AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN
    RETURN audit.record_write_decision('UPDATE','CRM_DEAL_AMOUNT',p_id,false,
      'CRM_SCOPE_STATE_OR_INPUT_DENIED');
  END IF;
  UPDATE crm.deals SET estimated_amount=p_amount,currency=p_currency,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp() WHERE deal_id=p_id;
  PERFORM crm.record_deal_event(p_event,p_id,'AMOUNT_CHANGED',NULL,NULL,v.estimated_amount,p_amount,
    NULL,NULL,NULL,p_reason);
  RETURN audit.record_write_decision('UPDATE','CRM_DEAL_AMOUNT',p_id,true,'DEAL_AMOUNT_CHANGED');
END
$fn$;

CREATE FUNCTION crm.add_managed_deal_item(
  p_id uuid,p_deal uuid,p_code text,p_name text,p_domain text,p_compass text,
  p_quantity numeric,p_amount numeric,p_currency text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.deals%ROWTYPE;
BEGIN
  SELECT * INTO v FROM crm.deals WHERE deal_id=p_deal FOR UPDATE;
  IF (FOUND AND crm.is_crm_service() AND auth.current_family_id()=v.family_id
      AND v.deal_status NOT IN ('WON','LOST','CANCELLED')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$' AND length(btrim(p_name)) BETWEEN 1 AND 300
      AND p_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE')
      AND (p_compass IS NULL OR p_compass IN ('CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS'))
      AND p_quantity>0 AND p_amount>=0 AND p_currency ~ '^[A-Z]{3}$') IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_DEAL_ITEM',p_id,false,'CRM_DEAL_SCOPE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO crm.deal_items(
    deal_item_id,deal_id,item_code,item_name,business_domain,compass_kind,quantity,
    estimated_amount,currency,created_by_principal_id
  ) VALUES(p_id,p_deal,p_code,btrim(p_name),p_domain,p_compass,p_quantity,p_amount,
    p_currency,auth.current_principal_id());
  PERFORM crm.record_deal_event(p_event,p_deal,'SCOPE_ADDED',NULL,NULL,NULL,NULL,NULL,NULL,
    p_code,'DEAL_SCOPE_ADDED');
  RETURN audit.record_write_decision('CREATE','CRM_DEAL_ITEM',p_id,true,'DEAL_SCOPE_ADDED');
EXCEPTION WHEN unique_violation THEN
  RETURN audit.record_write_decision('CREATE','CRM_DEAL_ITEM',p_id,false,'DEAL_ITEM_EXISTS');
END
$fn$;

CREATE FUNCTION crm.add_deal_project_candidate(
  p_id uuid,p_deal uuid,p_code text,p_domain text,p_compass text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.deals%ROWTYPE;
BEGIN
  SELECT * INTO v FROM crm.deals WHERE deal_id=p_deal FOR UPDATE;
  IF (FOUND AND crm.is_crm_service() AND auth.current_family_id()=v.family_id
      AND v.deal_status NOT IN ('WON','LOST','CANCELLED')
      AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'
      AND p_domain IN ('EDUCATION','IDENTITY','WEALTH','HEALTH','GLOBAL_LIVING','HERITAGE')
      AND (p_compass IS NULL OR p_compass IN ('CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_DEAL_PROJECT_CANDIDATE',p_id,false,
      'CRM_DEAL_SCOPE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO crm.deal_project_candidates(
    deal_project_candidate_id,deal_id,candidate_code,business_domain,compass_kind,status,
    created_by_principal_id
  ) VALUES(p_id,p_deal,p_code,p_domain,p_compass,'PROPOSED',auth.current_principal_id());
  PERFORM crm.record_deal_event(p_event,p_deal,'PROJECT_CANDIDATE_ADDED',NULL,NULL,NULL,NULL,
    NULL,NULL,p_code,'PROJECT_CANDIDATE_ADDED');
  RETURN audit.record_write_decision('CREATE','CRM_DEAL_PROJECT_CANDIDATE',p_id,true,
    'PROJECT_CANDIDATE_ADDED');
END
$fn$;

CREATE FUNCTION crm.transfer_deal_owner(
  p_deal uuid,p_assignment uuid,p_new_owner uuid,p_reason text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.deals%ROWTYPE; a crm.sales_assignments%ROWTYPE;
BEGIN
  SELECT * INTO v FROM crm.deals WHERE deal_id=p_deal FOR UPDATE;
  SELECT * INTO a FROM crm.sales_assignments WHERE deal_id=p_deal
    AND assignment_role='PRIMARY_OWNER' AND status='ACTIVE' AND valid_until IS NULL FOR UPDATE;
  IF (v.deal_id IS NOT NULL AND a.sales_assignment_id IS NOT NULL
      AND crm.is_crm_service() AND auth.current_family_id()=v.family_id
      AND v.deal_status NOT IN ('WON','LOST','CANCELLED')
      AND core.is_uuid_v7(p_assignment) AND core.is_uuid_v7(p_event)
      AND p_new_owner<>v.owner_principal_id AND p_reason ~ '^[A-Z0-9_]{2,80}$'
      AND EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_new_owner AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSFER','CRM_DEAL_OWNER',p_deal,false,
      'CRM_SCOPE_STATE_OR_NEW_OWNER_DENIED');
  END IF;
  UPDATE crm.sales_assignments SET status='REVOKED',valid_until=clock_timestamp(),
    revoked_by_principal_id=auth.current_principal_id() WHERE sales_assignment_id=a.sales_assignment_id;
  INSERT INTO crm.sales_assignments(
    sales_assignment_id,deal_id,principal_id,assignment_role,status,valid_from,
    assigned_by_principal_id,reason_code
  ) VALUES(p_assignment,p_deal,p_new_owner,'PRIMARY_OWNER','ACTIVE',clock_timestamp(),
    auth.current_principal_id(),p_reason);
  UPDATE crm.deals SET owner_principal_id=p_new_owner,updated_by_principal_id=auth.current_principal_id(),
    updated_at=clock_timestamp() WHERE deal_id=p_deal;
  PERFORM crm.record_deal_event(p_event,p_deal,'OWNER_CHANGED',NULL,NULL,NULL,NULL,
    v.owner_principal_id,p_new_owner,NULL,p_reason);
  RETURN audit.record_write_decision('TRANSFER','CRM_DEAL_OWNER',p_deal,true,'DEAL_OWNER_TRANSFERRED');
END
$fn$;

CREATE FUNCTION crm.schedule_follow_up(
  p_id uuid,p_kind text,p_lead uuid,p_deal uuid,p_client uuid,p_title text,
  p_assignee uuid,p_due timestamptz
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE f uuid;
BEGIN
  SELECT CASE p_kind WHEN 'LEAD' THEN (SELECT family_id FROM crm.leads WHERE lead_id=p_lead)
    WHEN 'DEAL' THEN (SELECT family_id FROM crm.deals WHERE deal_id=p_deal)
    WHEN 'CLIENT' THEN (SELECT family_id FROM crm.clients WHERE client_id=p_client) END INTO f;
  IF (crm.is_crm_service() AND core.is_uuid_v7(p_id)
      AND ((f IS NULL AND auth.current_family_id() IS NULL) OR f=auth.current_family_id())
      AND p_kind IN ('LEAD','DEAL','CLIENT') AND length(btrim(p_title)) BETWEEN 1 AND 300
      AND EXISTS(SELECT 1 FROM auth.principals WHERE principal_id=p_assignee AND status='ACTIVE')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_FOLLOW_UP',p_id,false,'CRM_SCOPE_OR_INPUT_DENIED');
  END IF;
  INSERT INTO crm.follow_ups(
    follow_up_id,target_kind,lead_id,deal_id,client_id,title,status,assigned_principal_id,
    created_by_principal_id,due_at
  ) VALUES(p_id,p_kind,p_lead,p_deal,p_client,btrim(p_title),'PENDING',p_assignee,
    auth.current_principal_id(),p_due);
  RETURN audit.record_write_decision('CREATE','CRM_FOLLOW_UP',p_id,true,'FOLLOW_UP_CREATED');
END
$fn$;

CREATE FUNCTION crm.transition_follow_up(p_id uuid,p_next text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit AS $fn$
DECLARE v crm.follow_ups%ROWTYPE; f uuid;
BEGIN
  SELECT * INTO v FROM crm.follow_ups WHERE follow_up_id=p_id FOR UPDATE;
  SELECT CASE v.target_kind WHEN 'LEAD' THEN (SELECT family_id FROM crm.leads WHERE lead_id=v.lead_id)
    WHEN 'DEAL' THEN (SELECT family_id FROM crm.deals WHERE deal_id=v.deal_id)
    WHEN 'CLIENT' THEN (SELECT family_id FROM crm.clients WHERE client_id=v.client_id) END INTO f;
  IF (FOUND AND v.status='PENDING' AND p_next IN ('COMPLETED','CANCELLED')
      AND crm.is_crm_service() AND ((f IS NULL AND auth.current_family_id() IS NULL)
        OR f=auth.current_family_id())) IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','CRM_FOLLOW_UP',p_id,false,'CRM_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.follow_ups SET status=p_next,
    completed_at=CASE WHEN p_next='COMPLETED' THEN clock_timestamp() END,
    updated_at=clock_timestamp() WHERE follow_up_id=p_id;
  RETURN audit.record_write_decision('TRANSITION','CRM_FOLLOW_UP',p_id,true,'FOLLOW_UP_STATUS_CHANGED');
END
$fn$;

ALTER TABLE crm.consultation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.consultation_events FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.deal_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.deal_events FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.sales_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.sales_assignments FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.deal_project_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.deal_project_candidates FORCE ROW LEVEL SECURITY;

CREATE POLICY consultation_events_crm_scope ON crm.consultation_events FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.consultations c
    WHERE c.consultation_id=consultation_events.consultation_id
      AND ((c.family_id IS NULL AND auth.current_family_id() IS NULL) OR c.family_id=auth.current_family_id())))
  WITH CHECK (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.consultations c
    WHERE c.consultation_id=consultation_events.consultation_id
      AND ((c.family_id IS NULL AND auth.current_family_id() IS NULL) OR c.family_id=auth.current_family_id())));
CREATE POLICY deal_events_crm_scope ON crm.deal_events FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.deals d
    WHERE d.deal_id=deal_events.deal_id AND d.family_id=auth.current_family_id()))
  WITH CHECK (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.deals d
    WHERE d.deal_id=deal_events.deal_id AND d.family_id=auth.current_family_id()));
CREATE POLICY sales_assignments_crm_scope ON crm.sales_assignments FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.deals d
    WHERE d.deal_id=sales_assignments.deal_id AND d.family_id=auth.current_family_id()))
  WITH CHECK (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.deals d
    WHERE d.deal_id=sales_assignments.deal_id AND d.family_id=auth.current_family_id()));
CREATE POLICY deal_project_candidates_crm_scope ON crm.deal_project_candidates FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.deals d
    WHERE d.deal_id=deal_project_candidates.deal_id AND d.family_id=auth.current_family_id()))
  WITH CHECK (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.deals d
    WHERE d.deal_id=deal_project_candidates.deal_id AND d.family_id=auth.current_family_id()));

REVOKE ALL ON crm.consultation_events,crm.deal_events,crm.sales_assignments,
  crm.deal_project_candidates FROM PUBLIC,phoenix_canonical_app,
  phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE EXECUTE ON FUNCTION
  crm.create_deal(uuid,uuid,uuid,uuid,text,text,numeric,text,timestamptz,uuid,uuid),
  crm.add_deal_item(uuid,uuid,text,text,text,text,numeric,numeric,text)
FROM phoenix_canonical_app;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crm FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  crm.create_consultation(uuid,uuid,uuid,uuid,uuid,text,text,text,uuid,timestamptz,uuid),
  crm.transition_consultation(uuid,text,text,text,uuid),
  crm.create_managed_deal(uuid,uuid,uuid,uuid,uuid,uuid,text,text,numeric,text,timestamptz,uuid,uuid,uuid),
  crm.transition_deal(uuid,text,text,uuid),
  crm.revise_deal_amount(uuid,numeric,text,text,uuid),
  crm.add_managed_deal_item(uuid,uuid,text,text,text,text,numeric,numeric,text,uuid),
  crm.add_deal_project_candidate(uuid,uuid,text,text,text,uuid),
  crm.transfer_deal_owner(uuid,uuid,uuid,text,uuid),
  crm.schedule_follow_up(uuid,text,uuid,uuid,uuid,text,uuid,timestamptz),
  crm.transition_follow_up(uuid,text)
TO phoenix_canonical_app;

COMMIT;
