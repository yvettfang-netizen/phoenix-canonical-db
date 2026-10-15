BEGIN READ ONLY;
SELECT 'database=' || current_database();
SELECT 'server=' || current_setting('server_version');
SELECT 'ledger=' || migration_name || '|' || sha256
  FROM canonical_migrations.applied ORDER BY migration_name;
SELECT 'table_count=' || count(*)
  FROM pg_tables
 WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity');
DO $audit$
DECLARE r record; n bigint; total bigint := 0;
BEGIN
  FOR r IN
    SELECT n.nspname, c.relname
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind IN ('r','p')
       AND n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity')
     ORDER BY n.nspname, c.relname
  LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I', r.nspname, r.relname) INTO n;
    RAISE NOTICE 'domain_rows=%.%|%', r.nspname, r.relname, n;
    total := total + n;
  END LOOP;
  RAISE NOTICE 'TOTAL_DOMAIN_ROWS=%', total;
  IF total <> 0 THEN RAISE EXCEPTION 'NONEMPTY_CANONICAL_DEVELOPMENT_DATABASE'; END IF;
END
$audit$;
SELECT 'hba=' || line_number || '|' || type || '|' || database::text || '|' || user_name::text || '|' || coalesce(address,'') || '|' || auth_method || '|' || coalesce(error,'')
  FROM pg_hba_file_rules ORDER BY line_number;
COMMIT;
