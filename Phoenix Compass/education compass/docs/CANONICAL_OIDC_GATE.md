# Canonical FD-6 OIDC/JWT Gate

**Status:** LOCAL VERIFIER IMPLEMENTED / BROKER AND LIVE INTEGRATION HOLD
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

The verifier is disabled by default. It is not wired into the live request path and does not change the existing WeChat login or opaque application session.

## Configuration boundary

The following public facts are required before the verifier may be enabled:

- `CANONICAL_OIDC_ISSUER`
- `CANONICAL_OIDC_AUDIENCE`
- `CANONICAL_OIDC_JWKS_URI`

`CANONICAL_OIDC_ENABLED=true` with missing or invalid facts fails startup configuration. No signing key, client secret, database password or real token belongs in these settings or in Git.

## Still HOLD

- broker/provider selection and exact metadata;
- broker implementation or contracted external service;
- distinct app and binder secret-manager references and pools;
- mapping a verified broker subject to `auth.external_identities`;
- one-time ticket handoff, connection clear/discard and protected audit output in the application runtime;
- live token/JWKS tests, real identities, deployment and production use.

Synthetic tests generate temporary RSA and P-256 keys in memory only. They never persist or commit private key material.
