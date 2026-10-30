DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<32 THEN
    RAISE EXCEPTION 'M2 restore ledger mismatch';
  END IF;
  IF to_regclass('crm.lead_attributions') IS NULL
     OR to_regclass('crm.lead_duplicate_candidates') IS NULL
     OR to_regclass('crm.lead_merge_decisions') IS NULL
     OR to_regclass('crm.referral_events') IS NULL THEN
    RAISE EXCEPTION 'M2 acquisition tables missing';
  END IF;
  IF (SELECT count(*) FROM crm.lead_attributions)<>5
     OR (SELECT count(*) FROM crm.lead_merge_decisions)<>2
     OR (SELECT count(*) FROM crm.referral_events)<>3
     OR (SELECT count(*) FROM crm.referrals WHERE status='REVOKED')<>1 THEN
    RAISE EXCEPTION 'M2 restored synthetic rows mismatch';
  END IF;
  IF (SELECT count(DISTINCT compass_kind) FROM crm.lead_attributions
       WHERE attribution_kind='FIRST_TOUCH')<>4 THEN
    RAISE EXCEPTION 'M2 restored four-Compass attribution mismatch';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','crm.lead_attributions','SELECT')
     OR has_table_privilege('phoenix_canonical_reader','crm.referral_events','SELECT')
     OR has_function_privilege('public','crm.transition_lead(uuid,text,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_app','crm.create_lead(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','crm.transition_lead(uuid,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'M2 restored ACL mismatch';
  END IF;
END
$test$;
