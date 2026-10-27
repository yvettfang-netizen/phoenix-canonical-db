# Phoenix Canonical OIDC Broker Selection Register V1.0

**Status:** PUBLIC ORIGIN AND PROTECTED FILES STAGED / RUNTIME INTEGRATION HOLD

**Contract direction:** Option A — preserve FD-6 and use an OIDC/JWT broker

**Accountable owner:** Founder 方琳媛

**Prepared:** 2026-10-27 (Asia/Shanghai)

This register captures the remaining public and reference-only facts needed to enable the local verifier. It must never contain passwords, tokens, client secrets, private signing keys or database credentials.

## Required selection

| Field | Required value | Current status |
|---|---|---|
| Broker / issuer product or first-party component | `Phoenix First-Party Canonical Identity Broker V1.0`; trusted server-side component | SELECTED / LOCAL IMPLEMENTATION |
| Implementation repository and immutable revision | Private `yvettfang-netizen/phoenix-canonical-db`, branch `codex/canonical-postgresql-phase1`; final V1.22 commit | BRANCH FIXED / COMMIT IN EXECUTION REPORT |
| Upstream identity source | WeChat Mini Program `code2Session` / verified OpenID mapping | VERIFIED CONTEXT; BROKER MAPPING HOLD |
| HTTPS issuer (`iss`) | `https://api.phoenixnova.com.cn/canonical-identity` | PUBLIC ORIGIN VERIFIED / ENDPOINT NOT LIVE |
| Audience (`aud`) | `phoenix-canonical-postgresql` | FIXED |
| HTTPS JWKS URI | `https://api.phoenixnova.com.cn/.well-known/phoenix-canonical-jwks.json` | PUBLIC ORIGIN VERIFIED / ENDPOINT NOT LIVE |
| Signing algorithms | `ES256` only | FIXED |
| Access-token maximum lifetime | 300 seconds | FIXED |
| Clock skew | At most 60 seconds | FIXED RULE |
| JWKS cache | 300 seconds | FIXED |
| Signing-key reference | `file:/run/secrets/phoenix_canonical_oidc_signing_key_v1` | TENCENT ISOLATED STAGED / 0600 / DISABLED |
| App database credential reference | `file:/run/secrets/phoenix_canonical_app_pgpass_v1` | TENCENT ISOLATED STAGED / 0600 / LOGIN PASS |
| Binder database credential reference | `file:/run/secrets/phoenix_canonical_binder_pgpass_v1` | TENCENT ISOLATED STAGED / 0600 / DISTINCT / LOGIN PASS |
| Broker and incident owners | Founder 方琳媛 | CONFIRMED ACCOUNTABILITY |

## Selected implementation boundary

- The broker is a separate server-side trust component inside the existing trusted backend codebase; it is not a new customer-facing Phoenix product.
- It converts an already authenticated application user ID (`usr_*`) into a 300-second ES256 assertion. It never emits OpenID, name, phone, email, family ID or other personal fields.
- It exposes only the public JWKS endpoint. There is no browser/mobile token-issuance route.
- The signing private key is loaded only when the broker flag is enabled. On POSIX, startup rejects group/world-accessible key files.
- The verified DNS, certificate and Nginx route establish `https://api.phoenixnova.com.cn` as the isolated public origin.
- Root-owned 0600 persistent sources are projected at boot to the three 0600 `/run/secrets` targets. Secret values are not recorded in Git or evidence.
- The deployed application was not restarted and does not yet contain this broker revision. Both enable flags remain `false`.

## Acceptance after fields are completed

1. Validate the public metadata and reference-only configuration with the tracked integration validator.
2. Verify positive and negative JWT cases against an isolated non-production broker: signature, issuer, exact audience, expiry, not-before, lifetime, unknown `kid`, rotation and JWKS outage.
3. Implement separate app/binder pools, one-time ticket redemption, `auth.clear_context()` on return, discard-on-clear-failure and protected audit correlation.
4. Publish an immutable private application revision and run isolated end-to-end synthetic acceptance.
5. Keep real users, real data and production switching outside this gate.

Until every required field and acceptance item has evidence, both `CANONICAL_OIDC_BROKER_ENABLED` and `CANONICAL_OIDC_ENABLED` remain `false`.
