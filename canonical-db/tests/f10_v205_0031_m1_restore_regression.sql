DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>31 THEN
    RAISE EXCEPTION 'M1 restore ledger mismatch';
  END IF;
  IF to_regclass('crm.client_parties') IS NULL
     OR to_regclass('crm.client_relationship_events') IS NULL
     OR to_regclass('crm.partner_relationships') IS NULL
     OR to_regclass('crm.partner_relationship_events') IS NULL THEN
    RAISE EXCEPTION 'M1 relationship tables missing';
  END IF;
  IF (SELECT count(*) FROM crm.client_parties)<>3
     OR (SELECT count(*) FROM crm.partner_relationships)<>3
     OR (SELECT count(*) FROM crm.partner_relationship_events)<>4 THEN
    RAISE EXCEPTION 'M1 restored synthetic rows mismatch';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','crm.client_parties','SELECT')
     OR has_table_privilege('phoenix_canonical_reader','crm.partner_relationships','SELECT')
     OR has_function_privilege('public','crm.add_client_party(uuid,uuid,text,uuid,text,timestamptz,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_app','crm.create_client(uuid,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','crm.add_client_party(uuid,uuid,text,uuid,text,timestamptz,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'M1 restored ACL mismatch';
  END IF;
END
$test$;
