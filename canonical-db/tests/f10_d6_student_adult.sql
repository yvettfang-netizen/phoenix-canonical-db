\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF consent.create_grant('018f0000-0000-7000-8000-000000008012',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001004',
    '018f0000-0000-7000-8000-000000001003','DOCUMENT_READ','GENERAL',
    clock_timestamp()+interval '1 day') IS NOT TRUE THEN RAISE EXCEPTION 'verified adult self consent'; END IF;
  RAISE NOTICE 'PASS D12 verified adult self consent';
END $test$;
