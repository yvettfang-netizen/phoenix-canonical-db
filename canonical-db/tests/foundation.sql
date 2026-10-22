DO $test$
DECLARE
  schema_name text;
BEGIN
  FOREACH schema_name IN ARRAY ARRAY['auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning','canonical_migrations'] LOOP
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
  IF has_schema_privilege('phoenix_canonical_app','education','CREATE') OR has_schema_privilege('phoenix_canonical_reader','identity','CREATE') THEN
    RAISE EXCEPTION 'application or reader role can create domain tables';
  END IF;
  IF NOT has_schema_privilege('phoenix_canonical_migrator','education','CREATE') OR NOT has_schema_privilege('phoenix_canonical_migrator','identity','CREATE') THEN
    RAISE EXCEPTION 'migration role cannot create in Phase 2A domains';
  END IF;
  IF has_schema_privilege('phoenix_canonical_app','canonical_migrations','USAGE') THEN
    RAISE EXCEPTION 'application role can inspect migration ledger';
  END IF;
  IF NOT has_table_privilege('phoenix_canonical_migrator','canonical_migrations.applied','INSERT') THEN
    RAISE EXCEPTION 'migration role cannot register a migration';
  END IF;
  IF (SELECT count(*) FROM canonical_migrations.applied) < 8 THEN
    RAISE EXCEPTION 'migration ledger is not repeat safe';
  END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning')) <> 50 THEN
    RAISE EXCEPTION 'unexpected Canonical business table count';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning')) <> 41 THEN
    RAISE EXCEPTION 'unexpected Canonical RLS policy count';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_context_binder' AND NOT rolcanlogin AND NOT rolsuper) THEN
    RAISE EXCEPTION 'trusted context binder role missing or unsafe';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','auth.session_contexts','SELECT') OR
     has_function_privilege('phoenix_canonical_app','auth.bind_context(uuid,uuid,uuid,text,timestamptz,uuid)','EXECUTE') OR
     has_function_privilege('phoenix_canonical_app','auth.issue_context_ticket(uuid,uuid,uuid,text,timestamptz,uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'application role can forge trusted context';
  END IF;
  IF NOT has_function_privilege('phoenix_canonical_app','auth.redeem_context_ticket(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'application role cannot redeem trusted context ticket';
  END IF;
  IF has_function_privilege('phoenix_canonical_app','audit.record_access_event(text,text,uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'application role can forge audit events';
  END IF;
END
$test$;
