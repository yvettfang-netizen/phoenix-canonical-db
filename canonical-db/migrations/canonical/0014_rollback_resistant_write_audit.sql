BEGIN;

-- D-9: a transaction can roll back its database audit row, but cannot retract
-- a PostgreSQL LOG record. A correlation UUID makes exact reconciliation
-- possible without names, document contents or credentials in the log.
ALTER TABLE audit.access_events ADD COLUMN attempt_id uuid;
CREATE UNIQUE INDEX access_events_attempt_id_unique ON audit.access_events(attempt_id)
  WHERE attempt_id IS NOT NULL;

CREATE OR REPLACE FUNCTION audit.record_write_decision(
  p_action text,p_resource_kind text,p_resource_id uuid,
  p_allowed boolean,p_reason_code text
) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,auth,audit
AS $fn$
DECLARE v_attempt uuid := gen_random_uuid();
        v_at timestamptz := clock_timestamp();
        v_principal uuid := auth.current_principal_id();
        v_decision text := CASE WHEN p_allowed IS TRUE THEN 'ALLOW' ELSE 'DENY' END;
BEGIN
  RAISE LOG 'PHOENIX_AUDIT attempt_id=% action=% resource_kind=% resource_id=% decision=% reason=% principal_id=% backend_pid=% occurred_at=%',
    v_attempt,p_action,p_resource_kind,coalesce(p_resource_id::text,'NULL'),
    v_decision,p_reason_code,coalesce(v_principal::text,'NULL'),pg_backend_pid(),v_at;
  INSERT INTO audit.access_events(attempt_id,occurred_at,backend_pid,principal_id,
    actor_person_id,family_id,action,resource_kind,resource_id,decision,reason_code)
  VALUES(v_attempt,v_at,pg_backend_pid(),v_principal,
    auth.current_actor_person_id(),auth.current_family_id(),
    p_action,p_resource_kind,p_resource_id,v_decision,p_reason_code);
  RETURN p_allowed IS TRUE;
END
$fn$;
REVOKE EXECUTE ON FUNCTION audit.record_write_decision(text,text,uuid,boolean,text) FROM PUBLIC;

COMMIT;
