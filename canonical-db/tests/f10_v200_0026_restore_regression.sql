DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>26 THEN
    RAISE EXCEPTION 'post-0026 restore ledger mismatch';
  END IF;
  IF to_regclass('core.organizations') IS NULL OR to_regclass('crm.clients') IS NULL THEN
    RAISE EXCEPTION '0026 Enterprise Core tables missing';
  END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='crm')<>1
     OR (SELECT count(*) FROM pg_policies WHERE schemaname='crm')<>1 THEN
    RAISE EXCEPTION '0026 CRM catalog mismatch';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='core.family_memberships'::regclass
       AND conname='family_memberships_no_overlapping_relationship'
       AND contype='x'
  ) OR EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='core.family_memberships'::regclass
       AND conname='family_memberships_family_id_person_id_key'
  ) THEN
    RAISE EXCEPTION '0026 family relationship compatibility constraint mismatch';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','crm.clients','SELECT')
     OR has_table_privilege('phoenix_canonical_app','crm.clients','INSERT')
     OR has_table_privilege('phoenix_canonical_reader','core.organizations','SELECT')
     OR has_table_privilege('phoenix_canonical_context_binder','crm.clients','SELECT')
     OR has_function_privilege('public','crm.create_client(uuid,uuid,text)','EXECUTE')
     OR NOT has_function_privilege('phoenix_canonical_app','crm.create_client(uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION '0026 Enterprise Core ACL mismatch';
  END IF;
  IF EXISTS (
    SELECT family_id FROM crm.clients
     WHERE lifecycle_status IN ('ACTIVE','PAUSED') AND relationship_ended_at IS NULL
     GROUP BY family_id HAVING count(*)>1
  ) THEN
    RAISE EXCEPTION '0026 duplicate current Client relationship restored';
  END IF;
  IF (SELECT count(*) FROM core.organizations)<>1
     OR (SELECT count(*) FROM crm.clients)<>2
     OR (SELECT count(*) FROM crm.clients WHERE lifecycle_status='ACTIVE')<>1
     OR (SELECT count(*) FROM crm.clients WHERE lifecycle_status='ENDED')<>1 THEN
    RAISE EXCEPTION '0026 restored synthetic Organization/Client rows mismatch';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='core' AND table_name='organizations'
       AND column_name='registration_reference'
  ) THEN
    RAISE EXCEPTION '0026 plaintext registration reference column found';
  END IF;
END
$test$;

