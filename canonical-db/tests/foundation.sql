DO $test$
DECLARE
  schema_name text;
BEGIN
  FOREACH schema_name IN ARRAY ARRAY['core','consent','audit','integration','docs','casework','canonical_migrations'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = schema_name) THEN
      RAISE EXCEPTION 'missing schema: %', schema_name;
    END IF;
  END LOOP;
  IF has_schema_privilege('phoenix_canonical_app','core','CREATE') THEN
    RAISE EXCEPTION 'application role can create tables';
  END IF;
  IF has_schema_privilege('phoenix_canonical_reader','docs','CREATE') THEN
    RAISE EXCEPTION 'reader role can create tables';
  END IF;
  IF has_schema_privilege('phoenix_canonical_app','canonical_migrations','USAGE') THEN
    RAISE EXCEPTION 'application role can inspect migration ledger';
  END IF;
  IF NOT has_table_privilege('phoenix_canonical_migrator','canonical_migrations.applied','INSERT') THEN
    RAISE EXCEPTION 'migration role cannot register a migration';
  END IF;
  IF (SELECT count(*) FROM canonical_migrations.applied) <> 1 THEN
    RAISE EXCEPTION 'migration ledger is not repeat safe';
  END IF;
END
$test$;
