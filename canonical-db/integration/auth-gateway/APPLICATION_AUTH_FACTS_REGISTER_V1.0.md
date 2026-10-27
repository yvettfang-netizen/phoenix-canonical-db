# Phoenix Canonical Application Authentication Facts Register V1.0

**Status:** OPTION A APPROVED / LOCAL VERIFIER PASS / LIVE INTEGRATION HOLD
**Last verified:** 2026-10-27 (Asia/Shanghai)
**Purpose:** Record application-owned facts without changing the approved FD-6 rules
**Do not enter:** passwords, tokens, client secrets, private keys, database credentials or real user data

## Identity provider facts

The deployed application context uses WeChat Mini Program login: `wx.login` is exchanged by the trusted application server through WeChat `code2Session`, the server stores `openid` / optional `unionid`, and the application issues its own opaque bearer session. This is verified application behavior, but it is **not** an OIDC/JWT provider and supplies no OIDC issuer, audience or JWKS.

| Field | Verified value | Status |
|---|---|---|
| Provider context | WeChat Mini Program login (`code2Session` / OpenID) | VERIFIED APPLICATION CONTEXT |
| FD-6 contract direction | Preserve FD-6 and use an OIDC/JWT broker (Option A) | FOUNDER APPROVED 2026-10-26 |
| FD-6 provider name | A concrete broker product or first-party issuer implementation has not been selected | EVIDENCE_MISSING / HOLD |
| Issuer (`iss`) | Not present in the current WeChat opaque-session design | EVIDENCE_MISSING / HOLD |
| Audience (`aud`) | Not present in the current WeChat opaque-session design | EVIDENCE_MISSING / HOLD |
| JWKS URI or discovery URL | Not present in the current WeChat opaque-session design | EVIDENCE_MISSING / HOLD |
| Allowed algorithm | `RS256`, `ES256`, or both | FIXED RULE |
| Token maximum lifetime | No more than 900 seconds | FIXED RULE |
| Clock skew | No more than 60 seconds | FIXED RULE |
| JWKS cache | No more than 3600 seconds | FIXED RULE |

The existing seven-day opaque application session is not treated as an FD-6 JWT and cannot be entered into the OIDC fields. No provider metadata was inferred from WeChat URLs.

## Ownership facts

Founder confirmed on 2026-10-26 that the natural accountable owner for this gate is herself. Formal documents use the legal/formal name required by the Phoenix project rules.

| Field | Verified value | Status |
|---|---|---|
| Application owner | Founder 方琳媛 | CONFIRMED BY FOUNDER |
| Binder owner | Founder 方琳媛 | CONFIRMED BY FOUNDER |
| Principal-resolution owner | Founder 方琳媛 | CONFIRMED BY FOUNDER |
| Audit-event owner | Founder 方琳媛 | CONFIRMED BY FOUNDER |
| Incident-response owner | Founder 方琳媛 | CONFIRMED BY FOUNDER |

This ownership entry identifies current accountability; it does not create production on-call staffing or authorize production use.

## Runtime facts

| Field | Verified value | Status |
|---|---|---|
| Application GitHub repository | `yvettfang-netizen/phoenix` | VERIFIED; GITHUB REPORTS `PUBLIC` |
| Deployed application worktree | `/home/ubuntu/education-compass` | VERIFIED READ-ONLY |
| Deployed branch | `claude/education-compass-virtual-payment-20261012` | VERIFIED ON SERVER; REMOTE BRANCH REF ABSENT |
| Deployed commit | `79e59fc22c712b500f91c994f62a80e9d546f69f` | VERIFIED ON SERVER AND GITHUB COMMIT API |
| Runtime package | `phoenix-family-os-server` V0.5.0 | VERIFIED |
| Runtime processes | `phoenix_uat_api`, `phoenix_uat_agent_worker` | VERIFIED |
| Integration environment | Tencent isolated non-production; application path above; Canonical PostgreSQL listens on host loopback only | VERIFIED NON-PRODUCTION BOUNDARY |
| Canonical contract repository | `yvettfang-netizen/phoenix-canonical-db`, branch `codex/canonical-postgresql-phase1` | VERIFIED PRIVATE |
| App database credential reference | Not obtained | KEY REFERENCE HOLD |
| Binder database credential reference | Not obtained; must differ from app reference | KEY REFERENCE HOLD |
| Pool mode | Direct or session | FIXED RULE |
| Clear-on-return hook | No application implementation evidence found | IMPLEMENTATION HOLD |
| Clear-failure discard | No application implementation/test evidence found | IMPLEMENTATION HOLD |
| Gateway audit destination | No protected destination reference supplied | EVIDENCE_MISSING / HOLD |
| Application-side verifier | Provider-neutral `RS256` / `ES256` verifier, disabled by default | LOCAL IMPLEMENTATION / SYNTHETIC PASS |

The application source repository being public and the deployed branch lacking a remote branch ref do not satisfy the original “exact private repository and branch” entry criterion. The database contract repository is private, but it is not substituted for the application repository.

## Review record

- Supplied by: Founder 方琳媛 (ownership and repository-location statement)
- Verified by: Codex, read-only repository/server evidence
- Verification date/time and timezone: 2026-10-26, Asia/Shanghai
- Application contract path/version: `canonical-db/integration/auth-gateway/AUTH_GATEWAY_INTEGRATION_CONTRACT_V1.0.md`, V1.0
- Candidate configuration: `canonical-db/integration/auth-gateway/auth-contract.owner-confirmed.candidate.json`
- Configuration validation evidence: candidate is deliberately rejected in `integration` mode because OIDC metadata and both key references are absent
- Live JWKS/token test evidence: NOT RUN / unavailable
- Decision: `HOLD`

The Option A approval and local verifier close the contract-direction and code-skeleton steps only. They do not supply a broker product, live metadata, keys, application pools or permission to enable the verifier.

## Closure requirements

1. Select or approve the concrete OIDC/JWT broker/issuer implementation compatible with the existing WeChat login. Option A is already approved; the product/implementation is still missing.
2. Supply the exact HTTPS issuer, audience and JWKS/discovery URL for the selected OIDC path.
3. Create distinct protected secret-manager references for the app and binder database credentials; never enter secret values here.
4. Implement and test separate app/binder pools, ticket handoff, `auth.clear_context()` on return, discard-on-clear-failure and protected gateway audit output in the application repository.
5. Publish or otherwise make immutable the exact application branch/commit intended for isolated integration, then run the integration validator and negative token tests.

This register is not approved merely because confirmed fields are populated. The missing identity-provider and key facts keep live application integration on `HOLD`.
