BEGIN;

-- T1 / EV-1 E1-2: bounded family relationship and display-name management.
CREATE FUNCTION core.end_family_membership(p_membership_id uuid,p_valid_until timestamptz)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
DECLARE v_item core.family_memberships%ROWTYPE; v_now timestamptz := clock_timestamp();
BEGIN
  SELECT * INTO v_item FROM core.family_memberships
    WHERE membership_id=p_membership_id FOR UPDATE;
  IF (FOUND AND auth.is_internal_service()
      AND auth.current_family_id()=v_item.family_id
      AND (v_item.valid_until IS NULL OR v_item.valid_until>v_now)
      AND p_valid_until>=v_now AND p_valid_until>v_item.valid_from
      AND (v_item.valid_until IS NULL OR p_valid_until<v_item.valid_until)) IS NOT TRUE THEN
    RETURN audit.record_write_decision('END','FAMILY_MEMBERSHIP',p_membership_id,false,
      'SERVICE_FAMILY_TIME_OR_STATE_DENIED');
  END IF;
  UPDATE core.family_memberships SET valid_until=p_valid_until
    WHERE membership_id=p_membership_id;
  RETURN audit.record_write_decision('END','FAMILY_MEMBERSHIP',p_membership_id,true,
    'SERVICE_ENDED_EARLY');
END
$fn$;

CREATE FUNCTION core.rename_person(p_person_id uuid,p_display_name text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id() IS NOT NULL
      AND core.person_in_current_family(p_person_id)
      AND length(btrim(p_display_name)) BETWEEN 1 AND 200) IS NOT TRUE THEN
    RETURN audit.record_write_decision('RENAME','PERSON',p_person_id,false,
      'SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  UPDATE core.people SET display_name=p_display_name WHERE person_id=p_person_id;
  IF NOT FOUND THEN
    RETURN audit.record_write_decision('RENAME','PERSON',p_person_id,false,'PERSON_NOT_FOUND');
  END IF;
  RETURN audit.record_write_decision('RENAME','PERSON',p_person_id,true,'DISPLAY_NAME_UPDATED');
END
$fn$;

CREATE FUNCTION core.rename_family(p_family_id uuid,p_display_name text) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,audit
AS $fn$
BEGIN
  IF (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND length(btrim(p_display_name)) BETWEEN 1 AND 200) IS NOT TRUE THEN
    RETURN audit.record_write_decision('RENAME','FAMILY',p_family_id,false,
      'SERVICE_FAMILY_OR_INPUT_DENIED');
  END IF;
  UPDATE core.families SET display_name=p_display_name WHERE family_id=p_family_id;
  IF NOT FOUND THEN
    RETURN audit.record_write_decision('RENAME','FAMILY',p_family_id,false,'FAMILY_NOT_FOUND');
  END IF;
  RETURN audit.record_write_decision('RENAME','FAMILY',p_family_id,true,'DISPLAY_NAME_UPDATED');
END
$fn$;

-- T2 / EV-1 E1-4 / EV-3 E3-6: a document subject must be covered by
-- an active case assignment in addition to DOCUMENT_READ consent.
CREATE OR REPLACE FUNCTION docs.can_read_document(p_subject_person_id uuid,p_data_class text)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,consent,integration,casework
RETURN coalesce(
  consent.has_active_consent(p_subject_person_id,'DOCUMENT_READ',p_data_class)
  AND CASE auth.current_channel()
    WHEN 'FAMILY' THEN (
      auth.current_actor_person_id()=p_subject_person_id
      OR core.has_verified_guardian_authority(p_subject_person_id,
        CASE p_data_class WHEN 'EDUCATION' THEN 'EDUCATION'
          WHEN 'IDENTITY_SENSITIVE' THEN 'IDENTITY' ELSE 'GENERAL' END)
    )
    WHEN 'ADVISOR' THEN EXISTS (
      SELECT 1 FROM casework.cases c
      JOIN casework.advisor_assignments a ON a.case_id=c.case_id
      WHERE c.family_id=auth.current_family_id()
        AND c.subject_person_id=p_subject_person_id
        AND c.status IN ('OPEN','PAUSED')
        AND a.advisor_person_id=auth.current_actor_person_id()
        AND a.lifecycle_status='ACTIVE' AND a.revoked_at IS NULL
        AND a.valid_from<=clock_timestamp() AND a.valid_until>clock_timestamp()
    )
    WHEN 'PARTNER' THEN integration.has_active_channel_grant(p_subject_person_id)
    ELSE false
  END,false);

-- T3 / EV-3 E3-1: withdrawal can only be set once. The controlled API below
-- updates only withdrawn_at; this trigger prevents any later rollback/change.
CREATE FUNCTION docs.protect_document_withdrawal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,docs
AS $fn$
BEGIN
  IF OLD.withdrawn_at IS NOT NULL AND NEW.withdrawn_at IS DISTINCT FROM OLD.withdrawn_at THEN
    RAISE EXCEPTION 'DOCUMENT_WITHDRAWAL_IMMUTABLE';
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER protect_document_withdrawal BEFORE UPDATE ON docs.documents
FOR EACH ROW EXECUTE FUNCTION docs.protect_document_withdrawal();

CREATE FUNCTION docs.withdraw_document(p_document_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,core,docs,audit
AS $fn$
DECLARE v_doc docs.documents%ROWTYPE; v_scope text; v_allowed boolean;
BEGIN
  SELECT * INTO v_doc FROM docs.documents WHERE document_id=p_document_id FOR UPDATE;
  v_scope := CASE v_doc.data_class WHEN 'EDUCATION' THEN 'EDUCATION'
    WHEN 'IDENTITY_SENSITIVE' THEN 'IDENTITY' ELSE 'GENERAL' END;
  v_allowed := FOUND AND v_doc.family_id=auth.current_family_id() AND (
    (auth.current_channel()='FAMILY'
      AND core.actor_can_manage_subject(v_doc.subject_person_id,v_scope))
    OR (auth.is_internal_service() AND auth.current_family_id()=v_doc.family_id));
  IF v_allowed IS NOT TRUE THEN
    RETURN audit.record_write_decision('WITHDRAW','DOCUMENT',p_document_id,false,
      'FAMILY_AUTHORITY_OR_SERVICE_DENIED');
  END IF;
  IF v_doc.withdrawn_at IS NOT NULL THEN
    RETURN audit.record_write_decision('WITHDRAW','DOCUMENT',p_document_id,false,
      'ALREADY_WITHDRAWN');
  END IF;
  UPDATE docs.documents SET withdrawn_at=clock_timestamp() WHERE document_id=p_document_id;
  RETURN audit.record_write_decision('WITHDRAW','DOCUMENT',p_document_id,true,'DOCUMENT_WITHDRAWN');
END
$fn$;

-- T4 / EV-4 E4-3: pre-review identity cases may close without an official
-- decision. RESOLVED retains its existing official-fact requirement.
CREATE OR REPLACE FUNCTION identity.advance_case(p_identity_case_id uuid,p_next_status text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,identity,audit
AS $fn$
DECLARE v_item identity.cases%ROWTYPE; v_valid boolean; v_authorized boolean;
BEGIN
  SELECT * INTO v_item FROM identity.cases WHERE identity_case_id=p_identity_case_id FOR UPDATE;
  v_authorized := FOUND AND v_item.family_id=auth.current_family_id() AND
    CASE WHEN p_next_status='RESOLVED' THEN
      identity.can_record_official_fact(v_item.identity_case_id,v_item.subject_person_id)
    ELSE identity.can_write_case(v_item.identity_case_id,v_item.subject_person_id) END;
  IF v_authorized IS NOT TRUE THEN
    RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,false,
      'FAMILY_ADVISOR_OR_CONSENT_DENIED');
  END IF;
  v_valid := (v_item.status='DRAFT' AND p_next_status IN ('EVIDENCE_PENDING','CLOSED'))
    OR (v_item.status='EVIDENCE_PENDING' AND p_next_status IN ('UNDER_REVIEW','CLOSED'))
    OR (v_item.status='UNDER_REVIEW' AND p_next_status IN ('RESOLVED','CLOSED'));
  IF v_valid IS NOT TRUE OR (p_next_status='RESOLVED' AND NOT EXISTS (
      SELECT 1 FROM identity.external_facts f WHERE f.identity_case_id=p_identity_case_id
        AND f.fact_kind='DECISION')) THEN
    RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,false,
      'STATE_OR_DECISION_FACT_DENIED');
  END IF;
  UPDATE identity.cases SET status=p_next_status WHERE identity_case_id=p_identity_case_id;
  RETURN audit.record_write_decision('ADVANCE','IDENTITY_CASE',p_identity_case_id,true,
    'STATE_TRANSITION_ALLOWED');
END
$fn$;

REVOKE EXECUTE ON FUNCTION core.end_family_membership(uuid,timestamptz),
  core.rename_person(uuid,text),core.rename_family(uuid,text),
  docs.protect_document_withdrawal(),docs.withdraw_document(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.end_family_membership(uuid,timestamptz),
  core.rename_person(uuid,text),core.rename_family(uuid,text),
  docs.withdraw_document(uuid) TO phoenix_canonical_app;

COMMIT;
