DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>29 THEN
    RAISE EXCEPTION 'post-0029 ledger mismatch';
  END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='service')<>10
     OR (SELECT count(*) FROM pg_policies WHERE schemaname='service')<>10 THEN
    RAISE EXCEPTION '0028 Service catalog mismatch';
  END IF;
  IF (SELECT count(*) FROM service.projects)<>2
     OR (SELECT count(*) FROM service.project_subjects)<>2
     OR (SELECT count(*) FROM service.project_domains)<>2
     OR (SELECT count(*) FROM service.project_assignments)<>1
     OR (SELECT count(*) FROM service.project_parties)<>1
     OR (SELECT count(*) FROM service.project_milestones)<>1
     OR (SELECT count(*) FROM service.deliverables)<>1
     OR (SELECT count(*) FROM service.tasks)<>1 THEN
    RAISE EXCEPTION '0028 restored Service rows mismatch';
  END IF;
  IF (SELECT task_status FROM service.tasks)<> 'COMPLETED'
     OR (SELECT count(*) FROM service.project_milestones WHERE status='ACHIEVED')<>1
     OR (SELECT count(*) FROM service.deliverables WHERE status='ACCEPTED' AND delivered_at IS NOT NULL)<>1
     OR (SELECT count(*) FROM service.task_events)<>5
     OR (SELECT count(*) FROM service.project_events)<>18 THEN
    RAISE EXCEPTION '0028 restored lifecycle or immutable event rows mismatch';
  END IF;
  IF (SELECT count(*) FROM service.projects WHERE family_id='018f0000-0000-7000-8000-000000000001')<>2
     OR (SELECT count(DISTINCT business_domain) FROM service.project_domains)<>2
     OR EXISTS(SELECT 1 FROM service.project_subjects WHERE access_status<>'REFERENCE_ONLY') THEN
    RAISE EXCEPTION '0028 family/project/subject boundary mismatch';
  END IF;
  IF EXISTS(SELECT 1 FROM information_schema.columns
     WHERE table_schema='service' AND table_name='projects' AND column_name='contract_id') THEN
    RAISE EXCEPTION '0028 invented a Finance contract authority';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class r ON r.oid=c.conrelid JOIN pg_namespace n ON n.oid=r.relnamespace
    JOIN pg_class f ON f.oid=c.confrelid JOIN pg_namespace fn ON fn.oid=f.relnamespace
     WHERE n.nspname='service' AND fn.nspname IN ('casework','learning')
  ) THEN
    RAISE EXCEPTION '0028 duplicates or couples Casework/Learning authority';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','service.projects','SELECT')
     OR has_table_privilege('phoenix_canonical_app','service.tasks','INSERT')
     OR has_table_privilege('phoenix_canonical_reader','service.tasks','SELECT')
     OR has_function_privilege('public','service.create_project(uuid,uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','service.create_project(uuid,uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0028 Service ACL mismatch';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='service' AND c.relname='task_events'
      AND t.tgname='reject_task_event_change' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION '0028 task event immutability trigger missing';
  END IF;
END
$test$;

