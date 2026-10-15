BEGIN;

-- R-1: keep the existing partial unique indexes, but normalize expired rows
-- before a new active row reaches them. Authorization functions already check
-- their time windows, so an unswept row never authorizes access.
CREATE FUNCTION consent.normalize_grant_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, consent
AS $fn$
DECLARE v_now timestamptz := clock_timestamp();
BEGIN
  IF NEW.status = 'ACTIVE' AND NEW.expires_at <= v_now THEN
    NEW.status := 'EXPIRED';
  END IF;
  IF NEW.status = 'ACTIVE' THEN
    UPDATE consent.grants
       SET status = 'EXPIRED'
     WHERE family_id = NEW.family_id
       AND grantee_person_id = NEW.grantee_person_id
       AND subject_person_id = NEW.subject_person_id
       AND purpose = NEW.purpose
       AND data_class = NEW.data_class
       AND status = 'ACTIVE'
       AND expires_at <= clock_timestamp();
  END IF;
  RETURN NEW;
END
$fn$;
CREATE TRIGGER normalize_grant_insert BEFORE INSERT ON consent.grants
FOR EACH ROW EXECUTE FUNCTION consent.normalize_grant_insert();

CREATE OR REPLACE FUNCTION casework.protect_advisor_assignment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, casework
AS $fn$
DECLARE v_now timestamptz := clock_timestamp(); v_status text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_status := CASE WHEN NEW.revoked_at IS NOT NULL THEN 'REVOKED'
                     WHEN NEW.valid_until <= v_now THEN 'EXPIRED'
                     ELSE 'ACTIVE' END;
    IF NEW.lifecycle_status <> 'ACTIVE' AND NEW.lifecycle_status <> v_status THEN
      RAISE EXCEPTION 'ADVISOR_ASSIGNMENT_INSERT_STATUS_INVALID';
    END IF;
    IF v_status = 'ACTIVE' THEN
      UPDATE casework.advisor_assignments
         SET lifecycle_status = 'EXPIRED'
       WHERE case_id = NEW.case_id
         AND advisor_person_id = NEW.advisor_person_id
         AND lifecycle_status = 'ACTIVE'
         AND valid_until <= clock_timestamp();
    END IF;
    NEW.lifecycle_status := v_status;
    RETURN NEW;
  END IF;

  IF ROW(NEW.assignment_id, NEW.case_id, NEW.advisor_person_id, NEW.valid_from)
     IS DISTINCT FROM ROW(OLD.assignment_id, OLD.case_id, OLD.advisor_person_id, OLD.valid_from)
  THEN RAISE EXCEPTION 'ADVISOR_ASSIGNMENT_IDENTITY_IMMUTABLE'; END IF;
  IF OLD.lifecycle_status <> 'ACTIVE' AND NEW.lifecycle_status = 'ACTIVE' THEN
    RAISE EXCEPTION 'ADVISOR_ASSIGNMENT_REACTIVATION_DENIED';
  END IF;
  IF OLD.revoked_at IS NOT NULL OR OLD.lifecycle_status <> 'ACTIVE' OR OLD.valid_until <= v_now THEN
    IF ROW(NEW.assignment_id, NEW.case_id, NEW.advisor_person_id, NEW.valid_from, NEW.valid_until, NEW.revoked_at)
       IS DISTINCT FROM ROW(OLD.assignment_id, OLD.case_id, OLD.advisor_person_id, OLD.valid_from, OLD.valid_until, OLD.revoked_at)
    THEN RAISE EXCEPTION 'ADVISOR_ASSIGNMENT_HISTORY_IMMUTABLE'; END IF;
    NEW.lifecycle_status := CASE WHEN OLD.revoked_at IS NOT NULL OR OLD.lifecycle_status = 'REVOKED' THEN 'REVOKED'
                                 ELSE 'EXPIRED' END;
    RETURN NEW;
  END IF;
  v_status := CASE WHEN NEW.revoked_at IS NOT NULL THEN 'REVOKED'
                   WHEN NEW.valid_until <= v_now THEN 'EXPIRED'
                   ELSE 'ACTIVE' END;
  IF NEW.lifecycle_status <> OLD.lifecycle_status AND NEW.lifecycle_status <> v_status THEN
    RAISE EXCEPTION 'ADVISOR_ASSIGNMENT_STATUS_INVALID';
  END IF;
  NEW.lifecycle_status := v_status;
  RETURN NEW;
END
$fn$;
DROP TRIGGER protect_advisor_assignment ON casework.advisor_assignments;
CREATE TRIGGER protect_advisor_assignment BEFORE INSERT OR UPDATE ON casework.advisor_assignments
FOR EACH ROW EXECUTE FUNCTION casework.protect_advisor_assignment();

CREATE OR REPLACE FUNCTION core.protect_guardian_authority() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE v_now timestamptz := clock_timestamp(); v_status text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_status := CASE WHEN NEW.revoked_at IS NOT NULL THEN 'REVOKED'
                     WHEN NEW.valid_until <= v_now THEN 'EXPIRED'
                     ELSE 'ACTIVE' END;
    IF NEW.lifecycle_status <> 'ACTIVE' AND NEW.lifecycle_status <> v_status THEN
      RAISE EXCEPTION 'GUARDIAN_AUTHORITY_INSERT_STATUS_INVALID';
    END IF;
    IF v_status = 'ACTIVE' THEN
      UPDATE core.guardian_authorities
         SET lifecycle_status = 'EXPIRED'
       WHERE family_id = NEW.family_id
         AND guardian_person_id = NEW.guardian_person_id
         AND subject_person_id = NEW.subject_person_id
         AND scope = NEW.scope
         AND lifecycle_status = 'ACTIVE'
         AND valid_until <= clock_timestamp();
    END IF;
    NEW.lifecycle_status := v_status;
    RETURN NEW;
  END IF;

  IF ROW(NEW.authority_id, NEW.family_id, NEW.guardian_person_id, NEW.subject_person_id, NEW.scope, NEW.valid_from)
     IS DISTINCT FROM ROW(OLD.authority_id, OLD.family_id, OLD.guardian_person_id, OLD.subject_person_id, OLD.scope, OLD.valid_from)
  THEN RAISE EXCEPTION 'GUARDIAN_AUTHORITY_IDENTITY_IMMUTABLE'; END IF;
  IF OLD.lifecycle_status <> 'ACTIVE' AND NEW.lifecycle_status = 'ACTIVE' THEN
    RAISE EXCEPTION 'GUARDIAN_AUTHORITY_REACTIVATION_DENIED';
  END IF;
  IF OLD.revoked_at IS NOT NULL OR OLD.lifecycle_status <> 'ACTIVE' OR OLD.valid_until <= v_now THEN
    IF ROW(NEW.authority_id, NEW.family_id, NEW.guardian_person_id, NEW.subject_person_id,
           NEW.evidence_level, NEW.scope, NEW.valid_from, NEW.valid_until, NEW.revoked_at)
       IS DISTINCT FROM ROW(OLD.authority_id, OLD.family_id, OLD.guardian_person_id, OLD.subject_person_id,
                            OLD.evidence_level, OLD.scope, OLD.valid_from, OLD.valid_until, OLD.revoked_at)
    THEN RAISE EXCEPTION 'GUARDIAN_AUTHORITY_HISTORY_IMMUTABLE'; END IF;
    NEW.lifecycle_status := CASE WHEN OLD.revoked_at IS NOT NULL OR OLD.lifecycle_status = 'REVOKED' THEN 'REVOKED'
                                 ELSE 'EXPIRED' END;
    RETURN NEW;
  END IF;
  v_status := CASE WHEN NEW.revoked_at IS NOT NULL THEN 'REVOKED'
                   WHEN NEW.valid_until <= v_now THEN 'EXPIRED'
                   ELSE 'ACTIVE' END;
  IF NEW.lifecycle_status <> OLD.lifecycle_status AND NEW.lifecycle_status <> v_status THEN
    RAISE EXCEPTION 'GUARDIAN_AUTHORITY_STATUS_INVALID';
  END IF;
  NEW.lifecycle_status := v_status;
  RETURN NEW;
END
$fn$;
DROP TRIGGER protect_guardian_authority ON core.guardian_authorities;
CREATE TRIGGER protect_guardian_authority BEFORE INSERT OR UPDATE ON core.guardian_authorities
FOR EACH ROW EXECUTE FUNCTION core.protect_guardian_authority();

-- Existing expired rows are normalized once at migration time. The function
-- below is a restricted maintenance hook for later idle-period sweeps.
UPDATE consent.grants SET status = 'EXPIRED'
 WHERE status = 'ACTIVE' AND expires_at <= clock_timestamp();
UPDATE casework.advisor_assignments SET lifecycle_status = 'EXPIRED'
 WHERE lifecycle_status = 'ACTIVE' AND valid_until <= clock_timestamp();
UPDATE core.guardian_authorities SET lifecycle_status = 'EXPIRED'
 WHERE lifecycle_status = 'ACTIVE' AND valid_until <= clock_timestamp();

CREATE FUNCTION auth.sweep_expired_authorizations()
RETURNS TABLE(consent_rows integer, assignment_rows integer, guardian_rows integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, consent, casework, core
AS $fn$
BEGIN
  UPDATE consent.grants SET status = 'EXPIRED'
   WHERE status = 'ACTIVE' AND expires_at <= clock_timestamp();
  GET DIAGNOSTICS consent_rows = ROW_COUNT;
  UPDATE casework.advisor_assignments SET lifecycle_status = 'EXPIRED'
   WHERE lifecycle_status = 'ACTIVE' AND valid_until <= clock_timestamp();
  GET DIAGNOSTICS assignment_rows = ROW_COUNT;
  UPDATE core.guardian_authorities SET lifecycle_status = 'EXPIRED'
   WHERE lifecycle_status = 'ACTIVE' AND valid_until <= clock_timestamp();
  GET DIAGNOSTICS guardian_rows = ROW_COUNT;
  RETURN NEXT;
END
$fn$;

-- R-4: an explicit maintenance hook removes dead backend contexts and expired
-- one-use tickets. Ticket issue/redeem also run it so normal traffic cleans up.
CREATE FUNCTION auth.cleanup_ephemeral_state()
RETURNS TABLE(context_rows integer, ticket_rows integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $fn$
BEGIN
  context_rows := auth.cleanup_stale_contexts();
  DELETE FROM auth.context_exchange_tickets WHERE expires_at <= clock_timestamp();
  GET DIAGNOSTICS ticket_rows = ROW_COUNT;
  RETURN NEXT;
END
$fn$;

CREATE OR REPLACE FUNCTION auth.issue_context_ticket(
  p_principal_id uuid, p_actor_person_id uuid, p_family_id uuid, p_channel text,
  p_expires_at timestamptz, p_request_nonce uuid, p_intended_principal_id uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth, core, integration, casework
AS $fn$
DECLARE v_ticket uuid := gen_random_uuid();
BEGIN
  IF p_expires_at <= clock_timestamp() OR p_expires_at > clock_timestamp() + interval '60 seconds' THEN
    RAISE EXCEPTION 'CONTEXT_TICKET_EXPIRY_INVALID';
  END IF;
  PERFORM auth.validate_context_request(p_principal_id, p_actor_person_id, p_family_id, p_channel);
  IF NOT EXISTS (SELECT 1 FROM auth.principals WHERE principal_id = p_intended_principal_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'CONTEXT_TICKET_TARGET_INVALID';
  END IF;
  PERFORM auth.cleanup_ephemeral_state();
  INSERT INTO auth.context_exchange_tickets(ticket_id, principal_id, actor_person_id, family_id, channel, request_nonce, expires_at, intended_principal_id)
  VALUES (v_ticket, p_principal_id, p_actor_person_id, p_family_id, p_channel, p_request_nonce, p_expires_at, p_intended_principal_id);
  RETURN v_ticket;
END
$fn$;

CREATE OR REPLACE FUNCTION auth.redeem_context_ticket(
  p_ticket_id uuid, p_expected_principal_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $fn$
DECLARE v_ticket auth.context_exchange_tickets%ROWTYPE; v_backend_start timestamptz;
BEGIN
  PERFORM auth.cleanup_ephemeral_state();
  DELETE FROM auth.context_exchange_tickets
   WHERE ticket_id = p_ticket_id
     AND intended_principal_id = p_expected_principal_id
     AND expires_at > clock_timestamp()
   RETURNING * INTO v_ticket;
  IF NOT FOUND THEN RAISE EXCEPTION 'CONTEXT_TICKET_INVALID_OR_ALREADY_USED'; END IF;
  SELECT backend_start INTO v_backend_start
    FROM pg_catalog.pg_stat_activity WHERE pid = pg_backend_pid();
  IF v_backend_start IS NULL THEN RAISE EXCEPTION 'CONTEXT_BACKEND_NOT_FOUND'; END IF;
  INSERT INTO auth.session_contexts(backend_pid, backend_start, principal_id, actor_person_id, family_id, channel, request_nonce, expires_at)
  VALUES (pg_backend_pid(), v_backend_start, v_ticket.principal_id, v_ticket.actor_person_id, v_ticket.family_id, v_ticket.channel, v_ticket.request_nonce, v_ticket.expires_at)
  ON CONFLICT (backend_pid) DO UPDATE SET
    backend_start = excluded.backend_start,
    principal_id = excluded.principal_id,
    actor_person_id = excluded.actor_person_id,
    family_id = excluded.family_id,
    channel = excluded.channel,
    request_nonce = excluded.request_nonce,
    expires_at = excluded.expires_at,
    bound_at = clock_timestamp();
END
$fn$;

-- R-3: executable functions created in 0007 must not inherit PUBLIC access.
REVOKE EXECUTE ON FUNCTION core.can_read_subject_basics(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.can_read_subject_basics(uuid) TO phoenix_canonical_app, phoenix_canonical_reader;
REVOKE EXECUTE ON FUNCTION casework.protect_advisor_assignment() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION core.protect_guardian_authority() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION docs.validate_submission_target() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION consent.normalize_grant_insert() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth.sweep_expired_authorizations() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION auth.cleanup_ephemeral_state() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth.sweep_expired_authorizations() TO phoenix_canonical_migrator;
GRANT EXECUTE ON FUNCTION auth.cleanup_ephemeral_state() TO phoenix_canonical_context_binder;

COMMIT;
