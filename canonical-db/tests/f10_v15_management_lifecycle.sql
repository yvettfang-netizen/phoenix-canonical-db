\set ON_ERROR_STOP on
DO $test$ BEGIN
  IF casework.create_case('018f0000-0000-7000-8000-000000009950',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001011',
    'Synthetic management lifecycle',NULL,NULL) IS NOT TRUE THEN RAISE EXCEPTION 'case create'; END IF;
  IF casework.create_advisor_assignment('018f0000-0000-7000-8000-000000009951',
    '018f0000-0000-7000-8000-000000009950','018f0000-0000-7000-8000-000000001004',
    clock_timestamp()+interval '1 day') IS NOT TRUE THEN RAISE EXCEPTION 'assignment create'; END IF;
  IF casework.revoke_advisor_assignment('018f0000-0000-7000-8000-000000009951') IS NOT TRUE THEN RAISE EXCEPTION 'assignment revoke'; END IF;
  IF casework.close_case('018f0000-0000-7000-8000-000000009950') IS NOT TRUE THEN RAISE EXCEPTION 'case close'; END IF;
  IF core.create_guardian_authority('018f0000-0000-7000-8000-000000009952',
    '018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002',
    '018f0000-0000-7000-8000-000000001011','VERIFIED','GENERAL',
    clock_timestamp()+interval '1 day','synthetic/lifecycle') IS NOT TRUE THEN RAISE EXCEPTION 'guardian create'; END IF;
  IF core.revoke_guardian_authority('018f0000-0000-7000-8000-000000009952') IS NOT TRUE THEN RAISE EXCEPTION 'guardian revoke'; END IF;
  IF integration.create_channel_grant('018f0000-0000-7000-8000-000000009953',
    '018f0000-0000-7000-8000-000000002005','018f0000-0000-7000-8000-000000000001',
    '018f0000-0000-7000-8000-000000001002',clock_timestamp()+interval '1 day') IS NOT TRUE THEN RAISE EXCEPTION 'channel create'; END IF;
  IF integration.revoke_channel_grant('018f0000-0000-7000-8000-000000009953') IS NOT TRUE THEN RAISE EXCEPTION 'channel revoke'; END IF;
  IF auth.create_login_principal('018f0000-0000-7000-8000-000000009954',
    '018f0000-0000-7000-8000-000000001011','FAMILY') IS NOT TRUE THEN RAISE EXCEPTION 'principal create'; END IF;
  IF auth.disable_login_principal('018f0000-0000-7000-8000-000000009954') IS NOT TRUE THEN RAISE EXCEPTION 'principal disable'; END IF;
  RAISE NOTICE 'PASS D10 management lifecycle case/assignment/guardian/channel/login create and close or revoke';
END $test$;
