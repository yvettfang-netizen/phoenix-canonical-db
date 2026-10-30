BEGIN;

-- Enterprise Database V2.0 / M2. Lead acquisition and attribution. No contact
-- attribute is accepted as automatic Person or Family identity evidence.
ALTER TABLE crm.leads DROP CONSTRAINT leads_lead_status_check;
ALTER TABLE crm.leads ADD CONSTRAINT leads_lead_status_check CHECK (lead_status IN (
  'NEW','CONTACTED','QUALIFYING','QUALIFIED','CONVERTED','LOST','DISQUALIFIED','MERGED'
));
ALTER TABLE crm.lead_events DROP CONSTRAINT lead_events_event_kind_check;
ALTER TABLE crm.lead_events ADD CONSTRAINT lead_events_event_kind_check CHECK (event_kind IN (
  'CREATED','STATUS_CHANGED','IDENTITY_LINKED','IDENTITY_VERIFIED','IDENTITY_REVOKED',
  'MERGED','MERGE_REVERSED','ASSIGNED','CONSULTATION','DEAL_CREATED',
  'ATTRIBUTION_RECORDED','REFERRAL_RECORDED','REFERRAL_CONFIRMED','REFERRAL_REVOKED',
  'DEDUP_CANDIDATE','DEDUP_REVIEWED'
));

CREATE TABLE crm.lead_attributions (
  lead_attribution_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(lead_attribution_id)),
  lead_id uuid NOT NULL REFERENCES crm.leads,
  attribution_kind text NOT NULL CHECK (attribution_kind IN ('FIRST_TOUCH','CONVERSION_TOUCH')),
  lead_source_id uuid NOT NULL REFERENCES crm.lead_sources,
  partner_relationship_id uuid REFERENCES crm.partner_relationships,
  campaign_id uuid REFERENCES crm.campaigns,
  compass_kind text NOT NULL CHECK (compass_kind IN (
    'CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS'
  )),
  source_system text NOT NULL CHECK (source_system ~ '^[a-z][a-z0-9_-]{1,39}$'),
  attribution_model_version text NOT NULL CHECK (
    attribution_model_version ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$'
  ),
  created_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(lead_id,attribution_kind)
);
CREATE INDEX lead_attributions_source_created_idx
  ON crm.lead_attributions(lead_source_id,created_at,lead_attribution_id);

CREATE TABLE crm.lead_duplicate_candidates (
  lead_duplicate_candidate_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(lead_duplicate_candidate_id)),
  lead_a_id uuid NOT NULL REFERENCES crm.leads,
  lead_b_id uuid NOT NULL REFERENCES crm.leads,
  evidence_sha256 text NOT NULL CHECK (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  status text NOT NULL CHECK (status IN ('PENDING','CONFIRMED','DISMISSED')),
  proposed_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  reviewed_by_principal_id uuid REFERENCES auth.principals,
  proposed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  reviewed_at timestamptz,
  CHECK (lead_a_id<lead_b_id),
  CHECK (
    (status='PENDING' AND reviewed_by_principal_id IS NULL AND reviewed_at IS NULL)
    OR (status IN ('CONFIRMED','DISMISSED') AND reviewed_by_principal_id IS NOT NULL AND reviewed_at IS NOT NULL)
  )
);
CREATE UNIQUE INDEX lead_duplicate_candidate_pending_uq
  ON crm.lead_duplicate_candidates(lead_a_id,lead_b_id) WHERE status='PENDING';

CREATE TABLE crm.lead_merge_decisions (
  lead_merge_decision_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(lead_merge_decision_id)),
  duplicate_candidate_id uuid NOT NULL REFERENCES crm.lead_duplicate_candidates,
  source_lead_id uuid NOT NULL REFERENCES crm.leads,
  target_lead_id uuid NOT NULL REFERENCES crm.leads,
  source_previous_status text NOT NULL CHECK (source_previous_status IN (
    'NEW','CONTACTED','QUALIFYING','QUALIFIED','CONVERTED','LOST','DISQUALIFIED'
  )),
  status text NOT NULL CHECK (status IN ('ACTIVE','REVERSED')),
  merged_by_principal_id uuid NOT NULL REFERENCES auth.principals,
  reversed_by_principal_id uuid REFERENCES auth.principals,
  merged_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  reversed_at timestamptz,
  CHECK (source_lead_id<>target_lead_id),
  CHECK (
    (status='ACTIVE' AND reversed_by_principal_id IS NULL AND reversed_at IS NULL)
    OR (status='REVERSED' AND reversed_by_principal_id IS NOT NULL AND reversed_at IS NOT NULL)
  )
);
CREATE UNIQUE INDEX lead_merge_one_active_source_uq
  ON crm.lead_merge_decisions(source_lead_id) WHERE status='ACTIVE';

ALTER TABLE crm.referrals
  ADD COLUMN partner_relationship_id uuid REFERENCES crm.partner_relationships,
  ADD COLUMN lead_source_id uuid REFERENCES crm.lead_sources,
  ADD CONSTRAINT referrals_partner_source_pair CHECK (
    (partner_relationship_id IS NULL)=(lead_source_id IS NULL)
  );

CREATE TABLE crm.referral_events (
  referral_event_id uuid PRIMARY KEY CHECK (core.is_uuid_v7(referral_event_id)),
  referral_id uuid NOT NULL REFERENCES crm.referrals,
  event_kind text NOT NULL CHECK (event_kind IN ('RECORDED','CONFIRMED','REVOKED')),
  from_status text,
  to_status text NOT NULL,
  reason_code text NOT NULL CHECK (reason_code ~ '^[A-Z0-9_]{2,80}$'),
  actor_principal_id uuid NOT NULL REFERENCES auth.principals,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX referral_events_referral_time_idx
  ON crm.referral_events(referral_id,occurred_at,referral_event_id);

CREATE FUNCTION crm.reject_acquisition_history_change() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,crm AS $fn$
BEGIN RAISE EXCEPTION 'CRM_ACQUISITION_HISTORY_IMMUTABLE'; END
$fn$;

CREATE FUNCTION crm.protect_duplicate_candidate() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,crm AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'LEAD_DUPLICATE_CANDIDATE_DELETE_FORBIDDEN'; END IF;
  IF OLD.status<>'PENDING' OR NEW.status NOT IN ('CONFIRMED','DISMISSED')
     OR NEW.lead_duplicate_candidate_id<>OLD.lead_duplicate_candidate_id
     OR NEW.lead_a_id<>OLD.lead_a_id OR NEW.lead_b_id<>OLD.lead_b_id
     OR NEW.evidence_sha256<>OLD.evidence_sha256
     OR NEW.proposed_by_principal_id<>OLD.proposed_by_principal_id
     OR NEW.proposed_at<>OLD.proposed_at
     OR NEW.reviewed_by_principal_id IS NULL OR NEW.reviewed_at IS NULL THEN
    RAISE EXCEPTION 'LEAD_DUPLICATE_CANDIDATE_MUTATION_FORBIDDEN';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE FUNCTION crm.protect_merge_decision() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,crm AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'LEAD_MERGE_DECISION_DELETE_FORBIDDEN'; END IF;
  IF OLD.status<>'ACTIVE' OR NEW.status<>'REVERSED'
     OR NEW.lead_merge_decision_id<>OLD.lead_merge_decision_id
     OR NEW.duplicate_candidate_id<>OLD.duplicate_candidate_id
     OR NEW.source_lead_id<>OLD.source_lead_id OR NEW.target_lead_id<>OLD.target_lead_id
     OR NEW.source_previous_status<>OLD.source_previous_status
     OR NEW.merged_by_principal_id<>OLD.merged_by_principal_id
     OR NEW.merged_at<>OLD.merged_at
     OR NEW.reversed_by_principal_id IS NULL OR NEW.reversed_at IS NULL THEN
    RAISE EXCEPTION 'LEAD_MERGE_DECISION_MUTATION_FORBIDDEN';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE TRIGGER lead_attributions_immutable
  BEFORE UPDATE OR DELETE ON crm.lead_attributions
  FOR EACH ROW EXECUTE FUNCTION crm.reject_acquisition_history_change();
CREATE TRIGGER referral_events_immutable
  BEFORE UPDATE OR DELETE ON crm.referral_events
  FOR EACH ROW EXECUTE FUNCTION crm.reject_acquisition_history_change();
CREATE TRIGGER lead_duplicate_candidates_protected
  BEFORE UPDATE OR DELETE ON crm.lead_duplicate_candidates
  FOR EACH ROW EXECUTE FUNCTION crm.protect_duplicate_candidate();
CREATE TRIGGER lead_merge_decisions_protected
  BEFORE UPDATE OR DELETE ON crm.lead_merge_decisions
  FOR EACH ROW EXECUTE FUNCTION crm.protect_merge_decision();

CREATE OR REPLACE FUNCTION crm.record_lead_event(
  p_event_id uuid,p_lead_id uuid,p_event_kind text,p_from text,p_to text,p_reason text
) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm
AS $fn$
BEGIN
  IF (crm.is_crm_service() AND core.is_uuid_v7(p_event_id)
      AND p_event_kind IN ('CREATED','STATUS_CHANGED','IDENTITY_LINKED','IDENTITY_VERIFIED',
        'IDENTITY_REVOKED','MERGED','MERGE_REVERSED','ASSIGNED','CONSULTATION','DEAL_CREATED',
        'ATTRIBUTION_RECORDED','REFERRAL_RECORDED','REFERRAL_CONFIRMED','REFERRAL_REVOKED',
        'DEDUP_CANDIDATE','DEDUP_REVIEWED')
      AND p_reason ~ '^[A-Z0-9_]{2,80}$') IS NOT TRUE THEN
    RAISE EXCEPTION 'CRM_EVENT_CONTEXT_OR_INPUT_DENIED';
  END IF;
  INSERT INTO crm.lead_events(lead_event_id,lead_id,event_kind,from_status,to_status,
    reason_code,actor_principal_id)
  VALUES(p_event_id,p_lead_id,p_event_kind,p_from,p_to,p_reason,auth.current_principal_id());
END
$fn$;

CREATE FUNCTION crm.create_lead(
  p_id uuid,p_source uuid,p_contact_person uuid,p_family uuid,p_assignee uuid,
  p_compass text,p_model_version text,p_event_id uuid,p_attribution_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v crm.lead_sources%ROWTYPE;
BEGIN
  SELECT * INTO v FROM crm.lead_sources WHERE lead_source_id=p_source AND status='ACTIVE';
  IF (FOUND AND crm.is_crm_service() AND core.is_uuid_v7(p_id)
      AND core.is_uuid_v7(p_event_id) AND core.is_uuid_v7(p_attribution_id)
      AND p_compass IN ('CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS')
      AND p_model_version ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$'
      AND ((p_family IS NULL AND auth.current_family_id() IS NULL)
        OR (p_family IS NOT NULL AND auth.current_family_id()=p_family
          AND EXISTS(SELECT 1 FROM core.families WHERE family_id=p_family)))
      AND (p_contact_person IS NULL OR EXISTS(SELECT 1 FROM core.people WHERE person_id=p_contact_person))
      AND (p_contact_person IS NULL OR p_family IS NULL OR EXISTS(SELECT 1 FROM core.family_memberships
        WHERE family_id=p_family AND person_id=p_contact_person AND valid_from<=clock_timestamp()
          AND (valid_until IS NULL OR valid_until>clock_timestamp())))
      AND (p_assignee IS NULL OR EXISTS(SELECT 1 FROM auth.principals
        WHERE principal_id=p_assignee AND status='ACTIVE'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_LEAD',p_id,false,
      'CRM_SCOPE_ATTRIBUTION_IDENTITY_OR_INPUT_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.leads WHERE lead_id=p_id) THEN
    RETURN audit.record_write_decision('CREATE','CRM_LEAD',p_id,false,'LEAD_ID_ALREADY_EXISTS');
  END IF;
  INSERT INTO crm.leads(lead_id,lead_source_id,campaign_id,partner_organization_id,
    contact_person_id,family_id,lead_status,qualification_status,assigned_principal_id,
    created_by_principal_id,updated_by_principal_id)
  VALUES(p_id,p_source,v.campaign_id,v.partner_organization_id,p_contact_person,p_family,
    'NEW','UNVERIFIED',p_assignee,auth.current_principal_id(),auth.current_principal_id());
  INSERT INTO crm.lead_attributions(
    lead_attribution_id,lead_id,attribution_kind,lead_source_id,campaign_id,
    compass_kind,source_system,attribution_model_version,created_by_principal_id
  ) VALUES(p_attribution_id,p_id,'FIRST_TOUCH',p_source,v.campaign_id,p_compass,
    v.source_system,p_model_version,auth.current_principal_id());
  PERFORM crm.record_lead_event(p_event_id,p_id,'CREATED',NULL,'NEW','LEAD_WITH_FIRST_TOUCH_CREATED');
  RETURN audit.record_write_decision('CREATE','CRM_LEAD',p_id,true,'UNVERIFIED_LEAD_WITH_FIRST_TOUCH_CREATED');
END
$fn$;

CREATE FUNCTION crm.transition_lead(p_lead uuid,p_next text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v crm.leads%ROWTYPE; ok boolean;
BEGIN
  SELECT * INTO v FROM crm.leads WHERE lead_id=p_lead FOR UPDATE;
  ok:=FOUND AND crm.is_crm_service() AND core.is_uuid_v7(p_event)
    AND ((v.family_id IS NULL AND auth.current_family_id() IS NULL) OR v.family_id=auth.current_family_id())
    AND ((v.lead_status='NEW' AND p_next IN ('CONTACTED','DISQUALIFIED'))
      OR (v.lead_status='CONTACTED' AND p_next IN ('QUALIFIED','LOST','DISQUALIFIED'))
      OR (v.lead_status='QUALIFYING' AND p_next IN ('QUALIFIED','LOST','DISQUALIFIED'))
      OR (v.lead_status='QUALIFIED' AND p_next IN ('CONVERTED','LOST','DISQUALIFIED')));
  IF ok IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','CRM_LEAD',p_lead,false,
      'CRM_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.leads SET lead_status=p_next,
    qualification_status=CASE WHEN p_next='QUALIFIED' THEN 'QUALIFIED'
      WHEN p_next='DISQUALIFIED' THEN 'UNQUALIFIED' ELSE qualification_status END,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE lead_id=p_lead;
  PERFORM crm.record_lead_event(p_event,p_lead,'STATUS_CHANGED',v.lead_status,p_next,
    'CONTROLLED_LEAD_STATUS_CHANGED');
  RETURN audit.record_write_decision('TRANSITION','CRM_LEAD',p_lead,true,
    'CONTROLLED_LEAD_STATUS_CHANGED');
END
$fn$;

CREATE FUNCTION crm.record_conversion_attribution(
  p_id uuid,p_lead uuid,p_source uuid,p_partner_relationship uuid,
  p_compass text,p_model text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE l crm.leads%ROWTYPE; s crm.lead_sources%ROWTYPE;
BEGIN
  SELECT * INTO l FROM crm.leads WHERE lead_id=p_lead FOR UPDATE;
  SELECT * INTO s FROM crm.lead_sources WHERE lead_source_id=p_source AND status='ACTIVE';
  IF (l.lead_id IS NOT NULL AND FOUND AND l.lead_status IN ('QUALIFIED','CONVERTED')
      AND crm.is_crm_service() AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND ((l.family_id IS NULL AND auth.current_family_id() IS NULL) OR l.family_id=auth.current_family_id())
      AND p_compass IN ('CHILD_COMPASS','EDUCATION_COMPASS','FAMILY_COMPASS','HEALTH_COMPASS')
      AND p_model ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$'
      AND (p_partner_relationship IS NULL OR EXISTS(SELECT 1 FROM crm.partner_relationships
        WHERE partner_relationship_id=p_partner_relationship AND status='ACTIVE'
          AND (valid_until IS NULL OR valid_until>clock_timestamp()) AND lead_source_id=p_source))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('ATTRIBUTION','CRM_LEAD',p_lead,false,
      'CRM_SCOPE_STATE_SOURCE_OR_PARTNER_DENIED');
  END IF;
  IF EXISTS(SELECT 1 FROM crm.lead_attributions
      WHERE lead_id=p_lead AND attribution_kind='CONVERSION_TOUCH') THEN
    RETURN audit.record_write_decision('ATTRIBUTION','CRM_LEAD',p_lead,false,
      'CONVERSION_TOUCH_ALREADY_RECORDED');
  END IF;
  INSERT INTO crm.lead_attributions(
    lead_attribution_id,lead_id,attribution_kind,lead_source_id,partner_relationship_id,
    campaign_id,compass_kind,source_system,attribution_model_version,created_by_principal_id
  ) VALUES(p_id,p_lead,'CONVERSION_TOUCH',p_source,p_partner_relationship,s.campaign_id,
    p_compass,s.source_system,p_model,auth.current_principal_id());
  PERFORM crm.record_lead_event(p_event,p_lead,'ATTRIBUTION_RECORDED',NULL,'CONVERSION_TOUCH',
    'CONVERSION_TOUCH_RECORDED');
  RETURN audit.record_write_decision('ATTRIBUTION','CRM_LEAD',p_lead,true,
    'CONVERSION_TOUCH_RECORDED');
END
$fn$;

CREATE FUNCTION crm.propose_lead_duplicate(
  p_id uuid,p_lead_1 uuid,p_lead_2 uuid,p_evidence text,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE a uuid:=least(p_lead_1,p_lead_2); b uuid:=greatest(p_lead_1,p_lead_2); fa uuid; fb uuid;
BEGIN
  SELECT family_id INTO fa FROM crm.leads WHERE lead_id=a;
  SELECT family_id INTO fb FROM crm.leads WHERE lead_id=b;
  IF (a<>b AND crm.is_crm_service() AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p_evidence ~ '^[0-9a-f]{64}$' AND fa IS NOT DISTINCT FROM fb
      AND ((fa IS NULL AND auth.current_family_id() IS NULL) OR fa=auth.current_family_id())
      AND EXISTS(SELECT 1 FROM crm.leads WHERE lead_id=a AND lead_status<>'MERGED')
      AND EXISTS(SELECT 1 FROM crm.leads WHERE lead_id=b AND lead_status<>'MERGED')) IS NOT TRUE THEN
    RETURN audit.record_write_decision('PROPOSE','CRM_LEAD_DUPLICATE',p_id,false,
      'CRM_SCOPE_STATE_OR_EVIDENCE_DENIED');
  END IF;
  INSERT INTO crm.lead_duplicate_candidates(
    lead_duplicate_candidate_id,lead_a_id,lead_b_id,evidence_sha256,status,proposed_by_principal_id
  ) VALUES(p_id,a,b,p_evidence,'PENDING',auth.current_principal_id());
  PERFORM crm.record_lead_event(p_event,a,'DEDUP_CANDIDATE',NULL,'PENDING','MANUAL_DUPLICATE_CANDIDATE');
  RETURN audit.record_write_decision('PROPOSE','CRM_LEAD_DUPLICATE',p_id,true,
    'MANUAL_DUPLICATE_CANDIDATE');
EXCEPTION WHEN unique_violation THEN
  RETURN audit.record_write_decision('PROPOSE','CRM_LEAD_DUPLICATE',p_id,false,
    'PENDING_DUPLICATE_CANDIDATE_EXISTS');
END
$fn$;

CREATE FUNCTION crm.review_lead_duplicate(p_id uuid,p_decision text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v crm.lead_duplicate_candidates%ROWTYPE; f uuid;
BEGIN
  SELECT * INTO v FROM crm.lead_duplicate_candidates WHERE lead_duplicate_candidate_id=p_id FOR UPDATE;
  SELECT family_id INTO f FROM crm.leads WHERE lead_id=v.lead_a_id;
  IF (FOUND AND v.status='PENDING' AND crm.is_crm_service()
      AND auth.current_principal_id()<>v.proposed_by_principal_id
      AND p_decision IN ('CONFIRMED','DISMISSED') AND core.is_uuid_v7(p_event)
      AND ((f IS NULL AND auth.current_family_id() IS NULL) OR f=auth.current_family_id())) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVIEW','CRM_LEAD_DUPLICATE',p_id,false,
      'DISTINCT_REVIEWER_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.lead_duplicate_candidates SET status=p_decision,
    reviewed_by_principal_id=auth.current_principal_id(),reviewed_at=clock_timestamp()
   WHERE lead_duplicate_candidate_id=p_id;
  PERFORM crm.record_lead_event(p_event,v.lead_a_id,'DEDUP_REVIEWED','PENDING',p_decision,
    'MANUAL_DUPLICATE_REVIEWED');
  RETURN audit.record_write_decision('REVIEW','CRM_LEAD_DUPLICATE',p_id,true,
    'MANUAL_DUPLICATE_REVIEWED');
END
$fn$;

CREATE FUNCTION crm.merge_lead(
  p_merge_id uuid,p_source uuid,p_target uuid,p_candidate uuid,p_event_id uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE s crm.leads%ROWTYPE; t crm.leads%ROWTYPE; c crm.lead_duplicate_candidates%ROWTYPE; f uuid;
BEGIN
  IF p_source=p_target THEN
    RETURN audit.record_write_decision('MERGE','CRM_LEAD',p_source,false,'SELF_MERGE_DENIED');
  END IF;
  SELECT * INTO s FROM crm.leads WHERE lead_id=p_source FOR UPDATE;
  SELECT * INTO t FROM crm.leads WHERE lead_id=p_target FOR UPDATE;
  SELECT * INTO c FROM crm.lead_duplicate_candidates WHERE lead_duplicate_candidate_id=p_candidate;
  f:=coalesce(s.family_id,t.family_id);
  IF (s.lead_id IS NOT NULL AND t.lead_id IS NOT NULL AND c.status='CONFIRMED'
      AND c.lead_a_id=least(p_source,p_target) AND c.lead_b_id=greatest(p_source,p_target)
      AND s.lead_status<>'MERGED' AND t.lead_status<>'MERGED' AND crm.is_crm_service()
      AND core.is_uuid_v7(p_merge_id) AND core.is_uuid_v7(p_event_id)
      AND (s.family_id IS NULL OR t.family_id IS NULL OR s.family_id=t.family_id)
      AND ((f IS NULL AND auth.current_family_id() IS NULL) OR f=auth.current_family_id())) IS NOT TRUE THEN
    RETURN audit.record_write_decision('MERGE','CRM_LEAD',p_source,false,
      'CONFIRMED_CANDIDATE_SCOPE_OR_STATE_DENIED');
  END IF;
  INSERT INTO crm.lead_merge_decisions(
    lead_merge_decision_id,duplicate_candidate_id,source_lead_id,target_lead_id,
    source_previous_status,status,merged_by_principal_id
  ) VALUES(p_merge_id,p_candidate,p_source,p_target,s.lead_status,'ACTIVE',auth.current_principal_id());
  UPDATE crm.leads SET lead_status='MERGED',merged_into_lead_id=p_target,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE lead_id=p_source;
  PERFORM crm.record_lead_event(p_event_id,p_source,'MERGED',s.lead_status,'MERGED','MANUAL_AUDITED_LEAD_MERGE');
  RETURN audit.record_write_decision('MERGE','CRM_LEAD',p_source,true,'MANUAL_AUDITED_LEAD_MERGE');
END
$fn$;

CREATE FUNCTION crm.reverse_lead_merge(p_merge uuid,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE v crm.lead_merge_decisions%ROWTYPE; l crm.leads%ROWTYPE;
BEGIN
  SELECT * INTO v FROM crm.lead_merge_decisions WHERE lead_merge_decision_id=p_merge FOR UPDATE;
  SELECT * INTO l FROM crm.leads WHERE lead_id=v.source_lead_id FOR UPDATE;
  IF (v.status='ACTIVE' AND l.lead_status='MERGED' AND l.merged_into_lead_id=v.target_lead_id
      AND crm.is_crm_service() AND core.is_uuid_v7(p_event)
      AND ((l.family_id IS NULL AND auth.current_family_id() IS NULL) OR l.family_id=auth.current_family_id())) IS NOT TRUE THEN
    RETURN audit.record_write_decision('REVERSE','CRM_LEAD_MERGE',p_merge,false,
      'CRM_SCOPE_OR_ACTIVE_MERGE_DENIED');
  END IF;
  UPDATE crm.lead_merge_decisions SET status='REVERSED',
    reversed_by_principal_id=auth.current_principal_id(),reversed_at=clock_timestamp()
   WHERE lead_merge_decision_id=p_merge;
  UPDATE crm.leads SET lead_status=v.source_previous_status,merged_into_lead_id=NULL,
    updated_by_principal_id=auth.current_principal_id(),updated_at=clock_timestamp()
   WHERE lead_id=v.source_lead_id;
  PERFORM crm.record_lead_event(p_event,v.source_lead_id,'MERGE_REVERSED','MERGED',
    v.source_previous_status,'MANUAL_LEAD_MERGE_REVERSED');
  RETURN audit.record_write_decision('REVERSE','CRM_LEAD_MERGE',p_merge,true,
    'MANUAL_LEAD_MERGE_REVERSED');
END
$fn$;

CREATE FUNCTION crm.record_referral(
  p_id uuid,p_lead uuid,p_partner_relationship uuid,p_event uuid
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE l crm.leads%ROWTYPE; p crm.partner_relationships%ROWTYPE;
BEGIN
  SELECT * INTO l FROM crm.leads WHERE lead_id=p_lead FOR UPDATE;
  SELECT * INTO p FROM crm.partner_relationships
   WHERE partner_relationship_id=p_partner_relationship AND status='ACTIVE'
     AND (valid_until IS NULL OR valid_until>clock_timestamp());
  IF (l.lead_id IS NOT NULL AND p.partner_relationship_id IS NOT NULL
      AND crm.is_crm_service() AND core.is_uuid_v7(p_id) AND core.is_uuid_v7(p_event)
      AND p.lead_source_id IS NOT NULL
      AND ((l.family_id IS NULL AND auth.current_family_id() IS NULL) OR l.family_id=auth.current_family_id())) IS NOT TRUE THEN
    RETURN audit.record_write_decision('CREATE','CRM_REFERRAL',p_id,false,
      'CRM_SCOPE_LEAD_OR_PARTNER_DENIED');
  END IF;
  INSERT INTO crm.referrals(
    referral_id,lead_id,referrer_person_id,referrer_organization_id,status,
    created_by_principal_id,partner_relationship_id,lead_source_id
  ) VALUES(p_id,p_lead,p.partner_person_id,p.partner_organization_id,'RECORDED',
    auth.current_principal_id(),p_partner_relationship,p.lead_source_id);
  INSERT INTO crm.referral_events(referral_event_id,referral_id,event_kind,to_status,
    reason_code,actor_principal_id)
  VALUES(p_event,p_id,'RECORDED','RECORDED','REFERRAL_RECORDED',auth.current_principal_id());
  PERFORM crm.record_lead_event(p_event,p_lead,'REFERRAL_RECORDED',NULL,'RECORDED','REFERRAL_RECORDED');
  RETURN audit.record_write_decision('CREATE','CRM_REFERRAL',p_id,true,'REFERRAL_RECORDED');
END
$fn$;

CREATE FUNCTION crm.transition_referral(p_id uuid,p_next text,p_event uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,crm,audit
AS $fn$
DECLARE r crm.referrals%ROWTYPE; l crm.leads%ROWTYPE;
BEGIN
  SELECT * INTO r FROM crm.referrals WHERE referral_id=p_id FOR UPDATE;
  SELECT * INTO l FROM crm.leads WHERE lead_id=r.lead_id;
  IF (r.referral_id IS NOT NULL AND crm.is_crm_service() AND core.is_uuid_v7(p_event)
      AND ((l.family_id IS NULL AND auth.current_family_id() IS NULL) OR l.family_id=auth.current_family_id())
      AND ((r.status='RECORDED' AND p_next IN ('CONFIRMED','REVOKED'))
        OR (r.status='CONFIRMED' AND p_next='REVOKED'))) IS NOT TRUE THEN
    RETURN audit.record_write_decision('TRANSITION','CRM_REFERRAL',p_id,false,
      'CRM_SCOPE_OR_STATE_DENIED');
  END IF;
  UPDATE crm.referrals SET status=p_next,
    revoked_at=CASE WHEN p_next='REVOKED' THEN clock_timestamp() END WHERE referral_id=p_id;
  INSERT INTO crm.referral_events(referral_event_id,referral_id,event_kind,from_status,to_status,
    reason_code,actor_principal_id)
  VALUES(p_event,p_id,p_next,r.status,p_next,'REFERRAL_'||p_next,auth.current_principal_id());
  PERFORM crm.record_lead_event(p_event,r.lead_id,'REFERRAL_'||p_next,r.status,p_next,
    'REFERRAL_'||p_next);
  RETURN audit.record_write_decision('TRANSITION','CRM_REFERRAL',p_id,true,'REFERRAL_'||p_next);
END
$fn$;

ALTER TABLE crm.lead_attributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_attributions FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_duplicate_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_duplicate_candidates FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_merge_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.lead_merge_decisions FORCE ROW LEVEL SECURITY;
ALTER TABLE crm.referral_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.referral_events FORCE ROW LEVEL SECURITY;

CREATE POLICY lead_attributions_crm_scope ON crm.lead_attributions FOR ALL TO phoenix_canonical_app
  USING (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.leads l
    WHERE l.lead_id=lead_attributions.lead_id
      AND ((l.family_id IS NULL AND auth.current_family_id() IS NULL) OR l.family_id=auth.current_family_id())))
  WITH CHECK (crm.is_crm_service() AND EXISTS(SELECT 1 FROM crm.leads l
    WHERE l.lead_id=lead_attributions.lead_id
      AND ((l.family_id IS NULL AND auth.current_family_id() IS NULL) OR l.family_id=auth.current_family_id())));
CREATE POLICY lead_duplicate_candidates_crm_service ON crm.lead_duplicate_candidates
  FOR ALL TO phoenix_canonical_app USING (crm.is_crm_service()) WITH CHECK (crm.is_crm_service());
CREATE POLICY lead_merge_decisions_crm_service ON crm.lead_merge_decisions
  FOR ALL TO phoenix_canonical_app USING (crm.is_crm_service()) WITH CHECK (crm.is_crm_service());
CREATE POLICY referral_events_crm_service ON crm.referral_events
  FOR ALL TO phoenix_canonical_app USING (crm.is_crm_service()) WITH CHECK (crm.is_crm_service());

REVOKE ALL ON crm.lead_attributions,crm.lead_duplicate_candidates,
  crm.lead_merge_decisions,crm.referral_events
  FROM PUBLIC,phoenix_canonical_app,phoenix_canonical_reader,phoenix_canonical_context_binder;
REVOKE EXECUTE ON FUNCTION crm.create_lead(uuid,uuid,uuid,uuid,uuid,uuid),
  crm.merge_lead(uuid,uuid,uuid) FROM phoenix_canonical_app;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crm FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  crm.create_lead(uuid,uuid,uuid,uuid,uuid,text,text,uuid,uuid),
  crm.transition_lead(uuid,text,uuid),
  crm.record_conversion_attribution(uuid,uuid,uuid,uuid,text,text,uuid),
  crm.propose_lead_duplicate(uuid,uuid,uuid,text,uuid),
  crm.review_lead_duplicate(uuid,text,uuid),
  crm.merge_lead(uuid,uuid,uuid,uuid,uuid),
  crm.reverse_lead_merge(uuid,uuid),
  crm.record_referral(uuid,uuid,uuid,uuid),
  crm.transition_referral(uuid,text,uuid)
TO phoenix_canonical_app;

COMMIT;
