\set ON_ERROR_STOP on
DO $test$
DECLARE v_rejected boolean;
BEGIN
  v_rejected:=false;
  BEGIN
    INSERT INTO auth.principals(principal_id,person_id,principal_kind,status)
      VALUES('018f0000-0000-7000-8000-000000009970',NULL,'FAMILY','ACTIVE');
  EXCEPTION WHEN check_violation THEN v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'non-SERVICE without person accepted'; END IF;
  v_rejected:=false;
  BEGIN
    INSERT INTO auth.principals(principal_id,person_id,principal_kind,status,service_label)
      VALUES('018f0000-0000-7000-8000-000000009971',
        '018f0000-0000-7000-8000-000000001002','SERVICE','ACTIVE','Invalid service');
  EXCEPTION WHEN check_violation THEN v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'SERVICE with person accepted'; END IF;
  IF auth.install_service_principal('018f0000-0000-7000-8000-000000009972','Disposable installer service') IS NOT TRUE THEN
    RAISE EXCEPTION 'installer create'; END IF;
  IF (SELECT person_id IS NULL FROM auth.principals WHERE principal_id='018f0000-0000-7000-8000-000000009972') IS NOT TRUE THEN
    RAISE EXCEPTION 'installer SERVICE has person'; END IF;
  IF auth.disable_service_principal('018f0000-0000-7000-8000-000000009972') IS NOT TRUE THEN
    RAISE EXCEPTION 'installer disable'; END IF;
  RAISE NOTICE 'PASS D11 person-kind constraints and installer-only SERVICE create/disable';
END $test$;
