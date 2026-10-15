\set ON_ERROR_STOP on
DO $test$
DECLARE v_rejected boolean := false; v_level text;
BEGIN
  PERFORM auth.bind_context('018f0000-0000-7000-8000-000000002001',
    '018f0000-0000-7000-8000-000000001001',
    '018f0000-0000-7000-8000-000000000001','INTERNAL',
    clock_timestamp()+interval '45 seconds',gen_random_uuid());
  INSERT INTO core.guardian_authorities(authority_id,family_id,guardian_person_id,
    subject_person_id,evidence_level,scope,valid_from,valid_until)
  VALUES ('018f0000-0000-7000-8000-000000003013',
    '018f0000-0000-7000-8000-000000000001',
    '018f0000-0000-7000-8000-000000001002',
    '018f0000-0000-7000-8000-000000001003',
    'SELF_DECLARED_LEGACY','GENERAL',transaction_timestamp(),
    transaction_timestamp()+interval '1 day');
  BEGIN
    UPDATE core.guardian_authorities SET evidence_level='VERIFIED'
     WHERE authority_id='018f0000-0000-7000-8000-000000003013';
  EXCEPTION WHEN others THEN
    IF SQLERRM='GUARDIAN_EVIDENCE_IMMUTABLE' THEN v_rejected:=true;
    ELSE RAISE; END IF;
  END;
  SELECT evidence_level INTO v_level FROM core.guardian_authorities
   WHERE authority_id='018f0000-0000-7000-8000-000000003013';
  IF NOT v_rejected OR v_level<>'SELF_DECLARED_LEGACY' THEN RAISE EXCEPTION 'R-7 evidence changed or not rejected'; END IF;
  UPDATE core.guardian_authorities SET revoked_at=clock_timestamp()
   WHERE authority_id='018f0000-0000-7000-8000-000000003013';
  INSERT INTO core.guardian_authorities(authority_id,family_id,guardian_person_id,
    subject_person_id,evidence_level,scope,valid_from,valid_until)
  VALUES ('018f0000-0000-7000-8000-000000003014',
    '018f0000-0000-7000-8000-000000000001',
    '018f0000-0000-7000-8000-000000001002',
    '018f0000-0000-7000-8000-000000001003',
    'VERIFIED','GENERAL',transaction_timestamp(),
    transaction_timestamp()+interval '1 day');
  IF (SELECT lifecycle_status FROM core.guardian_authorities
      WHERE authority_id='018f0000-0000-7000-8000-000000003013') <> 'REVOKED'
     OR (SELECT evidence_level FROM core.guardian_authorities
      WHERE authority_id='018f0000-0000-7000-8000-000000003014') <> 'VERIFIED'
     OR (SELECT count(*) FROM audit.access_events
      WHERE resource_kind='GUARDIAN_AUTHORITY'
        AND resource_id IN ('018f0000-0000-7000-8000-000000003013',
                            '018f0000-0000-7000-8000-000000003014')) <> 3 THEN
    RAISE EXCEPTION 'R-7 replacement or audit missing';
  END IF;
  PERFORM auth.clear_context();
  RAISE NOTICE 'PASS R-7 evidence immutable; old record revoked; new record and three audit events';
END
$test$;

