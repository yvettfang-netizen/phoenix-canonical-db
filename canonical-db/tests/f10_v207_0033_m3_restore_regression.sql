DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<33 THEN
    RAISE EXCEPTION 'M3 restore ledger mismatch';
  END IF;
  IF to_regclass('crm.consultation_events') IS NULL
     OR to_regclass('crm.deal_events') IS NULL
     OR to_regclass('crm.sales_assignments') IS NULL
     OR to_regclass('crm.deal_project_candidates') IS NULL THEN
    RAISE EXCEPTION 'M3 tables missing';
  END IF;
  IF (SELECT count(*) FROM crm.consultations WHERE status='COMPLETED')<>1
     OR (SELECT count(*) FROM crm.deals WHERE deal_status='WON')<>1
     OR (SELECT count(*) FROM crm.sales_assignments WHERE deal_id='018f0000-0000-7000-8000-000000033201')<>2
     OR (SELECT count(*) FROM crm.deal_events WHERE deal_id='018f0000-0000-7000-8000-000000033201')<>10
     OR (SELECT count(*) FROM crm.deal_project_candidates)<>1 THEN
    RAISE EXCEPTION 'M3 restored synthetic rows mismatch';
  END IF;
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='crm'
       AND table_name='consultations' AND column_name ~ '(questionnaire|diagnosis|medical|symptom|answer|response)') THEN
    RAISE EXCEPTION 'M3 Health raw questionnaire column present';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','crm.deal_events','SELECT')
     OR has_function_privilege('public','crm.transition_deal(uuid,text,text,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_app','crm.create_deal(uuid,uuid,uuid,uuid,text,text,numeric,text,timestamptz,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','crm.transition_deal(uuid,text,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'M3 restored ACL mismatch';
  END IF;
  IF to_regclass('finance.payments') IS NOT NULL OR to_regclass('finance.contracts') IS NOT NULL THEN
    RAISE EXCEPTION 'M3 introduced Finance authority';
  END IF;
END
$test$;
