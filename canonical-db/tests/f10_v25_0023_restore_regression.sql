DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>25 THEN
    RAISE EXCEPTION 'post-0025 restore ledger mismatch while checking 0023';
  END IF;
  IF to_regprocedure('auth.issue_application_family_context_ticket(text,text,text,timestamptz,uuid)') IS NULL THEN
    RAISE EXCEPTION '0023 atomic application family context function missing';
  END IF;
  IF has_function_privilege('public',
       'auth.issue_application_family_context_ticket(text,text,text,timestamptz,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_app',
       'auth.issue_application_family_context_ticket(text,text,text,timestamptz,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_context_binder',
       'auth.issue_application_family_context_ticket(text,text,text,timestamptz,uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0023 function ACL mismatch';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM integration.legacy_id_mappings
     WHERE source_system='PHOENIX_FAMILY_OS'
       AND entity_kind='FAMILY'
       AND mapping_status='VERIFIED'
  ) THEN
    RAISE EXCEPTION '0023 synthetic VERIFIED mapping missing after restore';
  END IF;
END
$test$;
