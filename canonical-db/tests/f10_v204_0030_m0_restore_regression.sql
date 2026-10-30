DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>30 THEN
    RAISE EXCEPTION 'M0 restore ledger mismatch';
  END IF;
  IF to_regclass('core.organization_identifiers') IS NULL
     OR to_regclass('core.organization_relationships') IS NULL
     OR to_regclass('core.organization_name_history') IS NULL
     OR to_regclass('core.organization_events') IS NULL THEN
    RAISE EXCEPTION 'M0 Organization governance tables missing';
  END IF;
  IF (SELECT count(*) FROM integration.public_ids WHERE entity_kind='ORGANIZATION')<>2
     OR (SELECT count(*) FROM core.organization_identifiers)<>2
     OR (SELECT count(*) FROM core.organization_relationships)<>2 THEN
    RAISE EXCEPTION 'M0 restored synthetic rows mismatch';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','core.organization_identifiers','SELECT')
     OR has_table_privilege('phoenix_canonical_reader','core.organization_relationships','SELECT')
     OR has_function_privilege('public','core.rename_organization(uuid,uuid,text,text,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','core.rename_organization(uuid,uuid,text,text,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_app','core.transition_organization(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'M0 restored ACL mismatch';
  END IF;
END
$test$;
