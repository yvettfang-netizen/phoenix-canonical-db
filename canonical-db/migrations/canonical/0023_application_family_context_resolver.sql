BEGIN;

-- Founder-approved application family context gate. The application identifier
-- namespace is fixed here so callers cannot select a second mapping authority.
-- Resolution and ticket issuance happen in one SECURITY DEFINER call on the
-- binder connection. No mapping or identity is auto-provisioned.
CREATE FUNCTION auth.issue_application_family_context_ticket(
  p_issuer text,
  p_subject text,
  p_application_family_id text,
  p_expires_at timestamptz,
  p_request_nonce uuid
) RETURNS TABLE(
  principal_id uuid,
  actor_person_id uuid,
  family_id uuid,
  ticket_id uuid
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, integration, core
AS $fn$
DECLARE
  v_principal_id uuid;
  v_actor_person_id uuid;
  v_family_id uuid;
  v_ticket_id uuid;
BEGIN
  -- Invalid or unapproved application inputs are indistinguishable from an
  -- unresolved mapping. The authenticated caller receives no mapping oracle.
  IF p_issuer IS NULL OR length(btrim(p_issuer)) NOT BETWEEN 1 AND 500
     OR p_subject IS NULL OR p_subject !~ '^usr_[A-Za-z0-9_-]{1,128}$'
     OR p_application_family_id IS NULL
     OR p_application_family_id !~ '^fam_[0-9a-f]{32}$'
     OR p_request_nonce IS NULL
     OR p_expires_at IS NULL
     OR p_expires_at <= clock_timestamp()
     OR p_expires_at > clock_timestamp() + interval '60 seconds' THEN
    RETURN;
  END IF;

  SELECT p.principal_id, p.person_id, m.canonical_id
    INTO v_principal_id, v_actor_person_id, v_family_id
    FROM auth.external_identities e
    JOIN auth.principals p
      ON p.principal_id = e.principal_id
    JOIN integration.legacy_id_mappings m
      ON m.source_system = 'PHOENIX_FAMILY_OS'
     AND m.entity_kind = 'FAMILY'
     AND m.legacy_id = p_application_family_id
     AND m.mapping_status = 'VERIFIED'
    JOIN core.families f
      ON f.family_id = m.canonical_id
    JOIN core.family_memberships fm
      ON fm.family_id = f.family_id
     AND fm.person_id = p.person_id
     AND fm.valid_from <= clock_timestamp()
     AND (fm.valid_until IS NULL OR fm.valid_until > clock_timestamp())
   WHERE e.issuer = p_issuer
     AND e.subject = p_subject
     AND e.status = 'ACTIVE'
     AND p.status = 'ACTIVE'
     AND p.principal_kind = 'FAMILY'
     AND p.person_id IS NOT NULL
   FOR UPDATE OF e, p, m, fm;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_ticket_id := auth.issue_context_ticket(
    v_principal_id,
    v_actor_person_id,
    v_family_id,
    'FAMILY',
    p_expires_at,
    p_request_nonce,
    v_principal_id
  );

  RETURN QUERY SELECT v_principal_id, v_actor_person_id, v_family_id, v_ticket_id;
END
$fn$;

REVOKE EXECUTE ON FUNCTION auth.issue_application_family_context_ticket(
  text,text,text,timestamptz,uuid
) FROM PUBLIC, phoenix_canonical_app, phoenix_canonical_reader;
GRANT EXECUTE ON FUNCTION auth.issue_application_family_context_ticket(
  text,text,text,timestamptz,uuid
) TO phoenix_canonical_context_binder;

COMMIT;
