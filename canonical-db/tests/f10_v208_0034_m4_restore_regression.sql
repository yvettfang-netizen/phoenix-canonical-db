DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>34 THEN
    RAISE EXCEPTION 'M4 restore ledger mismatch';
  END IF;
  IF to_regclass('service.project_subject_authorizations') IS NULL THEN
    RAISE EXCEPTION 'M4 authorization table missing';
  END IF;
  IF (SELECT count(*) FROM service.project_subject_authorizations)<>2
     OR (SELECT count(*) FROM service.project_subject_authorizations WHERE status='REVOKED')<>2
     OR (SELECT count(*) FROM service.project_subjects WHERE data_scope='HEALTH' AND status='ENDED')<>2
     OR (SELECT count(*) FROM service.project_parties WHERE status='ENDED')<2
     OR (SELECT count(*) FROM service.project_assignments WHERE status='ENDED')<3
     OR (SELECT count(*) FROM service.projects WHERE project_status='COMPLETED')<>2 THEN
    RAISE EXCEPTION 'M4 restored lifecycle rows mismatch';
  END IF;
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='service'
       AND table_name='projects' AND column_name='contract_id') THEN
    RAISE EXCEPTION 'M4 introduced Finance contract authority';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','service.project_subject_authorizations','SELECT')
     OR has_function_privilege('public','service.register_project_subject_authorization(uuid,uuid,uuid,text,uuid,text,timestamptz,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_app','service.add_project_subject(uuid,uuid,uuid,text,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','service.add_project_subject_authorized(uuid,uuid,uuid,text,uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'M4 restored ACL mismatch';
  END IF;
END
$test$;
