\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF consent.create_grant('018f0000-0000-7000-8000-000000008011',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001004',
    '018f0000-0000-7000-8000-000000001003','DOCUMENT_READ','GENERAL',
    clock_timestamp()+interval '1 day') IS NOT FALSE THEN RAISE EXCEPTION 'unverified/minor self consent'; END IF;
  IF core.set_civil_capacity('018f0000-0000-7000-8000-000000008099',
    '018f0000-0000-7000-8000-000000001003','ADULT_VERIFIED','synthetic evidence') IS NOT FALSE
    THEN RAISE EXCEPTION 'family self capacity verification'; END IF;
  RAISE NOTICE 'PASS D12 unverified/minor self grant and family verification denied';
END $test$;
