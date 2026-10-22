-- PoC only (V1.9 P5): move table and function ownership of the Canonical business schemas from the
-- bootstrap superuser to a NOLOGIN, non-superuser owner role. Runs in disposable containers only.
-- Nothing here is a migration: no historical migration file is changed and no ledger row is written.
\set ON_ERROR_STOP on
DO $owner$
DECLARE
  o text := 'phoenix_canonical_schema_owner';
  s text;
  r record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = o) THEN
    EXECUTE format('CREATE ROLE %I NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS', o);
  END IF;
  FOREACH s IN ARRAY ARRAY['auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning'] LOOP
    EXECUTE format('GRANT USAGE, CREATE ON SCHEMA %I TO %I', s, o);
  END LOOP;
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning')
              AND c.relkind IN ('r','v') LOOP
    EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', r.nspname, r.relname, o);
  END LOOP;
  FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning')
              AND p.prokind = 'f' LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO %I', r.sig, o);
  END LOOP;
  RAISE NOTICE 'PASS owner transfer applied to tables/sequences/functions in 11 Canonical schemas';
END
$owner$;

-- Finding from the first PoC run: pg_stat_activity hides a session from a role that is not the session
-- user, so auth.current_backend_start() (used by every context check) returned NULL under the owner role.
-- The minimal compensating grant is the predefined read-only stats role, inherited (the owner is NOINHERIT).
-- This also lets the owner read other sessions' query text; see DATABASE_OWNER_SECURITY_DECISION_V1.0.md.
GRANT pg_read_all_stats TO phoenix_canonical_schema_owner WITH INHERIT TRUE, SET FALSE;
