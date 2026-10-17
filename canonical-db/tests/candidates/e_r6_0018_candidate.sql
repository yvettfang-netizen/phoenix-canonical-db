-- CANDIDATE ONLY, NOT A MIGRATION (V1.9-R1, E-R6). Applied only inside disposable test containers after 0001-0017.
-- Not approved by the Founder. Frozen migrations 0001-0017 are not edited; a real fix would ship as 0018 after approval.
-- Rule: an advisor's read path closes when the case is no longer OPEN or PAUSED (same rule as 0015 and 0016).
-- Covers every advisor-reachable read that the repro found without a case-status check:
--   core.can_read_subject_basics            -> people, student_profiles, family_memberships
--   casework.is_current_advisor_for_case    -> cases_read (its only caller)
--   assignments_read (advisor clause)       -> casework.advisor_assignments
-- Does not change lifecycle_status or close_case: whether closure must also end assignments is a Founder decision (D-14).
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

COMMIT;
