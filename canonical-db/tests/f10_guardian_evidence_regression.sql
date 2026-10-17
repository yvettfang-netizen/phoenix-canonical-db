\set ON_ERROR_STOP on
DO $test$ BEGIN
  IF core.create_guardian_authority('018f0000-0000-7000-8000-000000003013',
      '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002',
      '018f0000-0000-7000-8000-000000001003','SELF_DECLARED_LEGACY','GENERAL',
      clock_timestamp()+interval '1 day','synthetic/legacy') IS NOT FALSE THEN
    RAISE EXCEPTION 'legacy authority must be denied'; END IF;
  IF core.create_guardian_authority('018f0000-0000-7000-8000-000000003013',
      '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002',
      '018f0000-0000-7000-8000-000000001003','VERIFIED','GENERAL',
      clock_timestamp()+interval '1 day','') IS NOT FALSE THEN
    RAISE EXCEPTION 'missing evidence must be denied'; END IF;
  IF core.create_guardian_authority('018f0000-0000-7000-8000-000000003013',
      '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002',
      '018f0000-0000-7000-8000-000000001003','VERIFIED','GENERAL',
      clock_timestamp()+interval '1 day','synthetic/evidence/general') IS NOT TRUE THEN
    RAISE EXCEPTION 'verified creation'; END IF;
  IF core.revoke_guardian_authority('018f0000-0000-7000-8000-000000003013') IS NOT TRUE THEN
    RAISE EXCEPTION 'guardian revocation'; END IF;
  IF core.create_guardian_authority('018f0000-0000-7000-8000-000000003014',
      '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002',
      '018f0000-0000-7000-8000-000000001003','VERIFIED','GENERAL',
      clock_timestamp()+interval '1 day','synthetic/evidence/replacement') IS NOT TRUE THEN
    RAISE EXCEPTION 'verified replacement'; END IF;
  RAISE NOTICE 'PASS R-7/D10 legacy and missing evidence denied; verified authority revoked and replaced by API';
END $test$;
