# Canonical FD-6 OIDC/JWT Gate

**Status:** FIRST-PARTY BROKER + VERIFIER + DATABASE CONTEXT BRIDGE LOCALLY IMPLEMENTED / LIVE ENABLEMENT HOLD
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

`server/src/auth/canonical-context-gateway.ts` and `canonical-context-runtime.ts` now implement the disabled application-to-database bridge:

- separate `phoenix_canonical_binder_runtime` and `phoenix_canonical_app_runtime` pools, each loaded from its own protected pgpass file;
- exact `usr_*` subject resolution through `auth.resolve_external_identity` with no automatic provisioning;
- a 45-second one-use ticket issued by binder and redeemed only on the app connection that performs the business transaction;
- business callback denial for transaction, role and `DISCARD` control;
- `auth.clear_context()`, a NULL principal assertion and `DISCARD ALL` before a connection is reused;
- connection destruction on rollback, clear uncertainty or discard failure;
- an append-only, 0600 JSONL audit containing only timestamp, request nonce, issuer, pseudonymous subject, channel, allow/deny and reason code.

The runtime has no public HTTP issuance or database-operation route. It is constructed only when all three explicit flags are enabled and the verifier metadata exactly matches the first-party broker. It therefore remains inert in the current application.

`server/src/auth/canonical-application-route-bridge.ts` adds a disabled, unwired application-context candidate. It accepts only three authenticated, family-owned GET routes; derives the application family through trusted Store ownership; issues the broker token internally; and requires an injected resolver to return reviewed Canonical actor/family UUIDv7 values. Unknown routes, writes, admin actors, cross-family students and missing/malformed mappings are denied before token issuance. No resolver is configured because the application `fam_*` UUIDv4 text cannot be treated as a Canonical UUIDv7 and no family legacy-mapping resolver has been approved.

## Configuration boundary

The verified isolated metadata is:

- public origin: `https://api.phoenixnova.com.cn`;
- issuer: `https://api.phoenixnova.com.cn/canonical-identity`;
- audience: `phoenix-canonical-postgresql`;
- JWKS: `https://api.phoenixnova.com.cn/.well-known/phoenix-canonical-jwks.json`;
- signing algorithm: `ES256`;
- token TTL: 300 seconds.

The following protected references are staged in the Tencent isolated non-production environment with 0600 runtime files. Their values are not stored in Git or evidence:

- `file:/run/secrets/phoenix_canonical_oidc_signing_key_v1`;
- `file:/run/secrets/phoenix_canonical_app_pgpass_v1`;
- `file:/run/secrets/phoenix_canonical_binder_pgpass_v1`.

The corresponding `.env.uat` reference-only configuration is staged, but the running process was not restarted. `CANONICAL_OIDC_BROKER_ENABLED`, `CANONICAL_OIDC_ENABLED` and `CANONICAL_CONTEXT_GATEWAY_ENABLED` remain `false`. Invalid or drifting facts still fail startup configuration. No signing key, database password or real token belongs in Git.

## Still HOLD

- deployment and explicit enablement of an immutable application revision containing the broker, verifier and context bridge;
- real `usr_*` mapping records in `auth.external_identities` (unknown or disabled mappings are denied);
- approval and implementation of the binder-side application-family mapping resolver described in `canonical-db/integration/auth-gateway/APPLICATION_ROUTE_CONTEXT_CONTRACT_V1.0_REVIEW_CANDIDATE.md`;
- live token/JWKS tests, real identities, deployment and production use.

Synthetic tests generate temporary P-256 keys in memory only. They never persist or commit private key material.
