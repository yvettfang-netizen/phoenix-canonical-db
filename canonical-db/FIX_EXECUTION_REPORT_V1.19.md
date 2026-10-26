# Phoenix Canonical PostgreSQL — Application Identity Facts Gate V1.19

**Execution date:** 2026-10-26 (Asia/Shanghai)
**Branch:** `codex/canonical-postgresql-phase1`
**Implementation commit:** `52aff6f8e702de62b562236c85435ceb915f7ddb`
**Scope:** Founder ownership confirmation, application runtime/repository verification, identity-context compatibility review and fail-closed candidate configuration
**Verdict:** **PASS WITH LIVE APPLICATION IDENTITY INTEGRATION HOLD**

## 1. Boundaries

- No Migration was added or modified. The Canonical chain remains `0001`–`0022`.
- No application or database deployment, restart, production switch, data import or real-identity provisioning occurred.
- No `.env`, token, password, private key, client secret or database credential value was read or written.
- Tencent inspection was read-only and limited to the already-authorized isolated non-production host and exact application/database paths.
- Only the private Canonical remote branch was updated. Public `origin`, Merge and PR were not used.

## 2. Closed facts

Founder confirmed that the natural accountable owner is herself. Formal engineering records now identify **Founder 方琳媛** as:

- application owner;
- binder owner;
- principal-resolution owner;
- audit-event owner;
- incident-response owner.

This closes the five ownership blanks but does not create production on-call staffing or authorize a live integration.

Read-only verification identified the application runtime:

| Fact | Verified value |
|---|---|
| Server worktree | `/home/ubuntu/education-compass` |
| Server branch | `claude/education-compass-virtual-payment-20261012` |
| Server/GitHub commit | `79e59fc22c712b500f91c994f62a80e9d546f69f` |
| Tracked worktree state | Clean |
| Package | `phoenix-family-os-server` V0.5.0 |
| Runtime processes | `phoenix_uat_api`, `phoenix_uat_agent_worker` |
| Application repository | `yvettfang-netizen/phoenix` (`PUBLIC`) |
| Deployed branch remote ref | Absent; the commit itself is available through GitHub |
| Canonical repository | `yvettfang-netizen/phoenix-canonical-db` (`PRIVATE`) |
| Canonical branch | `codex/canonical-postgresql-phase1` |

The application repository and the private Canonical repository are explicitly distinguished. A private database-contract repository is not evidence that the application repository is private.

## 3. Identity-context finding

The deployed application source proves this authentication flow:

1. Mini Program calls `wx.login`.
2. The trusted server exchanges the code with WeChat `jscode2session`.
3. The server maps `openid` / optional `unionid` to an application user.
4. The server issues its own random opaque bearer token and stores only its digest.
5. The current application session default is seven days.

This is not an OIDC/JWT provider. It does not provide the exact `iss`, `aud` or JWKS facts required by the approved FD-6 contract. The WeChat API URL and `openid` were not re-labelled as OIDC metadata.

## 4. Implemented gate changes

- Completed all five owner fields in `APPLICATION_AUTH_FACTS_REGISTER_V1.0.md`.
- Added exact application repository, runtime, branch, commit and environment facts.
- Recorded both database credential references as `KEY REFERENCE HOLD`, without adding secret values.
- Added `APPLICATION_AUTH_CONTEXT_EVIDENCE_V1.0.md` with the source-backed WeChat/opaque-session finding.
- Added `auth-contract.owner-confirmed.candidate.json`; it contains confirmed owners but deliberately unresolved OIDC and key-reference markers.
- Extended the permanent regression so `integration` mode must reject that candidate.
- Added `APPLICATION_IDENTITY_CONTRACT_FOUNDER_GATE_V1.0.md` with the two lawful contract paths and forbidden actions.

## 5. Executed acceptance

`auth_gateway_contract_regression.ps1` passed 23 checks. The new check confirms that ownership alone cannot open the integration gate while OIDC metadata and credential references are missing.

Direct candidate validation returned the expected nonzero result:

`AUTH_CONTRACT_INVALID: identity_provider.issuer must be an absolute HTTPS URL`

Additional results:

- candidate JSON parse: PASS;
- credential-value scan of staged changes: PASS;
- `git diff --check`: PASS;
- local PG16 health: PASS;
- local PG17 health: PASS;
- Migration changes from V1.18: NONE;
- Tencent PostgreSQL listener: `127.0.0.1:5432` only;
- Tencent Canonical container: healthy, with no published host port shown;
- private implementation push: `a8be324a...` → `52aff6f8...` PASS.

## 6. Evidence and SHA-256

| Artifact | SHA-256 |
|---|---|
| `APPLICATION_AUTH_FACTS_REGISTER_V1.0.md` | `2e851f165c2ccb2740077f6113db7d08ca06354a269ab653016d31824d74e69a` |
| `APPLICATION_AUTH_CONTEXT_EVIDENCE_V1.0.md` | `92210e1e75172f3e779c2bbc4b53aff77f7cd6c534057789d607bb2834780cf0` |
| `auth-contract.owner-confirmed.candidate.json` | `fe22d5ca7ea2836c529bb8dc9aea1fb704b98733731d95c55637ab4ac3986142` |
| `auth_gateway_contract_regression.ps1` | `98333a031f8df585c447e4cd2000ae06b92f383b6e1a9809f91095dcfafce4f0` |
| `v1.19-application-auth-runtime-facts.txt` | `e1c4c81229adebcdd3a16bc20073f4d11ab1fcb05234ab373cc403d6de1c29a0` |
| `v1.19-auth-gateway-contract-regression.txt` | `43c3bdd94fba07c03cad8dcab52c7e192581dffe292355b2d78ecf91245b7ee3` |
| `v1.19-local-health-and-migration-boundary.txt` | `de5169725086a836ac54c84b1845d54973309c99bf37c114cb15a7e8087609a4` |
| `APPLICATION_IDENTITY_CONTRACT_FOUNDER_GATE_V1.0.md` | `eec9add0f107bd09ba29e7211b12febc41977821857c30824ffcaecae2e3828a` |

Private push output is stored in `canonical-db/evidence/v1.19-private-push.txt`.

## 7. Remaining HOLD

| Item | Status | Closure evidence required |
|---|---|---|
| FD-6 identity contract direction | FOUNDER DECISION REQUIRED | Choose OIDC broker path or approve a reviewed opaque-session amendment |
| Exact OIDC issuer/audience/JWKS | HOLD | Required only after an OIDC provider/broker is selected |
| Separate app/binder key references | HOLD | Two distinct secret-manager reference names; no secret values in Git |
| App-side pool/ticket/clear/audit implementation | HOLD | Code and isolated negative integration tests in the approved application revision |
| Immutable application branch | HOLD | Publish/lock the intended remote branch or other approved immutable ref |
| Real users, production keys/data and production switch | HOLD | Separate production release gates |

## 8. Founder gate and unique next action

The prepared Founder Gate recommends preserving FD-6 and placing a standards-compliant OIDC/JWT broker between the existing WeChat login and the Canonical trusted-context gateway. The alternative is a formal FD-6 amendment for first-party opaque sessions with a new security review.

**Unique next action:** Founder records Option A or Option B in a separate signed decision record. Until that choice and the required key references exist, the application integration stays fail-closed and no live deployment is authorized.
