DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied)<>25 THEN
    RAISE EXCEPTION 'post-0025 restore ledger mismatch while checking 0024';
  END IF;
  IF to_regprocedure('integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)') IS NULL
     OR to_regprocedure('integration.verify_family_mapping(uuid,uuid)') IS NULL
     OR to_regprocedure('integration.revoke_family_mapping(uuid,uuid)') IS NULL
     OR to_regprocedure('integration.supersede_family_mapping(uuid,uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION '0024 family mapping management functions missing';
  END IF;
  IF NOT has_function_privilege('phoenix_canonical_app',
       'integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_context_binder',
       'integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)','EXECUTE')
     OR has_function_privilege('phoenix_canonical_reader',
       'integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)','EXECUTE')
     OR has_function_privilege('public',
       'integration.propose_family_mapping(uuid,text,text,text,uuid,text,text,text,text,text,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0024 function ACL mismatch';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','integration.legacy_id_mappings','INSERT,UPDATE,DELETE')
     OR has_table_privilege('phoenix_canonical_context_binder','integration.legacy_id_mappings','INSERT,UPDATE,DELETE')
     OR has_table_privilege('phoenix_canonical_reader','integration.legacy_id_mappings','INSERT,UPDATE,DELETE')
     OR has_table_privilege('public','integration.legacy_id_mappings','INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION '0024 direct table DML grant found';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='integration'
       AND p.proname IN ('propose_family_mapping','verify_family_mapping',
                         'revoke_family_mapping','supersede_family_mapping')
       AND position('auth.is_internal_service()' in pg_get_functiondef(p.oid))
           >= position('pg_advisory_xact_lock' in pg_get_functiondef(p.oid))
  ) THEN
    RAISE EXCEPTION '0025 authorization must precede serialization lock';
  END IF;
  IF (SELECT count(*) FROM integration.legacy_id_mappings
       WHERE managed_lifecycle_version='FM_V1' AND mapping_status='REVOKED')<>1
     OR (SELECT count(*) FROM integration.legacy_id_mappings
       WHERE managed_lifecycle_version='FM_V1' AND mapping_status='SUPERSEDED')<>1
     OR (SELECT count(*) FROM integration.legacy_id_mappings
       WHERE managed_lifecycle_version='FM_V1' AND mapping_status='VERIFIED')<>1 THEN
    RAISE EXCEPTION '0024 restored lifecycle rows mismatch';
  END IF;
  IF EXISTS (
    SELECT 1 FROM integration.legacy_id_mappings
     WHERE managed_lifecycle_version='FM_V1'
       AND (proposed_by_principal_id IS NULL
         OR application_ownership_evidence_sha256 !~ '^[0-9a-f]{64}$'
         OR canonical_membership_evidence_sha256 !~ '^[0-9a-f]{64}$'
         OR founder_approval_evidence_sha256 !~ '^[0-9a-f]{64}$')
  ) THEN
    RAISE EXCEPTION '0024 restored evidence or attribution mismatch';
  END IF;
  IF EXISTS (
    SELECT canonical_id FROM integration.legacy_id_mappings
     WHERE source_system='PHOENIX_FAMILY_OS' AND entity_kind='FAMILY'
       AND mapping_status='VERIFIED'
     GROUP BY canonical_id HAVING count(*)>1
  ) THEN
    RAISE EXCEPTION '0024 multiple current VERIFIED application families';
  END IF;
END
$test$;

