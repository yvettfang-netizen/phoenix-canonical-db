# Canonical FD-6 OIDC/JWT Gate

**Status:** FIRST-PARTY BROKER + VERIFIER LOCALLY IMPLEMENTED / LIVE INTEGRATION HOLD
**Founder direction:** Preserve FD-6 and use an OIDC/JWT broker (Option A, selected 2026-10-26)

## Implemented locally

`server/src/auth/oidc-jwt-verifier.ts` provides a provider-neutral verification boundary for a future approved broker:

- only `RS256` and `ES256`;
- exact issuer and audience;
- required `iss`, `aud`, `sub`, `nbf` and `exp`;
- token lifetime at most 900 seconds and clock skew at most 60 seconds;
- HTTPS JWKS, one-hour maximum cache and a single rate-limited refresh for an unknown `kid`;
- rejection of token-supplied `jku`, `jwk`, `x5u` and `x5c` key material;
- no automatic identity provisioning;
- fail-closed network, media-type, key-shape, claim and signature behavior.

The selected component is `Phoenix First-Party Canonical Identity Broker V1.0`. It is a server-side technical component, not a customer-facing product. It issues 300-second ES256 assertions for non-personal application user IDs, exposes only a public JWKS route, and has no browser/mobile token-issuance endpoint.

Both the broker and verifier are disabled by default. They do not change the existing WeChat login or opaque application session.

## Configuration boundary

The approved metadata shape is:

- issuer: `<approved PUBLIC_BASE_URL>/canonical-identity`;
- audience: `phoenix-canonical-postgresql`;
- JWKS: `<approved PUBLIC_BASE_URL>/.well-known/phoenix-canonical-jwks.json`;
- signing algorithm: `ES256`;
- token TTL: 300 seconds.

The following protected reference names are reserved but no secret value has been provisioned:

- `file:/run/secrets/phoenix_canonical_oidc_signing_key_v1`;
- `file:/run/secrets/phoenix_canonical_app_pgpass_v1`;
- `file:/run/secrets/phoenix_canonical_binder_pgpass_v1`.

The following public facts are still required before the verifier may be enabled:

- `CANONICAL_OIDC_ISSUER`
- `CANONICAL_OIDC_AUDIENCE`
- `CANONICAL_OIDC_JWKS_URI`

`CANONICAL_OIDC_ENABLED=true` with missing or invalid facts fails startup configuration. No signing key, client secret, database password or real token belongs in these settings or in Git.

## Still HOLD

- approved exact HTTPS `PUBLIC_BASE_URL`, which resolves the fixed issuer/JWKS paths;
- provisioned signing, app and binder secret files with restrictive permissions;
- distinct app and binder pools using the reserved references;
- mapping a verified broker subject to `auth.external_identities`;
- one-time ticket handoff, connection clear/discard and protected audit output in the application runtime;
- live token/JWKS tests, real identities, deployment and production use.

Synthetic tests generate temporary P-256 keys in memory only. They never persist or commit private key material.
