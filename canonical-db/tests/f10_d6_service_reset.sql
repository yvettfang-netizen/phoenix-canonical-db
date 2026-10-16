\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF core.set_civil_capacity('018f0000-0000-7000-8000-000000008003',
    '018f0000-0000-7000-8000-000000001003','UNVERIFIED','synthetic corrected attestation') IS NOT TRUE
    THEN RAISE EXCEPTION 'service capacity reset'; END IF;
  RAISE NOTICE 'PASS D12 append-only later capacity status';
END $test$;
