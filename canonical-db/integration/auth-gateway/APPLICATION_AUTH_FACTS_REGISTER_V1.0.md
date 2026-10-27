# Phoenix Canonical Application Authentication Facts Register V1.0

**Status:** FIRST-PARTY BROKER SELECTED / LOCAL BROKER+VERIFIER PASS / LIVE INTEGRATION HOLD
**Last verified:** 2026-10-27 (Asia/Shanghai)
**Purpose:** Record application-owned facts without changing the approved FD-6 rules
**Do not enter:** passwords, tokens, client secrets, private keys, database credentials or real user data

## Identity provider facts

The deployed application context uses WeChat Mini Program login: `wx.login` is exchanged by the trusted application server through WeChat `code2Session`, the server stores `openid` / optional `unionid`, and the application issues its own opaque bearer session. This is verified application behavior, but it is **not** an OIDC/JWT provider and supplies no OIDC issuer, audience or JWKS.

| Field | Verified value | Status |
|---|---|---|
| Provider context | WeChat Mini Program login (`code2Session` / OpenID) | VERIFIED APPLICATION CONTEXT |
| FD-6 contract direction | Preserve FD-6 and use an OIDC/JWT broker (Option A) | FOUNDER APPROVED 2026-10-26 |
| FD-6 provider name | `Phoenix First-Party Canonical Identity Broker V1.0` | TECHNICALLY SELECTED / LOCAL IMPLEMENTATION |
| Issuer (`iss`) | `<approved PUBLIC_BASE_URL>/canonical-identity` | PATH FIXED / PUBLIC ORIGIN HOLD |
| Audience (`aud`) | `phoenix-canonical-postgresql` | FIXED |
| JWKS URI or discovery URL | `<approved PUBLIC_BASE_URL>/.well-known/phoenix-canonical-jwks.json` | PATH FIXED / PUBLIC ORIGIN HOLD |
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
| Deployed application worktree | `/home/ubuntu/education-compass` | VERIFIED READ-ONLY |
| Deployed branch | `claude/education-compass-virtual-payment-20261012` | VERIFIED ON SERVER; REMOTE BRANCH REF ABSENT |
| Deployed commit | `79e59fc22c712b500f91c994f62a80e9d546f69f` | VERIFIED ON SERVER AND GITHUB COMMIT API |
| Runtime package | `phoenix-family-os-server` V0.5.0 | VERIFIED |
| Runtime processes | `phoenix_uat_api`, `phoenix_uat_agent_worker` | VERIFIED |
| Integration environment | Tencent isolated non-production; application path above; Canonical PostgreSQL listens on host loopback only | VERIFIED NON-PRODUCTION BOUNDARY |
| Canonical contract repository | `yvettfang-netizen/phoenix-canonical-db`, branch `codex/canonical-postgresql-phase1` | VERIFIED PRIVATE |
| Signing-key reference | `file:/run/secrets/phoenix_canonical_oidc_signing_key_v1` | RESERVED / NOT PROVISIONED |
| App database credential reference | `file:/run/secrets/phoenix_canonical_app_pgpass_v1` | RESERVED / NOT PROVISIONED |
| Binder database credential reference | `file:/run/secrets/phoenix_canonical_binder_pgpass_v1` | RESERVED / NOT PROVISIONED; DISTINCT |
| Pool mode | Direct or session | FIXED RULE |
| Clear-on-return hook | No application implementation evidence found | IMPLEMENTATION HOLD |
| Clear-failure discard | No application implementation/test evidence found | IMPLEMENTATION HOLD |
| Gateway audit destination | No protected destination reference supplied | EVIDENCE_MISSING / HOLD |
| Application-side verifier | Provider-neutral verifier narrowed to the selected ES256 broker, disabled by default | LOCAL IMPLEMENTATION / SYNTHETIC PASS |
| First-party broker | Minimal claims, public JWKS only, no browser issuance route | LOCAL IMPLEMENTATION / SYNTHETIC PASS |

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

The Option A approval and first-party broker selection close the contract-direction, component, audience, path, algorithm, TTL and reference-name steps. The approved public origin, provisioned secret files, application pools and permission to enable the integration remain missing.

## Closure requirements

1. Supply and approve the exact `PUBLIC_BASE_URL`; the selected component then derives the exact issuer and JWKS URI from fixed paths.
2. Provision the three reserved protected files with separate key/credential values and restrictive permissions; never enter their contents here.
3. Verify the broker public metadata and key rotation in an isolated environment.
4. Implement and test separate app/binder pools, ticket handoff, `auth.clear_context()` on return, discard-on-clear-failure and protected gateway audit output in the application repository.
5. Publish or otherwise make immutable the exact application branch/commit intended for isolated integration, then run the integration validator and negative token tests.

This register is not approved merely because confirmed fields are populated. The missing identity-provider and key facts keep live application integration on `HOLD`.
