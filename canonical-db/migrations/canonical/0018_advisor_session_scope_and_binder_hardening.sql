BEGIN;

CREATE OR REPLACE FUNCTION core.can_read_subject_basics(p_person_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, casework, integration
RETURN CASE auth.current_channel()
  WHEN 'FAMILY' THEN core.current_actor_is_family_member() AND core.person_in_current_family(p_person_id)
  WHEN 'ADVISOR' THEN EXISTS (
    SELECT 1
      FROM casework.cases c
      JOIN casework.advisor_assignments a ON a.case_id = c.case_id
     WHERE c.family_id = auth.current_family_id()
       AND c.subject_person_id = p_person_id
       AND c.status IN ('OPEN','PAUSED')
       AND a.advisor_person_id = auth.current_actor_person_id()
       AND a.valid_from <= transaction_timestamp() AND a.valid_until > transaction_timestamp()
       AND a.revoked_at IS NULL AND a.lifecycle_status = 'ACTIVE'
  )
  WHEN 'PARTNER' THEN integration.has_active_channel_grant(p_person_id)
  ELSE false
END;

CREATE OR REPLACE FUNCTION casework.is_current_advisor_for_case(p_case_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, casework
RETURN EXISTS (
  SELECT 1
    FROM casework.cases c
    JOIN casework.advisor_assignments a ON a.case_id = c.case_id
   WHERE c.case_id = p_case_id
     AND c.status IN ('OPEN','PAUSED')
     AND a.advisor_person_id = auth.current_actor_person_id()
     AND a.valid_from <= transaction_timestamp() AND a.valid_until > transaction_timestamp()
     AND a.revoked_at IS NULL AND a.lifecycle_status = 'ACTIVE'
);

DROP POLICY IF EXISTS assignments_read ON casework.advisor_assignments;
CREATE POLICY assignments_read ON casework.advisor_assignments FOR SELECT TO phoenix_canonical_app, phoenix_canonical_reader
  USING (
    EXISTS (
      SELECT 1 FROM casework.cases c
       WHERE c.case_id = advisor_assignments.case_id
         AND c.family_id = auth.current_family_id()
         AND (core.current_actor_is_family_member()
              OR (advisor_person_id = auth.current_actor_person_id() AND c.status IN ('OPEN','PAUSED')))
    )
  );

REVOKE EXECUTE ON FUNCTION auth.bind_context(uuid,uuid,uuid,text,timestamptz,uuid)
  FROM phoenix_canonical_context_binder;

COMMIT;
