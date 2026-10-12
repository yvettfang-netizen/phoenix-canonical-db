-- Disposable synthetic decision-mechanism probe. No Canonical business objects.
-- Arguments stand in for a trusted server decision; this is not session binding.
BEGIN;
CREATE SCHEMA acceptance_probe;

CREATE TABLE acceptance_probe.mapping_claims (
  source_system text NOT NULL,
  legacy_id text NOT NULL,
  canonical_key uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('VERIFIED','REVOKED')),
  PRIMARY KEY (source_system, legacy_id, canonical_key)
);
CREATE TABLE acceptance_probe.decision_audit (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  operation text NOT NULL,
  reason text NOT NULL
);

CREATE FUNCTION acceptance_probe.resolve_legacy(p_source text, p_legacy text)
RETURNS TABLE (resolved_key uuid, reason text) LANGUAGE plpgsql AS $fn$
DECLARE
  candidate_count integer;
  candidate uuid;
  decision text;
BEGIN
  SELECT count(DISTINCT canonical_key), min(canonical_key::text)::uuid
    INTO candidate_count, candidate
    FROM acceptance_probe.mapping_claims
   WHERE source_system = p_source AND legacy_id = p_legacy AND status = 'VERIFIED';
  IF candidate_count = 0 THEN decision := 'MAPPING_NOT_FOUND';
  ELSIF candidate_count > 1 THEN decision := 'MAPPING_AMBIGUOUS';
  ELSIF substring(candidate::text, 15, 1) <> '7' THEN decision := 'ID_VERSION_INVALID';
  ELSE decision := 'ALLOW';
  END IF;
  INSERT INTO acceptance_probe.decision_audit(operation, reason) VALUES ('RESOLVE_LEGACY', decision);
  IF decision = 'ALLOW' THEN resolved_key := candidate; END IF;
  reason := decision;
  RETURN NEXT;
END
$fn$;

INSERT INTO acceptance_probe.mapping_claims VALUES
  ('synthetic-source-a','same-id','01920000-0000-7000-8000-000000000001','VERIFIED'),
  ('synthetic-source-b','same-id','01920000-0000-7000-8000-000000000002','VERIFIED'),
  ('synthetic-source-a','ambiguous','01920000-0000-7000-8000-000000000003','VERIFIED'),
  ('synthetic-source-a','ambiguous','01920000-0000-7000-8000-000000000004','VERIFIED'),
  ('synthetic-source-a','wrong-version','01920000-0000-4000-8000-000000000005','VERIFIED');

CREATE TABLE acceptance_probe.guardian_authority (
  guardian_key uuid PRIMARY KEY,
  family_scope text NOT NULL,
  evidence_kind text NOT NULL,
  expires_at timestamptz NOT NULL
);
CREATE TABLE acceptance_probe.consent_decisions (
  guardian_key uuid PRIMARY KEY REFERENCES acceptance_probe.guardian_authority,
  status text NOT NULL CHECK (status IN ('ACTIVE','WITHDRAWN'))
);
CREATE FUNCTION acceptance_probe.guardian_document_decision(
  p_guardian uuid, p_family text, p_at timestamptz
) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE
  authority acceptance_probe.guardian_authority%ROWTYPE;
  consent_status text;
  decision text;
BEGIN
  SELECT * INTO authority FROM acceptance_probe.guardian_authority WHERE guardian_key = p_guardian;
  SELECT status INTO consent_status FROM acceptance_probe.consent_decisions WHERE guardian_key = p_guardian;
  IF NOT FOUND OR consent_status IS NULL OR consent_status <> 'ACTIVE' THEN
    decision := 'CONSENT_MISSING_OR_WITHDRAWN';
  ELSIF authority.family_scope IS DISTINCT FROM p_family THEN
    decision := 'FAMILY_SCOPE_MISMATCH';
  ELSIF authority.evidence_kind = 'SELF_DECLARED_LEGACY' THEN
    decision := 'GUARDIAN_EVIDENCE_INSUFFICIENT';
  ELSIF authority.expires_at <= p_at THEN
    decision := 'GUARDIAN_EXPIRED';
  ELSE
    decision := 'ALLOW';
  END IF;
  INSERT INTO acceptance_probe.decision_audit(operation, reason) VALUES ('GUARDIAN_DOC', decision);
  RETURN decision;
END
$fn$;

INSERT INTO acceptance_probe.guardian_authority VALUES
  ('01920000-0000-7000-8000-000000000011','synthetic-family-a','VERIFIED','2031-01-01 UTC'),
  ('01920000-0000-7000-8000-000000000012','synthetic-family-a','VERIFIED','2029-01-01 UTC'),
  ('01920000-0000-7000-8000-000000000013','synthetic-family-a','SELF_DECLARED_LEGACY','2031-01-01 UTC');
INSERT INTO acceptance_probe.consent_decisions VALUES
  ('01920000-0000-7000-8000-000000000011','ACTIVE'),
  ('01920000-0000-7000-8000-000000000012','ACTIVE'),
  ('01920000-0000-7000-8000-000000000013','ACTIVE');

DO $test$
DECLARE
  decision text;
  key_found uuid;
  at_time timestamptz := '2030-01-01 UTC';
BEGIN
  SELECT resolved_key, reason INTO key_found, decision FROM acceptance_probe.resolve_legacy('synthetic-source-a','same-id');
  IF decision <> 'ALLOW' OR key_found <> '01920000-0000-7000-8000-000000000001' THEN RAISE EXCEPTION 'source A mapping failed'; END IF;
  SELECT resolved_key, reason INTO key_found, decision FROM acceptance_probe.resolve_legacy('synthetic-source-b','same-id');
  IF decision <> 'ALLOW' OR key_found <> '01920000-0000-7000-8000-000000000002' THEN RAISE EXCEPTION 'source B mapping crossed source boundary'; END IF;
  SELECT resolved_key, reason INTO key_found, decision FROM acceptance_probe.resolve_legacy('synthetic-source-a','missing');
  IF decision <> 'MAPPING_NOT_FOUND' OR key_found IS NOT NULL THEN RAISE EXCEPTION 'unmapped legacy ID accepted'; END IF;
  SELECT resolved_key, reason INTO key_found, decision FROM acceptance_probe.resolve_legacy('synthetic-source-a','ambiguous');
  IF decision <> 'MAPPING_AMBIGUOUS' OR key_found IS NOT NULL THEN RAISE EXCEPTION 'ambiguous legacy ID accepted'; END IF;
  SELECT resolved_key, reason INTO key_found, decision FROM acceptance_probe.resolve_legacy('synthetic-source-a','wrong-version');
  IF decision <> 'ID_VERSION_INVALID' OR key_found IS NOT NULL THEN RAISE EXCEPTION 'non-v7 internal ID accepted'; END IF;

  IF acceptance_probe.guardian_document_decision('01920000-0000-7000-8000-000000000011','synthetic-family-a',at_time) <> 'ALLOW' THEN RAISE EXCEPTION 'verified guardian denied'; END IF;
  IF acceptance_probe.guardian_document_decision('01920000-0000-7000-8000-000000000011','synthetic-family-b',at_time) <> 'FAMILY_SCOPE_MISMATCH' THEN RAISE EXCEPTION 'cross-family guardian allowed'; END IF;
  IF acceptance_probe.guardian_document_decision('01920000-0000-7000-8000-000000000012','synthetic-family-a',at_time) <> 'GUARDIAN_EXPIRED' THEN RAISE EXCEPTION 'expired guardian allowed'; END IF;
  IF acceptance_probe.guardian_document_decision('01920000-0000-7000-8000-000000000013','synthetic-family-a',at_time) <> 'GUARDIAN_EVIDENCE_INSUFFICIENT' THEN RAISE EXCEPTION 'self-declared legacy guardian allowed'; END IF;
  UPDATE acceptance_probe.consent_decisions SET status = 'WITHDRAWN' WHERE guardian_key = '01920000-0000-7000-8000-000000000011';
  IF acceptance_probe.guardian_document_decision('01920000-0000-7000-8000-000000000011','synthetic-family-a',at_time) <> 'CONSENT_MISSING_OR_WITHDRAWN' THEN RAISE EXCEPTION 'withdrawn consent remained effective'; END IF;
  IF acceptance_probe.guardian_document_decision('01920000-0000-7000-8000-000000000099','synthetic-family-a',at_time) <> 'CONSENT_MISSING_OR_WITHDRAWN' THEN RAISE EXCEPTION 'unknown guardian allowed'; END IF;
  IF (SELECT count(*) FROM acceptance_probe.decision_audit) <> 11 THEN RAISE EXCEPTION 'missing decision audit events'; END IF;
END
$test$;
ROLLBACK;
