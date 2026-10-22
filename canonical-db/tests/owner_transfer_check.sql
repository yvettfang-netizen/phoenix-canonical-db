-- PoC assertions after owner_transfer.sql (bootstrap session).
\set ON_ERROR_STOP on
DO $check$
DECLARE
  o text := 'phoenix_canonical_schema_owner';
  n_tables int; n_bad_tables int; n_funcs int; n_bad_funcs int; n_super_owned int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE pg_get_userbyid(c.relowner) <> o)
    INTO n_tables, n_bad_tables
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning')
     AND c.relkind IN ('r','v','S');
  SELECT count(*), count(*) FILTER (WHERE pg_get_userbyid(p.proowner) <> o)
    INTO n_funcs, n_bad_funcs
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning')
     AND p.prokind = 'f';
  SELECT count(*) INTO n_super_owned FROM pg_roles WHERE rolname = o AND (rolsuper OR rolcanlogin OR rolbypassrls);
  IF n_bad_tables <> 0 THEN RAISE EXCEPTION 'FAIL %: tables not owned by owner role', n_bad_tables; END IF;
  IF n_bad_funcs <> 0 THEN RAISE EXCEPTION 'FAIL %: functions not owned by owner role', n_bad_funcs; END IF;
  IF n_super_owned <> 0 THEN RAISE EXCEPTION 'FAIL owner role is superuser, login or bypassrls'; END IF;
  RAISE NOTICE 'PASS owner model: % relations and % functions owned by %, owner is NOSUPERUSER NOLOGIN NOBYPASSRLS',
    n_tables, n_funcs, o;
END
$check$;

DO $stats$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_auth_members m
                   JOIN pg_roles r ON r.oid = m.roleid JOIN pg_roles mb ON mb.oid = m.member
                  WHERE r.rolname = 'pg_read_all_stats' AND mb.rolname = 'phoenix_canonical_schema_owner'
                    AND m.inherit_option) THEN
    RAISE EXCEPTION 'FAIL owner lacks inherited pg_read_all_stats (needed for backend_start visibility)';
  END IF;
  RAISE NOTICE 'PASS owner inherits pg_read_all_stats (backend_start visibility preserved)';
END
$stats$;
