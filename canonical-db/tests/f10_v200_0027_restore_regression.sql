DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<29 THEN RAISE EXCEPTION 'post-0029 ledger missing while checking 0027 CRM'; END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='crm')<>12
     OR (SELECT count(*) FROM pg_policies WHERE schemaname='crm')<>12 THEN
    RAISE EXCEPTION '0027 CRM catalog mismatch';
  END IF;
  IF (SELECT count(*) FROM crm.campaigns)<>1 OR (SELECT count(*) FROM crm.lead_sources)<>1
     OR (SELECT count(*) FROM crm.leads)<>2 OR (SELECT count(*) FROM crm.lead_identity_links)<>2
     OR (SELECT count(*) FROM crm.deals)<>1 OR (SELECT count(*) FROM crm.deal_items)<>3 THEN
    RAISE EXCEPTION '0027 restored CRM rows mismatch';
  END IF;
  IF (SELECT count(*) FROM crm.leads WHERE lead_status='MERGED')<>1
     OR (SELECT count(*) FROM crm.lead_identity_links WHERE status='VERIFIED')<>1
     OR (SELECT count(*) FROM crm.lead_identity_links WHERE status='REVOKED')<>1 THEN
    RAISE EXCEPTION '0027 restored merge/link lifecycle mismatch';
  END IF;
  IF (SELECT count(DISTINCT compass_kind) FROM crm.deal_items)<>3 THEN
    RAISE EXCEPTION '0027 restored Compass attribution mismatch';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','crm.leads','SELECT')
     OR has_table_privilege('phoenix_canonical_app','crm.deals','INSERT')
     OR has_table_privilege('phoenix_canonical_reader','crm.leads','SELECT')
     OR has_function_privilege('public','crm.create_lead(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','crm.create_lead(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0027 CRM ACL mismatch';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='crm'
    AND table_name='deals' AND column_name='estimated_amount'
    AND (data_type<>'numeric' OR numeric_precision<>18 OR numeric_scale<>2)) THEN
    RAISE EXCEPTION '0027 deal amount is not numeric(18,2)';
  END IF;
END
$test$;

