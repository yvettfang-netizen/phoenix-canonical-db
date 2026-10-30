DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>35 THEN
    RAISE EXCEPTION 'M5 restore ledger mismatch';
  END IF;
  IF to_regclass('service.milestone_templates') IS NULL
     OR to_regclass('service.delivery_events') IS NULL THEN
    RAISE EXCEPTION 'M5 catalog missing';
  END IF;
  IF (SELECT count(*) FROM service.milestone_templates)<2
     OR (SELECT count(*) FROM service.delivery_events)<13
     OR (SELECT count(*) FROM service.task_events WHERE event_kind='TRANSFERRED')<1
     OR (SELECT count(*) FROM service.deliverables WHERE delivery_governance_version=2)<3
     OR (SELECT count(*) FROM service.deliverables WHERE status='ACCEPTED')<2
     OR (SELECT count(*) FROM service.deliverables WHERE status='WITHDRAWN')<1 THEN
    RAISE EXCEPTION 'M5 restored lifecycle rows mismatch';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM service.deliverables d
      JOIN docs.document_versions v ON v.version_id=d.document_version_id
     WHERE d.delivery_governance_version=2 AND d.document_id=v.document_id)
     OR EXISTS(SELECT 1 FROM service.deliverables
       WHERE delivery_governance_version=2 AND (document_id IS NULL OR document_version_id IS NULL)) THEN
    RAISE EXCEPTION 'M5 document-version authority mismatch';
  END IF;
  IF EXISTS(SELECT 1 FROM information_schema.columns
      WHERE table_schema='service' AND column_name ~ '(body|content|payload|blob)') THEN
    RAISE EXCEPTION 'M5 duplicated document content into Service domain';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','service.delivery_events','SELECT')
     OR has_function_privilege('public','service.review_deliverable(uuid,text,text,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_app','service.create_deliverable(uuid,uuid,uuid,uuid,text,timestamptz,uuid)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','service.create_versioned_deliverable(uuid,uuid,uuid,uuid,uuid,text,timestamptz,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'M5 restored ACL mismatch';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='service' AND c.relname='delivery_events'
       AND t.tgname='reject_delivery_event_change' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'M5 delivery event immutability trigger missing';
  END IF;
END
$test$;
