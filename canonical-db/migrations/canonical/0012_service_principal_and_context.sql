BEGIN;

-- D-11: a SERVICE principal is never a natural person. Historical greenfield
-- databases have no SERVICE rows; existing non-service rows remain valid.
ALTER TABLE auth.principals ALTER COLUMN person_id DROP NOT NULL;
ALTER TABLE auth.principals ADD COLUMN service_label text;
ALTER TABLE auth.principals ADD CONSTRAINT principal_person_kind_match
  CHECK ((principal_kind = 'SERVICE') = (person_id IS NULL));
ALTER TABLE auth.principals ADD CONSTRAINT principal_service_label_match
  CHECK ((principal_kind = 'SERVICE' AND length(btrim(service_label)) BETWEEN 1 AND 200)
      OR (principal_kind <> 'SERVICE' AND service_label IS NULL));

ALTER TABLE auth.session_contexts ALTER COLUMN actor_person_id DROP NOT NULL;
ALTER TABLE auth.session_contexts ALTER COLUMN family_id DROP NOT NULL;
ALTER TABLE auth.session_contexts ADD CONSTRAINT session_actor_channel_match
  CHECK ((channel = 'INTERNAL') = (actor_person_id IS NULL));
ALTER TABLE auth.session_contexts ADD CONSTRAINT session_family_channel_match
  CHECK (channel = 'INTERNAL' OR family_id IS NOT NULL);
ALTER TABLE auth.context_exchange_tickets ALTER COLUMN actor_person_id DROP NOT NULL;
ALTER TABLE auth.context_exchange_tickets ALTER COLUMN family_id DROP NOT NULL;
ALTER TABLE auth.context_exchange_tickets ADD CONSTRAINT ticket_actor_channel_match
  CHECK ((channel = 'INTERNAL') = (actor_person_id IS NULL));
ALTER TABLE auth.context_exchange_tickets ADD CONSTRAINT ticket_family_channel_match
  CHECK (channel = 'INTERNAL' OR family_id IS NOT NULL);

-- R-20: reject a kind/channel mismatch before family, assignment or grant checks.
CREATE OR REPLACE FUNCTION auth.validate_context_request(
  p_principal_id uuid,p_actor_person_id uuid,p_family_id uuid,p_channel text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration, casework
AS $fn$
DECLARE v_principal auth.principals%ROWTYPE;
BEGIN
  IF p_channel NOT IN ('FAMILY','ADVISOR','PARTNER','INTERNAL') OR p_channel IS NULL THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_INVALID';
  END IF;
  SELECT * INTO v_principal FROM auth.principals
    WHERE principal_id=p_principal_id AND status='ACTIVE';
  IF NOT FOUND THEN RAISE EXCEPTION 'CONTEXT_PRINCIPAL_INVALID'; END IF;
  IF (v_principal.principal_kind='FAMILY' AND p_channel='FAMILY'
      OR v_principal.principal_kind='ADVISOR' AND p_channel='ADVISOR'
      OR v_principal.principal_kind='CHANNEL' AND p_channel='PARTNER'
      OR v_principal.principal_kind='SERVICE' AND p_channel='INTERNAL') IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTEXT_PRINCIPAL_CHANNEL_MISMATCH';
  END IF;
  IF p_channel='INTERNAL' THEN
    IF p_actor_person_id IS NOT NULL OR v_principal.person_id IS NOT NULL THEN
      RAISE EXCEPTION 'CONTEXT_SERVICE_ACTOR_MUST_BE_NULL';
    END IF;
    IF p_family_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM core.families WHERE family_id=p_family_id) THEN
      RAISE EXCEPTION 'CONTEXT_FAMILY_INVALID';
    END IF;
    RETURN;
  END IF;
  IF p_actor_person_id IS NULL OR p_family_id IS NULL
      OR v_principal.person_id IS DISTINCT FROM p_actor_person_id THEN
    RAISE EXCEPTION 'CONTEXT_ACTOR_OR_FAMILY_INVALID';
  END IF;
  IF p_channel='FAMILY' AND NOT EXISTS (
      SELECT 1 FROM core.family_memberships
       WHERE family_id=p_family_id AND person_id=p_actor_person_id
         AND valid_from <= clock_timestamp()
         AND (valid_until IS NULL OR valid_until > clock_timestamp())) THEN
    RAISE EXCEPTION 'CONTEXT_FAMILY_MEMBERSHIP_INVALID';
  END IF;
  IF p_channel='ADVISOR' AND NOT EXISTS (
      SELECT 1 FROM casework.cases c
      JOIN casework.advisor_assignments a ON a.case_id=c.case_id
       WHERE c.family_id=p_family_id AND a.advisor_person_id=p_actor_person_id
         AND c.status IN ('OPEN','PAUSED')
         AND a.valid_from <= clock_timestamp() AND a.valid_until > clock_timestamp()
         AND a.revoked_at IS NULL AND a.lifecycle_status='ACTIVE') THEN
    RAISE EXCEPTION 'CONTEXT_ADVISOR_ASSIGNMENT_INVALID';
  END IF;
  IF p_channel='PARTNER' AND NOT EXISTS (
      SELECT 1 FROM integration.channel_grants
       WHERE principal_id=p_principal_id AND family_id=p_family_id
         AND valid_from <= clock_timestamp() AND valid_until > clock_timestamp()
         AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'CONTEXT_CHANNEL_GRANT_INVALID';
  END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION auth.is_internal_service() RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth
RETURN coalesce(auth.write_context_is_live()
  AND auth.current_channel()='INTERNAL'
  AND auth.current_actor_person_id() IS NULL
  AND EXISTS (SELECT 1 FROM auth.principals p
    WHERE p.principal_id=auth.current_principal_id()
      AND p.principal_kind='SERVICE' AND p.person_id IS NULL
      AND p.status='ACTIVE'),false);

-- A disabled principal cannot redeem a ticket issued before disabling.
CREATE OR REPLACE FUNCTION auth.redeem_context_ticket(
  p_ticket_id uuid,p_expected_principal_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $fn$
DECLARE v_ticket auth.context_exchange_tickets%ROWTYPE; v_backend_start timestamptz;
BEGIN
  PERFORM auth.cleanup_ephemeral_state();
  DELETE FROM auth.context_exchange_tickets
   WHERE ticket_id=p_ticket_id
     AND intended_principal_id=p_expected_principal_id
     AND expires_at>clock_timestamp()
   RETURNING * INTO v_ticket;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED'; END IF;
  PERFORM auth.validate_context_request(v_ticket.principal_id,v_ticket.actor_person_id,
    v_ticket.family_id,v_ticket.channel);
  SELECT backend_start INTO v_backend_start FROM pg_catalog.pg_stat_activity
    WHERE pid=pg_backend_pid();
  IF v_backend_start IS NULL THEN RAISE EXCEPTION 'CONTEXT_BACKEND_NOT_FOUND'; END IF;
  INSERT INTO auth.session_contexts(backend_pid,backend_start,principal_id,actor_person_id,
    family_id,channel,request_nonce,expires_at)
  VALUES (pg_backend_pid(),v_backend_start,v_ticket.principal_id,v_ticket.actor_person_id,
    v_ticket.family_id,v_ticket.channel,v_ticket.request_nonce,v_ticket.expires_at)
  ON CONFLICT (backend_pid) DO UPDATE SET
    backend_start=excluded.backend_start,
    principal_id=excluded.principal_id,
    actor_person_id=excluded.actor_person_id,
    family_id=excluded.family_id,
    channel=excluded.channel,
    request_nonce=excluded.request_nonce,
    expires_at=excluded.expires_at,
    bound_at=clock_timestamp();
END
$fn$;

-- SERVICE activity retains principal attribution with no invented person.
ALTER TABLE education.application_status_events
  ADD COLUMN changed_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE identity.case_status_events
  ADD COLUMN changed_by_principal_id uuid REFERENCES auth.principals;
CREATE OR REPLACE FUNCTION education.audit_application_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, education
AS $fn$
BEGIN
  IF TG_OP='INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO education.application_status_events(application_id,from_status,to_status,
      changed_by,changed_by_principal_id)
    VALUES (NEW.application_id,CASE WHEN TG_OP='INSERT' THEN NULL ELSE OLD.status END,
      NEW.status,auth.current_actor_person_id(),auth.current_principal_id());
  END IF;
  RETURN NEW;
END
$fn$;
CREATE OR REPLACE FUNCTION identity.audit_case_status() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, identity
AS $fn$
BEGIN
  IF TG_OP='INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO identity.case_status_events(identity_case_id,from_status,to_status,
      changed_by,changed_by_principal_id)
    VALUES (NEW.identity_case_id,CASE WHEN TG_OP='INSERT' THEN NULL ELSE OLD.status END,
      NEW.status,auth.current_actor_person_id(),auth.current_principal_id());
  END IF;
  RETURN NEW;
END
$fn$;

ALTER TABLE docs.submission_manifests
  ADD COLUMN submitted_by_principal_id uuid REFERENCES auth.principals;
ALTER TABLE docs.submission_manifests DROP CONSTRAINT submission_manifests_check;
ALTER TABLE docs.submission_manifests ADD CONSTRAINT manifest_submission_attribution
  CHECK ((status='PREPARING' AND submitted_by IS NULL
          AND submitted_by_principal_id IS NULL AND submitted_at IS NULL)
      OR (status='SUBMITTED' AND confirmed_by IS NOT NULL AND submitted_at IS NOT NULL
          AND (submitted_by IS NOT NULL OR submitted_by_principal_id IS NOT NULL)));

CREATE OR REPLACE FUNCTION docs.submit_manifest(p_submission_id uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, docs, audit
AS $fn$
DECLARE v_manifest docs.submission_manifests%ROWTYPE; v_service boolean; v_advisor boolean;
BEGIN
  SELECT * INTO v_manifest FROM docs.submission_manifests WHERE submission_id=p_submission_id FOR UPDATE;
  v_service := auth.is_internal_service() AND auth.current_family_id()=v_manifest.family_id;
  v_advisor := auth.current_channel()='ADVISOR' AND
    docs.can_manage_submission_target(v_manifest.family_id,v_manifest.subject_person_id,
      v_manifest.target_kind,v_manifest.target_id);
  IF (FOUND AND v_manifest.status='PREPARING'
      AND v_manifest.confirmed_by IS NOT NULL AND v_manifest.confirmed_at IS NOT NULL
      AND (v_service OR v_advisor) AND auth.current_principal_id() IS NOT NULL
      AND auth.current_actor_person_id() IS DISTINCT FROM v_manifest.confirmed_by) IS NOT TRUE THEN
    RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,false,'CONFIRMATION_OR_SUBMITTER_DENIED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM docs.submission_items WHERE submission_id=p_submission_id)
     OR EXISTS (SELECT 1 FROM docs.submission_items i
       JOIN docs.document_versions v ON v.version_id=i.version_id
       JOIN docs.documents d ON d.document_id=v.document_id
       WHERE i.submission_id=p_submission_id AND (d.withdrawn_at IS NOT NULL
         OR d.family_id<>v_manifest.family_id OR d.subject_person_id<>v_manifest.subject_person_id
         OR (NOT v_service AND docs.can_read_document(d.subject_person_id,d.data_class) IS NOT TRUE))) THEN
    RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,false,'ITEMS_INVALID_OR_WITHDRAWN');
  END IF;
  UPDATE docs.submission_manifests SET status='SUBMITTED',
    submitted_by=auth.current_actor_person_id(),
    submitted_by_principal_id=auth.current_principal_id(),
    submitted_at=clock_timestamp()
   WHERE submission_id=p_submission_id;
  RETURN audit.record_write_decision('SUBMIT','SUBMISSION_MANIFEST',p_submission_id,true,'SUBMITTED_AFTER_CONFIRMATION');
END
$fn$;

COMMIT;
