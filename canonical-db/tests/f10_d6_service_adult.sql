\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF core.set_civil_capacity('018f0000-0000-7000-8000-000000008002',
    '018f0000-0000-7000-8000-000000001003','ADULT_VERIFIED','synthetic adult attestation') IS NOT TRUE
    THEN RAISE EXCEPTION 'service adult verification'; END IF;
  RAISE NOTICE 'PASS D12 service adult verification';
END $test$;
