# Phoenix Canonical PostgreSQL — Option A Local OIDC/JWT Gate V1.20

**Execution date:** 2026-10-27 (Asia/Shanghai)

**Branch:** `codex/canonical-postgresql-phase1`

**Implementation commit:** `54b4117d30aaed6c32e9269170b76c398182a881`

**Scope:** Founder Option A approval record, provider-neutral application-side OIDC/JWT verifier, synthetic security regression and remaining broker-selection gate

**Verdict:** **PASS WITH CONCRETE BROKER, KEYS AND LIVE INTEGRATION HOLD**

## 1. Founder decision and boundary

Founder selected Option A: preserve FD-6 and use an OIDC/JWT broker. The decision record is anchored to `APPLICATION_IDENTITY_CONTRACT_FOUNDER_GATE_V1.0.md` SHA-256 `eec9add0f107bd09ba29e7211b12febc41977821857c30824ffcaecae2e3828a`.

This selection authorizes the contract direction and local provider-neutral implementation. It does not name a concrete broker product or supply issuer, audience, JWKS, keys or database credentials. Those facts remain fail-closed.

No Canonical Migration, database state, Tencent host, deployed application, real identity or production system was changed.

## 2. Implemented locally

The existing Phoenix Family OS server now contains a disabled-by-default verifier boundary that:

- accepts only `RS256` and `ES256`;
- checks exact issuer and one exact audience;
- requires `iss`, `aud`, `sub`, `nbf` and `exp`;
- limits token lifetime to 900 seconds and clock skew to 60 seconds;
- fetches HTTPS JWKS without redirects, with response size/type/key-count bounds;
- caches JWKS for at most one hour and performs one rate-limited unknown-`kid` refresh;
- rejects token-supplied key locations/material and private JWK members;
- rejects RSA keys below 2048 bits and EC keys outside P-256;
- fails closed on invalid config, network, metadata, key, claim or signature state;
- performs no automatic principal provisioning.

Only public metadata placeholders were added to `.env.example`; no secret value was added. `CANONICAL_OIDC_ENABLED` remains `false`, and the verifier is not wired into the live WeChat request path.

## 3. Synthetic acceptance

| Check | Result |
|---|---|
| TypeScript typecheck | PASS |
| Server build | PASS |
| Dedicated OIDC/JWT tests | 6/6 PASS |
| Full existing server regression | 93/93 PASS |
| Exact issuer/audience and TTL | PASS |
| RS256 and ES256 signature validation | PASS |
| `none` / HMAC / injected key header rejection | PASS |
| Tampered signature and bad claims rejection | PASS |
| Unknown `kid` refresh and rate limit | PASS |
| JWKS network/media/shape failure denial | PASS |
| Disabled/incomplete/unsafe config rejection | PASS |
| Credential-value scan | PASS |
| `git diff --check` | PASS |
| Canonical Migration changes | NONE |

Windows initially materialized hash-pinned SQL/JSON with CRLF and caused 17 cascading existing test failures. A scoped `.gitattributes` rule now forces LF for migration SQL and frozen JSON. The tracked files were re-materialized from unchanged Git objects; their approved hashes match and the full suite passes. No frozen file content was edited or committed.

## 4. Evidence and SHA-256

| Artifact | SHA-256 |
|---|---|
| `server/src/auth/oidc-jwt-verifier.ts` | `cf0d59e9460b5bd82a6de035104eb89720f48451d1b289261ad2cb5ed38f8ef3` |
| `server/tests/oidc-jwt-verifier.test.ts` | `de57c42dad1de132120126e8810c9ffc2b4f7f3adbb3b75c2f0ee282a0841a58` |
| `docs/CANONICAL_OIDC_GATE.md` | `0603f6b3d8f2047a52f87f1755192d0a9a75918945975f197d5b3ff6d1f7e0c8` |
| `FOUNDER_APPLICATION_IDENTITY_OPTION_A_APPROVAL.md` | `008115ceab970443305f2b5c72983c99e193d5862beda9d26a093b2eeaa97592` |
| `OIDC_BROKER_SELECTION_REGISTER_V1.0.md` | `78b3c393f1e9ee86428464bba8f9d81f2c123a2ea5d4ae95dc88bc60cc43ff53` |
| `v1.20-option-a-oidc-local-verifier.txt` | `197312e2b58b681b7f2a4d12e9cf73f4ac6de1825743ba6d024a8c7de5b865ba` |

Raw commands and outputs are stored in `canonical-db/evidence/v1.20-option-a-oidc-local-verifier.txt`.

## 5. Remaining HOLD

| Item | Status | Closure evidence |
|---|---|---|
| Concrete broker/product or first-party issuer | HOLD | Approved exact component, owner, repository and immutable revision |
| Exact `iss`, `aud`, JWKS URI | HOLD | Broker-owned public metadata |
| Signing-key reference | HOLD | Approved key-manager reference name; no key value in Git |
| Separate app and binder credential references | HOLD | Two distinct secret-manager reference names |
| App/binder pools, ticket handoff, clear/discard and audit | HOLD | Application implementation plus isolated negative tests |
| Existing WeChat identity to broker-subject mapping | HOLD | Approved mapping and no automatic provisioning |
| Tencent or production deployment | NOT EXECUTED / HOLD | Separate reviewed deployment gate |
| Real users, identities and business data | NOT USED / HOLD | Separate production/data authorization |

## 6. Unique next action

Complete `OIDC_BROKER_SELECTION_REGISTER_V1.0.md` with the exact broker/issuer implementation and its public metadata plus reference-only key locations. Until then, the verifier remains disabled and no live application integration is authorized.
