# Phoenix Canonical Application Authentication Facts Register V1.0

**Status:** PUBLIC ORIGIN + PROTECTED FILES STAGED / LOCAL BROKER+VERIFIER+CONTEXT BRIDGE PASS / LIVE INTEGRATION HOLD
**Last verified:** 2026-10-28 (Asia/Shanghai)
**Purpose:** Record application-owned facts without changing the approved FD-6 rules
**Do not enter:** passwords, tokens, client secrets, private keys, database credentials or real user data

## Identity provider facts

The deployed application context uses WeChat Mini Program login: `wx.login` is exchanged by the trusted application server through WeChat `code2Session`, the server stores `openid` / optional `unionid`, and the application issues its own opaque bearer session. This is verified application behavior, but it is **not** an OIDC/JWT provider and supplies no OIDC issuer, audience or JWKS.

| Field | Verified value | Status |
|---|---|---|
| Provider context | WeChat Mini Program login (`code2Session` / OpenID) | VERIFIED APPLICATION CONTEXT |
| FD-6 contract direction | Preserve FD-6 and use an OIDC/JWT broker (Option A) | FOUNDER APPROVED 2026-10-26 |
| FD-6 provider name | `Phoenix First-Party Canonical Identity Broker V1.0` | TECHNICALLY SELECTED / LOCAL IMPLEMENTATION |
| Issuer (`iss`) | `https://api.phoenixnova.com.cn/canonical-identity` | VERIFIED PUBLIC ORIGIN / STAGED |
| Audience (`aud`) | `phoenix-canonical-postgresql` | FIXED |
| JWKS URI or discovery URL | `https://api.phoenixnova.com.cn/.well-known/phoenix-canonical-jwks.json` | VERIFIED PUBLIC ORIGIN / ENDPOINT NOT LIVE |
| Allowed algorithm | `ES256` only | FIXED |
| Token maximum lifetime | 300 seconds | FIXED |
| Clock skew | No more than 60 seconds | FIXED RULE |
| JWKS cache | 300 seconds | FIXED |

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
| Deployed application worktree | `/home/ubuntu/education-compass` | VERIFIED; TRACKED SOURCE UNCHANGED |
| Deployed branch | `claude/education-compass-virtual-payment-20261012` | VERIFIED ON SERVER; REMOTE BRANCH REF ABSENT |
| Deployed commit | `79e59fc22c712b500f91c994f62a80e9d546f69f` | VERIFIED ON SERVER AND GITHUB COMMIT API |
| Runtime package | `phoenix-family-os-server` V0.5.0 | VERIFIED |
| Runtime API | Node.js process on `127.0.0.1:3010`, proxied by Nginx | VERIFIED; NOT RESTARTED |
| Integration environment | Tencent isolated non-production; application path above; Canonical PostgreSQL listens on host loopback only | VERIFIED NON-PRODUCTION BOUNDARY |
| Canonical contract repository | `yvettfang-netizen/phoenix-canonical-db`, branch `codex/canonical-postgresql-phase1` | VERIFIED PRIVATE |
| Signing-key reference | `file:/run/secrets/phoenix_canonical_oidc_signing_key_v1` | TENCENT ISOLATED STAGED / 0600 / DISABLED |
| App database credential reference | `file:/run/secrets/phoenix_canonical_app_pgpass_v1` | TENCENT ISOLATED STAGED / 0600 / LOGIN PASS |
| Binder database credential reference | `file:/run/secrets/phoenix_canonical_binder_pgpass_v1` | TENCENT ISOLATED STAGED / 0600 / DISTINCT / LOGIN PASS |
| Pool mode | Direct or session | FIXED RULE |
| Clear-on-return hook | `auth.clear_context()` + NULL-principal assertion + `DISCARD ALL` | LOCAL IMPLEMENTATION / SYNTHETIC PASS |
| Clear-failure discard | rollback/clear uncertainty destroys the app connection; discard failure prevents reuse | LOCAL IMPLEMENTATION / SYNTHETIC PASS |
| Gateway audit destination | 0600 append-only JSONL path is required; no deployed path enabled | LOCAL IMPLEMENTATION PASS / LIVE DESTINATION HOLD |
| Application-side verifier | Provider-neutral verifier narrowed to the selected ES256 broker, disabled by default | LOCAL IMPLEMENTATION / SYNTHETIC PASS |
| First-party broker | Minimal claims, public JWKS only, no browser issuance route | LOCAL IMPLEMENTATION / SYNTHETIC PASS |
| Application subject derivation | authenticated server `usr_*` user ID; never OpenID/UnionID or client input | LOCAL REVIEW CANDIDATE / SYNTHETIC PASS |
| Family route derivation | three read-only routes use trusted Store ownership; all other routes denied | LOCAL REVIEW CANDIDATE / NOT WIRED |
| Canonical actor/family resolver | no approved family legacy-mapping resolver exists | CONTRACT HOLD |

The application source repository being public and the deployed branch lacking a remote branch ref do not satisfy the original “exact private repository and branch” entry criterion. The database contract repository is private, but it is not substituted for the application repository.

## Review record

- Supplied by: Founder 方琳媛 (ownership and repository-location statement)
- Verified by: Codex, read-only repository/server evidence
- Verification date/time and timezone: 2026-10-27, Asia/Shanghai
- Application contract path/version: `canonical-db/integration/auth-gateway/AUTH_GATEWAY_INTEGRATION_CONTRACT_V1.0.md`, V1.0
- Candidate configuration: `canonical-db/integration/auth-gateway/auth-contract.owner-confirmed.candidate.json`
- Configuration validation evidence: candidate passes `integration` mode with exact origin, ES256 constraints and three protected references; drift cases reject
- Live JWKS/token test evidence: NOT RUN / unavailable
- Decision: `HOLD`

The public origin and protected files are staged only in the isolated Tencent environment. DNS, certificate, Nginx routing, 0600 permissions, distinct app/binder credentials and read-only role logins are verified. The application was not restarted, the deployed commit does not contain the broker implementation, and both enable flags remain `false`.

## Closure requirements

1. Publish or otherwise make immutable the exact application revision containing the broker/verifier and database-runtime integration.
2. Deploy and explicitly enable the locally tested separate app/binder pools, ticket handoff, clear/discard and protected audit only after isolated review.
3. Approve the authenticated application user ID as the broker `usr_*` subject, register reviewed external-identity records without automatic provisioning, and approve the actor/family resolver described in `APPLICATION_ROUTE_CONTEXT_CONTRACT_V1.0_REVIEW_CANDIDATE.md`.
4. Verify the broker public JWKS, token rejection paths and key rotation in the isolated environment before either enable flag changes.

Configuration staging and validator PASS do not constitute live integration approval. Missing runtime implementation, subject mapping and isolated end-to-end evidence keep the live application integration on `HOLD`.
