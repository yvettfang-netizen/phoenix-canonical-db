\set ON_ERROR_STOP on
DO $test$
DECLARE denied boolean;
BEGIN
  denied := false;
  BEGIN
    UPDATE core.civil_capacity_history SET evidence_ref='synthetic overwrite'
      WHERE capacity_record_id='018f0000-0000-7000-8000-000000008001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%CIVIL_CAPACITY_HISTORY_IMMUTABLE%' THEN RAISE; END IF;
    denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'capacity evidence changed'; END IF;

  denied := false;
  BEGIN
    UPDATE education.external_facts SET external_reference='synthetic overwrite'
      WHERE fact_id='018f0000-0000-7000-8000-000000008102';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%EDUCATION_EXTERNAL_FACT_IMMUTABLE%' THEN RAISE; END IF;
    denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'official fact changed'; END IF;

  denied := false;
  BEGIN
    DELETE FROM docs.submission_items
      WHERE submission_id='018f0000-0000-7000-8000-000000007001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%CONFIRMED_MANIFEST_ITEMS_IMMUTABLE%' THEN RAISE; END IF;
    denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'confirmed manifest item deleted'; END IF;
  RAISE NOTICE 'PASS D12/D13/D14 append-only evidence, official fact and confirmed item locks';
END $test$;
