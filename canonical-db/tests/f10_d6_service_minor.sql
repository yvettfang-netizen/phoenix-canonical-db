\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF core.set_civil_capacity('018f0000-0000-7000-8000-000000008001',
    '018f0000-0000-7000-8000-000000001003','MINOR_VERIFIED','synthetic minor attestation') IS NOT TRUE
    THEN RAISE EXCEPTION 'service minor verification'; END IF;
  RAISE NOTICE 'PASS D12 service minor verification';
END $test$;
