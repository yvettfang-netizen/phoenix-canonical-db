# Phoenix Canonical PostgreSQL — Next Gate Execution V1.18

**Execution date:** 2026-10-26 (Asia/Shanghai)
**Branch:** `codex/canonical-postgresql-phase1`
**Scope:** Current-state audit, isolated backup recovery, and FD-6 application-auth integration skeleton
**Verdict:** **PASS WITH LIVE OIDC INTEGRATION HOLD**

## 1. Boundaries

- No Migration was added or modified. The Canonical chain remains `0001`–`0022`.
- No real user, staff, family, customer, document, token, key or identity-provider fact was used.
- No production connection, production secret, real-data migration or production cutover occurred.
- No timer, cron job, external alert destination or offsite storage was installed.
- Only the existing private branch may receive this report; `origin`, Merge and PR remain out of scope.

## 2. Entry audit

The local branch and private remote both started at `90cfc4992557672cfa03b07f1bc9d0343b39ef55`. The worktree was clean. V1.17 showed that database-side binder/app separation, one-use tickets, context clearing, direct-table denial and zero residual context were already complete.

The remaining FD-6 facts were still absent:

- identity-provider name;
- exact issuer and audience;
- exact JWKS or discovery URL;
- application, binder, principal-resolution, audit-event and incident-response owners;
- application repository/runtime and separate secret references.

These are application-owned facts and were not inferred.

## 3. Tencent isolated backup alert recovery

The read-only entry check found `BACKUP_STALE`: the newest verified backup was 66 hours old. The database itself was healthy, PostgreSQL had no published host port, `.env` remained mode `0600`, and the catalog remained 22 Migration rows, 50 tables and 41 RLS policies.

Authorized non-production recovery actions:

1. Ran `backup.sh` with its protected backup-role pgpass flow.
2. Created and verified `backups/phoenix_canonical_20261026T022222Z.dump` with 867 archive entries.
3. Restored the backup into a disposable `--network none` container.
4. Verified all 22 migration hashes, 50 tables, 41 policies, zero families and one synthetic audit row.
5. Re-ran health and alert checks; final alert count was `0`.

No backup was deleted and no schedule was installed. Raw evidence: `evidence/v1.18-tencent-backup-recovery.txt`.

Final read-only state remained:

- one synthetic SERVICE principal and no other principals;
- zero session contexts and zero exchange tickets;
- zero people, families, Consent grants, cases, documents, Education applications, Identity cases and Learning enrollments;
- healthy PostgreSQL 16.15 container with no published port.

Raw evidence: `evidence/v1.18-tencent-final-readonly.txt`.

## 4. FD-6 application-auth integration skeleton

Added `integration/auth-gateway/` with:

| Artifact | Purpose |
|---|---|
| `AUTH_GATEWAY_INTEGRATION_CONTRACT_V1.0.md` | Fixed OIDC/JWT, mapping, binder/app, ticket, pool, audit and denial rules |
| `APPLICATION_AUTH_FACTS_REGISTER_V1.0.md` | Exact application-owned facts and owners still required |
| `auth-contract.template.json` | Integration configuration template containing no secret values |
| `fixtures/auth-contract.valid.synthetic.json` | Synthetic-only positive fixture using `.invalid` URLs |
| `validate-auth-contract.ps1` | Fail-closed machine validator for the approved FD-6 rules |
| `tests/auth_gateway_contract_regression.ps1` | Standalone synthetic positive and negative regression |

The validator enforces:

- `RS256` and/or `ES256` only;
- required `iss`, `aud`, `exp`, `nbf` and `sub` claims;
- access-token lifetime at most 900 seconds;
- clock skew at most 60 seconds;
- JWKS cache at most 3600 seconds and one rate-limited unknown-`kid` refresh;
- `issuer + subject` mapping, no auto-provisioning and denial for missing/disabled mappings;
- ticket lifetime at most 60 seconds;
- direct/session pooling only;
- mandatory clear-on-return and connection discard on clear failure;
- separate app/binder roles, credentials and pools;
- no raw-token or personal-data logging;
- required request-correlation audit fields;
- integration mode rejects synthetic values and incomplete placeholders.

## 5. Executed acceptance

`tests/auth_gateway_contract_regression.ps1` passed 22 checks:

- one valid synthetic contract;
- integration-mode rejection of the synthetic fixture and incomplete template;
- missing issuer;
- `HS256` and `none`;
- excessive token lifetime, skew and JWKS cache;
- missing unknown-`kid` refresh;
- missing required claims;
- automatic principal creation and fail-open missing mapping;
- excessive ticket lifetime;
- transaction pooling;
- missing clear/discard behavior;
- unseparated or identical credential references;
- raw-token, personal-data and incomplete audit logging.

Result: `PASS_AUTH_GATEWAY_CONTRACT_REGRESSION`.

Local Docker Desktop was initially stopped. It was started without rebuilding or resetting a database. Existing PG16 and PG17 health checks then passed. Evidence:

- `evidence/v1.18-auth-gateway-contract-regression.txt`
- `evidence/v1.18-local-pg16-pg17-health.txt`
- `evidence/v1.18-static-review.txt`

## 6. SHA-256

| Artifact | SHA-256 |
|---|---|
| `AUTH_GATEWAY_INTEGRATION_CONTRACT_V1.0.md` | `972b9574004fda20b7cf1dfe9f4ba68c18e9f87543b7f4f392890aaed903814a` |
| `APPLICATION_AUTH_FACTS_REGISTER_V1.0.md` | `7d9ff1e27d5d1a2bb4488d7b60655cc08300adeb60d725f72fd0d1fa832b71ca` |
| `auth-contract.template.json` | `0a0a25f659aca1d0a596ea18fcf6926bccfd5bc0eba424e3b38f2a741c4ca1a7` |
| `auth-contract.valid.synthetic.json` | `c677a7c0d6ab60d1e01ff2dd1459c3fc8b47caf2ee32783a4b7ba079389642a6` |
| `validate-auth-contract.ps1` | `48f54778f9d3bf86c777501e6369502bc5ebf6072160c7d702c5051ac46e0440` |
| `auth_gateway_contract_regression.ps1` | `26ec50fcc578750cdf1eba7e117b62b90fc4fc60a3f87ce9f676fa3ea826758e` |
| `v1.18-auth-gateway-contract-regression.txt` | `37969ad96db933b2a1fa2ba26fdb069bdc8b6d11a48ceb19713b0eb51778b5f1` |
| `v1.18-tencent-backup-recovery.txt` | `2958ec943cd079d57fa5064b8763191892b4023a0cd238e2394862139c61cfb7` |
| `v1.18-tencent-final-readonly.txt` | `ef735e53e5948a6c281fa5f4c0ce49d9c69dc2003fcc358ae9d07a119b264ae5` |
| `v1.18-local-pg16-pg17-health.txt` | `83e744fb42f704918e423939791953cd20ac4333aeafcf4b2bc477ba0398b717` |

## 7. Remaining HOLD and next gate

| Item | Status | Closure evidence required |
|---|---|---|
| Real OIDC/JWT/JWKS validation | HOLD | Completed facts register, reviewed integration config, real provider connectivity and token negative tests |
| Real external identity mappings and staff accounts | HOLD | Approved identities and two-person provisioning evidence |
| Automated Tencent backup scheduling | HOLD | Trusted-host/scheduler approval and operational owner evidence; manual backup is current |
| Production use, real data and production secrets | HOLD | Separate production release and migration gates |

**Unique next action:** the application owner completes `APPLICATION_AUTH_FACTS_REGISTER_V1.0.md` with public provider metadata, named owners, exact app repository/runtime and secret references. After review, run the validator in `integration` mode and request separate approval for isolated application integration. The skeleton itself does not authorize live integration.
