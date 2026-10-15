\set ON_ERROR_STOP on
DO $test$
DECLARE v_app_write integer; v_public_exec integer; v_bad_secdef integer;
BEGIN
  SELECT count(*) INTO v_app_write FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity')
     AND c.relkind IN ('r','p')
     AND (has_table_privilege('phoenix_canonical_app',c.oid,'INSERT')
       OR has_table_privilege('phoenix_canonical_app',c.oid,'UPDATE')
       OR has_table_privilege('phoenix_canonical_app',c.oid,'DELETE'));
  SELECT count(*) INTO v_public_exec FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity')
     AND has_function_privilege('public',p.oid,'EXECUTE');
  SELECT count(*) INTO v_bad_secdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity')
     AND p.prosecdef AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) x WHERE x LIKE 'search_path=%');
  IF v_app_write<>0 OR v_public_exec<>0 OR v_bad_secdef<>0 THEN
    RAISE EXCEPTION 'catalog failed app_write=% public_exec=% secdef_without_path=%',v_app_write,v_public_exec,v_bad_secdef;
  END IF;
  RAISE NOTICE 'PASS catalog app_write=0 public_execute=0 secdef_without_path=0';
END
$test$;

