DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>25 THEN
    RAISE EXCEPTION 'post-0025 restore ledger mismatch while checking 0022';
  END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='learning')<>14
     OR (SELECT count(*) FROM pg_policies WHERE schemaname='learning')<>14 THEN
    RAISE EXCEPTION '0022 Learning catalog mismatch';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='btree_gist') THEN
    RAISE EXCEPTION '0022 btree_gist missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='learning' AND c.relkind='r'
        AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)) THEN
    RAISE EXCEPTION '0022 Learning RLS not enabled and forced';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','learning.enrollment','SELECT')
     OR has_table_privilege('phoenix_canonical_app','learning.after_class_card','INSERT')
     OR has_table_privilege('phoenix_canonical_reader','learning.publication','SELECT') THEN
    RAISE EXCEPTION '0022 raw table privilege leaked';
  END IF;
  IF has_function_privilege('public','learning.can_read_sensitive(uuid,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','learning.read_published_card(uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0022 function ACL mismatch';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.principals WHERE principal_kind='TEACHER')
     OR NOT EXISTS (SELECT 1 FROM auth.principals WHERE principal_kind='SUPERVISOR')
     OR NOT EXISTS (SELECT 1 FROM consent.grants WHERE purpose='LEARNING_RECORD' AND data_class='LEARNING')
     OR NOT EXISTS (SELECT 1 FROM core.guardian_authorities WHERE scope='LEARNING') THEN
    RAISE EXCEPTION '0022 authorization vocabulary or synthetic rows missing';
  END IF;
  IF (SELECT count(*) FROM learning.enrollment)<>1
     OR (SELECT count(*) FROM learning.publication)<>2
     OR (SELECT count(*) FROM learning.attendance_record)<>1
     OR (SELECT count(*) FROM learning.attendance_correction)<>0 THEN
    RAISE EXCEPTION '0022 restored synthetic lifecycle mismatch';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables
      WHERE table_schema='learning' AND table_name IN ('external_entitlement_ref','askwise_session_link')) THEN
    RAISE EXCEPTION '0022 duplicated entitlement or ASKWISE table';
  END IF;
END
$test$;
