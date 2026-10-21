\set ON_ERROR_STOP on

DO $test$
BEGIN
  IF (SELECT count(*) FROM canonical_migrations.applied
      WHERE migration_name IN ('0019_education_master_and_records.sql',
        '0020_education_service_read_hardening.sql')) <> 2 THEN
    RAISE EXCEPTION '0019/0020 restore ledger mismatch';
  END IF;
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='education'
      AND tablename IN ('institution','program','academic_record','score_record','language_test','plan','plan_target')) <> 7 THEN
    RAISE EXCEPTION '0019 restore education tables missing';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='education'
      AND tablename IN ('institution','program','academic_record','score_record','language_test','plan','plan_target')) <> 7 THEN
    RAISE EXCEPTION '0019 restore education RLS policies missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_schema='education' AND table_name='applications' AND column_name='institution_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
      WHERE table_schema='education' AND table_name='applications' AND column_name='program_id') THEN
    RAISE EXCEPTION '0019 restore application master columns missing';
  END IF;
  IF has_table_privilege('phoenix_canonical_app','education.academic_record','INSERT') THEN
    RAISE EXCEPTION '0019 restore app retained direct education DML';
  END IF;
  IF has_function_privilege('public','education.create_academic_record(uuid,uuid,uuid,text,text,date,uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0019 restore write function executable by PUBLIC';
  END IF;
  IF NOT has_function_privilege('phoenix_canonical_app','education.create_academic_record(uuid,uuid,uuid,text,text,date,uuid)','EXECUTE') THEN
    RAISE EXCEPTION '0019 restore app write function grant missing';
  END IF;
END
$test$;

SELECT 'PASS 0019 restore catalog: ledger, tables, RLS, ACL and application target columns preserved';
