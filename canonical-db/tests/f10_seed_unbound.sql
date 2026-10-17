\set ON_ERROR_STOP on
DO $test$ BEGIN
  IF core.create_family('018f0000-0000-7000-8000-000000000001','Synthetic Family A') IS NOT TRUE THEN RAISE EXCEPTION 'seed family A'; END IF;
  IF core.create_family('018f0000-0000-7000-8000-000000000002','Synthetic Family B') IS NOT TRUE THEN RAISE EXCEPTION 'seed family B'; END IF;
  IF core.register_external_person('018f0000-0000-7000-8000-000000001004','Synthetic Advisor') IS NOT TRUE THEN RAISE EXCEPTION 'seed advisor'; END IF;
  IF core.register_external_person('018f0000-0000-7000-8000-000000001005','Synthetic Partner') IS NOT TRUE THEN RAISE EXCEPTION 'seed partner'; END IF;
  IF auth.create_login_principal('018f0000-0000-7000-8000-000000002004','018f0000-0000-7000-8000-000000001004','ADVISOR') IS NOT TRUE THEN RAISE EXCEPTION 'seed advisor principal'; END IF;
  IF auth.create_login_principal('018f0000-0000-7000-8000-000000002005','018f0000-0000-7000-8000-000000001005','CHANNEL') IS NOT TRUE THEN RAISE EXCEPTION 'seed channel principal'; END IF;
  IF casework.create_case('018f0000-0000-7000-8000-000000009930','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001004','Unbound denied',NULL,NULL) IS NOT FALSE THEN RAISE EXCEPTION 'unbound family operation allowed'; END IF;
  RAISE NOTICE 'PASS C3 unbound SERVICE created first family and has no person';
END $test$;
