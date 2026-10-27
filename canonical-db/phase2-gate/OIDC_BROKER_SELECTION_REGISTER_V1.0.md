# Phoenix Canonical OIDC Broker Selection Register V1.0

**Status:** INPUT REQUIRED / LIVE INTEGRATION HOLD

**Contract direction:** Option A — preserve FD-6 and use an OIDC/JWT broker

**Accountable owner:** Founder 方琳媛

**Prepared:** 2026-10-27 (Asia/Shanghai)

This register captures the remaining public and reference-only facts needed to enable the local verifier. It must never contain passwords, tokens, client secrets, private signing keys or database credentials.

## Required selection

| Field | Required value | Current status |
|---|---|---|
| Broker / issuer product or first-party component | Exact approved name and version/hosting model | MISSING / HOLD |
| Implementation repository and immutable revision | Private repository plus branch/tag/commit | MISSING / HOLD |
| Upstream identity source | WeChat Mini Program `code2Session` / verified OpenID mapping | VERIFIED CONTEXT; BROKER MAPPING HOLD |
| HTTPS issuer (`iss`) | Exact immutable issuer string | MISSING / HOLD |
| Audience (`aud`) | One exact Canonical integration audience | MISSING / HOLD |
| HTTPS JWKS URI | Exact endpoint, redirect-free | MISSING / HOLD |
| Signing algorithms | `RS256`, `ES256`, or both | FIXED RULE |
| Access-token maximum lifetime | 900 seconds | FIXED RULE |
| Clock skew | At most 60 seconds | FIXED RULE |
| JWKS cache | At most 3600 seconds | FIXED RULE |
| Signing-key reference | Approved key-manager reference name only | MISSING / HOLD |
| App database credential reference | Approved secret-manager reference name only | MISSING / HOLD |
| Binder database credential reference | Different approved secret-manager reference name only | MISSING / HOLD |
| Broker and incident owners | Named operational owners | Founder accountable; operating assignments HOLD |

## Acceptance after fields are completed

1. Validate the public metadata and reference-only configuration with the tracked integration validator.
2. Verify positive and negative JWT cases against an isolated non-production broker: signature, issuer, exact audience, expiry, not-before, lifetime, unknown `kid`, rotation and JWKS outage.
3. Implement separate app/binder pools, one-time ticket redemption, `auth.clear_context()` on return, discard-on-clear-failure and protected audit correlation.
4. Publish an immutable private application revision and run isolated end-to-end synthetic acceptance.
5. Keep real users, real data and production switching outside this gate.

Until every required field and acceptance item has evidence, `CANONICAL_OIDC_ENABLED` remains `false`.
