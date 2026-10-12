-- Disposable, synthetic PostgreSQL RLS engine check. No canonical domain objects.
BEGIN;
CREATE SCHEMA acceptance_probe;
CREATE TABLE acceptance_probe.resources (
  id integer PRIMARY KEY,
  family_scope text NOT NULL,
  advisor_scope text NOT NULL,
  partner_scope text NOT NULL,
  UNIQUE (family_scope, advisor_scope, partner_scope)
);
INSERT INTO acceptance_probe.resources VALUES
  (1, 'synthetic-family-a', 'synthetic-advisor-a', 'synthetic-partner-a'),
  (2, 'synthetic-family-b', 'synthetic-advisor-b', 'synthetic-partner-b');
ALTER TABLE acceptance_probe.resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE acceptance_probe.resources FORCE ROW LEVEL SECURITY;
CREATE POLICY scope_read ON acceptance_probe.resources FOR SELECT TO phoenix_canonical_app
  USING (
    (current_setting('probe.actor_kind', true) = 'family' AND family_scope = current_setting('probe.scope', true)) OR
    (current_setting('probe.actor_kind', true) = 'advisor' AND advisor_scope = current_setting('probe.scope', true)) OR
    (current_setting('probe.actor_kind', true) = 'partner' AND partner_scope = current_setting('probe.scope', true))
  );
GRANT USAGE ON SCHEMA acceptance_probe TO phoenix_canonical_app;
GRANT SELECT ON acceptance_probe.resources TO phoenix_canonical_app;
SET ROLE phoenix_canonical_app;
SET probe.actor_kind = 'family';
SET probe.scope = 'synthetic-family-a';
DO $test$
BEGIN
  IF (SELECT array_agg(id ORDER BY id) FROM acceptance_probe.resources) IS DISTINCT FROM ARRAY[1] THEN
    RAISE EXCEPTION 'cross-family isolation failed';
  END IF;
END
$test$;
SET probe.actor_kind = 'advisor';
SET probe.scope = 'synthetic-advisor-a';
DO $test$
BEGIN
  IF (SELECT array_agg(id ORDER BY id) FROM acceptance_probe.resources) IS DISTINCT FROM ARRAY[1] THEN
    RAISE EXCEPTION 'unassigned advisor isolation failed';
  END IF;
END
$test$;
SET probe.scope = 'synthetic-advisor-none';
DO $test$
BEGIN
  IF EXISTS (SELECT 1 FROM acceptance_probe.resources) THEN
    RAISE EXCEPTION 'unassigned advisor gained access';
  END IF;
END
$test$;
SET probe.actor_kind = 'partner';
SET probe.scope = 'synthetic-partner-a';
DO $test$
BEGIN
  IF (SELECT array_agg(id ORDER BY id) FROM acceptance_probe.resources) IS DISTINCT FROM ARRAY[1] THEN
    RAISE EXCEPTION 'partner cross-subject isolation failed';
  END IF;
END
$test$;
RESET ROLE;
ROLLBACK;
