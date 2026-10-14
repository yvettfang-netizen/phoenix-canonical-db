-- Phase 2B disposable database-boundary probe. The bootstrap role simulates a
-- trusted binder; no production authentication or Canonical business table is built.
BEGIN;
CREATE SCHEMA acceptance_probe;

CREATE TABLE acceptance_probe.bound_context (
  backend_pid integer PRIMARY KEY,
  actor_kind text NOT NULL CHECK (actor_kind IN ('family','advisor','partner')),
  actor_scope text NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked boolean NOT NULL DEFAULT false
);
CREATE TABLE acceptance_probe.resources (
  resource_id integer PRIMARY KEY,
  family_scope text NOT NULL,
  advisor_scope text NOT NULL,
  partner_scope text NOT NULL
);
INSERT INTO acceptance_probe.resources VALUES
  (1,'synthetic-family-a','synthetic-advisor-a','synthetic-partner-a'),
  (2,'synthetic-family-b','synthetic-advisor-b','synthetic-partner-b');

CREATE FUNCTION acceptance_probe.allowed_resource(
  p_family text, p_advisor text, p_partner text
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = pg_catalog, acceptance_probe AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM acceptance_probe.bound_context AS c
    WHERE c.backend_pid = pg_backend_pid()
      AND NOT c.revoked
      AND c.expires_at > statement_timestamp()
      AND (
        (c.actor_kind = 'family' AND c.actor_scope = p_family) OR
        (c.actor_kind = 'advisor' AND c.actor_scope = p_advisor) OR
        (c.actor_kind = 'partner' AND c.actor_scope = p_partner)
      )
  );
$fn$;
REVOKE ALL ON SCHEMA acceptance_probe FROM PUBLIC;
REVOKE ALL ON FUNCTION acceptance_probe.allowed_resource(text,text,text) FROM PUBLIC;
GRANT USAGE ON SCHEMA acceptance_probe TO phoenix_canonical_app;
GRANT EXECUTE ON FUNCTION acceptance_probe.allowed_resource(text,text,text) TO phoenix_canonical_app;
GRANT SELECT ON acceptance_probe.resources TO phoenix_canonical_app;
ALTER TABLE acceptance_probe.resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE acceptance_probe.resources FORCE ROW LEVEL SECURITY;
CREATE POLICY bound_scope_read ON acceptance_probe.resources FOR SELECT TO phoenix_canonical_app
  USING (acceptance_probe.allowed_resource(family_scope,advisor_scope,partner_scope));

SET ROLE phoenix_canonical_app;
SET probe.actor_kind = 'family';
SET probe.scope = 'synthetic-family-a';
DO $test$
BEGIN
  IF EXISTS (SELECT 1 FROM acceptance_probe.resources) THEN
    RAISE EXCEPTION 'forged caller GUC authorized an unbound session';
  END IF;
  IF has_table_privilege(current_user,'acceptance_probe.bound_context','SELECT') OR
     has_table_privilege(current_user,'acceptance_probe.bound_context','UPDATE') THEN
    RAISE EXCEPTION 'application can inspect or change trusted context';
  END IF;
END
$test$;
RESET ROLE;

-- A test-only bootstrap actor binds the current backend after an assumed external check.
INSERT INTO acceptance_probe.bound_context VALUES
  (pg_backend_pid(),'family','synthetic-family-a',clock_timestamp() + interval '1 hour',false);
SET ROLE phoenix_canonical_app;
DO $test$
BEGIN
  IF (SELECT array_agg(resource_id ORDER BY resource_id) FROM acceptance_probe.resources) IS DISTINCT FROM ARRAY[1] THEN
    RAISE EXCEPTION 'bound family did not receive exactly its own resource';
  END IF;
END
$test$;
SET probe.actor_kind = 'partner';
SET probe.scope = 'synthetic-partner-b';
DO $test$
DECLARE blocked boolean := false;
BEGIN
  IF (SELECT array_agg(resource_id ORDER BY resource_id) FROM acceptance_probe.resources) IS DISTINCT FROM ARRAY[1] THEN
    RAISE EXCEPTION 'forged partner GUC changed bound family scope';
  END IF;
  BEGIN
    UPDATE acceptance_probe.bound_context SET actor_scope = 'synthetic-family-b' WHERE backend_pid = pg_backend_pid();
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'application changed private context'; END IF;
END
$test$;
RESET ROLE;

UPDATE acceptance_probe.bound_context
   SET actor_kind = 'advisor', actor_scope = 'synthetic-advisor-none'
 WHERE backend_pid = pg_backend_pid();
SET ROLE phoenix_canonical_app;
DO $test$
BEGIN
  IF EXISTS (SELECT 1 FROM acceptance_probe.resources) THEN
    RAISE EXCEPTION 'unassigned advisor gained access';
  END IF;
END
$test$;
RESET ROLE;

UPDATE acceptance_probe.bound_context
   SET actor_kind = 'partner', actor_scope = 'synthetic-partner-b'
 WHERE backend_pid = pg_backend_pid();
SET ROLE phoenix_canonical_app;
DO $test$
BEGIN
  IF (SELECT array_agg(resource_id ORDER BY resource_id) FROM acceptance_probe.resources) IS DISTINCT FROM ARRAY[2] THEN
    RAISE EXCEPTION 'bound partner crossed subject scope';
  END IF;
END
$test$;
RESET ROLE;

UPDATE acceptance_probe.bound_context SET revoked = true WHERE backend_pid = pg_backend_pid();
SET ROLE phoenix_canonical_app;
DO $test$
BEGIN
  IF EXISTS (SELECT 1 FROM acceptance_probe.resources) THEN
    RAISE EXCEPTION 'revoked context remained effective';
  END IF;
END
$test$;
RESET ROLE;

UPDATE acceptance_probe.bound_context
   SET revoked = false, expires_at = clock_timestamp() - interval '1 second'
 WHERE backend_pid = pg_backend_pid();
SET ROLE phoenix_canonical_app;
DO $test$
BEGIN
  IF EXISTS (SELECT 1 FROM acceptance_probe.resources) THEN
    RAISE EXCEPTION 'expired context remained effective';
  END IF;
END
$test$;
RESET ROLE;
DELETE FROM acceptance_probe.bound_context WHERE backend_pid = pg_backend_pid();
SET ROLE phoenix_canonical_app;
DO $test$
BEGIN
  IF EXISTS (SELECT 1 FROM acceptance_probe.resources) THEN
    RAISE EXCEPTION 'cleared pooled backend retained prior scope';
  END IF;
END
$test$;
RESET ROLE;

INSERT INTO acceptance_probe.bound_context VALUES
  (pg_backend_pid(),'family','synthetic-family-b',clock_timestamp() + interval '1 hour',false);
SET ROLE phoenix_canonical_app;
DO $test$
BEGIN
  IF (SELECT array_agg(resource_id ORDER BY resource_id) FROM acceptance_probe.resources) IS DISTINCT FROM ARRAY[2] THEN
    RAISE EXCEPTION 'rebound backend leaked previous actor scope';
  END IF;
END
$test$;
RESET ROLE;
ROLLBACK;
