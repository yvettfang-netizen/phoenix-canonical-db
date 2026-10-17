\set ON_ERROR_STOP on
DO $test$
DECLARE v_rejected boolean := false;
BEGIN
  BEGIN
    UPDATE docs.documents SET withdrawn_at=NULL
      WHERE document_id='018f0000-0000-7000-8000-00000000b502';
  EXCEPTION WHEN others THEN
    IF SQLERRM='DOCUMENT_WITHDRAWAL_IMMUTABLE' THEN v_rejected:=true; ELSE RAISE; END IF;
  END;
  IF NOT v_rejected OR NOT EXISTS (SELECT 1 FROM docs.documents
      WHERE document_id='018f0000-0000-7000-8000-00000000b502' AND withdrawn_at IS NOT NULL) THEN
    RAISE EXCEPTION 'document withdrawal rollback protection failed';
  END IF;
  RAISE NOTICE 'PASS T3 withdrawn_at cannot be cleared or changed';
END
$test$;
