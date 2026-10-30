DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>25 THEN
    RAISE EXCEPTION 'post-0025 restore ledger mismatch while checking 0021';
  END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='operations_ref')<>2 THEN
    RAISE EXCEPTION '0021 Operations table count mismatch';
  END IF;
  IF (SELECT count(*) FROM operations_ref.entitlement_ref)<>5
     OR (SELECT count(*) FROM operations_ref.entitlement_event)<>6 THEN
    RAISE EXCEPTION '0021 synthetic reference/event restore mismatch';
  END IF;
  IF (SELECT count(*) FROM operations_ref.entitlement_ref WHERE status='ACTIVE')<>3
     OR (SELECT count(*) FROM operations_ref.entitlement_ref WHERE status='REVOKED')<>1
     OR (SELECT count(*) FROM operations_ref.entitlement_ref WHERE status='EXPIRED')<>1 THEN
    RAISE EXCEPTION '0021 lifecycle restore mismatch';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='operations_ref' AND c.relkind='r'
        AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)) THEN
    RAISE EXCEPTION '0021 RLS not enabled and forced';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','operations_ref.entitlement_ref','SELECT')
     OR has_table_privilege('phoenix_canonical_app','operations_ref.entitlement_ref','INSERT')
     OR has_table_privilege('phoenix_canonical_reader','operations_ref.entitlement_event','SELECT') THEN
    RAISE EXCEPTION '0021 raw table privilege leaked';
  END IF;
  IF has_function_privilege('public','operations_ref.register_entitlement(uuid,text,text,text,bigint,uuid,uuid,text,uuid,timestamptz,timestamptz,timestamptz)','EXECUTE')
     OR has_function_privilege('public','operations_ref.protect_entitlement_ref()','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','operations_ref.check_entitlement(uuid,uuid,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0021 function ACL mismatch';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.principals
      WHERE principal_id='018f0000-0000-7000-8000-000000002009'
        AND principal_kind='SERVICE' AND status='ACTIVE'
        AND service_label='operations_entitlement_service') THEN
    RAISE EXCEPTION '0021 Operations service principal missing';
  END IF;
END
$test$;

