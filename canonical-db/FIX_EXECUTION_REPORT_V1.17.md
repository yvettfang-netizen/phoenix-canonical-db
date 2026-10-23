# Phoenix Canonical PostgreSQL — Private Remote Sync and Application Authorization V1.17

**Execution date:** 2026-10-23 (Asia/Shanghai)
**Branch:** `codex/canonical-postgresql-phase1`
**Scope:** Private GitHub branch synchronization and database-side non-production application authorization
**Verdict:** **PASS WITH APPLICATION-INTEGRATION HOLD**

## 1. Boundaries

- The target GitHub repository is the existing private remote `canonical-private`; `origin` was not pushed.
- The Tencent database remains an isolated non-production environment. No PostgreSQL host port is published.
- No real customer, family, person, staff, document or historical data was used.
- Migrations `0001`–`0022` were not modified. No new Migration was created.
- The installed SERVICE principal is a synthetic non-production configuration identity, not a real employee or production workload identity.
- Web OIDC/JWT/JWKS validation, real external identity mapping, real staff provisioning and production cutover remain outside this execution.

## 2. Private remote synchronization

Before the first push, the private branch was `d3caaacda61d8367523c1f877c8a6b1cfeabd666` and the local branch was `090b7be24ead3d582a9d1ffa28e884172217dab6`. Git verified that the private branch was an ancestor of the local branch. The push was a fast-forward update to the exact branch `refs/heads/codex/canonical-postgresql-phase1`.

Raw evidence: `evidence/v1.17-private-push-initial.txt`.

## 3. Database-side application authorization

The existing installer registered the synthetic UUIDv7 SERVICE principal `018f0000-0000-7000-8000-00000000a001` with label `phoenix-nonprod-management-service`. The server `.env` was backed up before the first change and both files remained mode `0600`. No secret value was printed or passed as `PGPASSWORD`; the tests used protected container-local pgpass files.

The following checks passed with separate real LOGIN sessions:

| Check | Result |
|---|---|
| Binder and app use separate runtime LOGIN roles | PASS |
| Binder issues a 45-second one-use INTERNAL ticket for the SERVICE principal | PASS |
| App redeems the ticket and receives the expected principal/channel with null actor and family | PASS |
| `clear_context()` removes the bound context | PASS |
| Reuse of the consumed ticket | REJECTED |
| Redemption with the wrong expected principal | REJECTED; the correct principal could still redeem afterward |
| SERVICE principal with FAMILY channel | REJECTED |
| App direct table write | REJECTED |
| App tables with effective direct INSERT/UPDATE/DELETE | `0` |
| PUBLIC access to controlled auth functions | `0` |
| Residual session-context rows after completion | `0` |
| Residual ticket rows after completion | `0` |

Raw evidence:

- `evidence/v1.17-tencent-application-auth.sh`
- `evidence/v1.17-tencent-application-auth.txt`
- `evidence/v1.17-tencent-application-auth-final-readonly.sh`
- `evidence/v1.17-tencent-application-auth-final-readonly.txt`

SHA-256:

| File | SHA-256 |
|---|---|
| `v1.17-tencent-application-auth.sh` | `4d7b1c94075e9f1be10ddeb7530d3d84343ffdc39ec9bbf299912daf707f6d59` |
| `v1.17-tencent-application-auth.txt` | `775a35a2df7b758f8c673b48e272025c5c886544ac277413e583d62156da171e` |
| `v1.17-tencent-application-auth-final-readonly.sh` | `a948e24a2b62fa7bda8615f43e6b1ce035cc7dd407771bc02f76f9439e4f59df` |
| `v1.17-tencent-application-auth-final-readonly.txt` | `28ba48c0fa090e80cfb36dd64076386efeb0b72c7ba267e1d985f0506532e864` |

## 4. Database and recovery state

Final read-only verification reported:

- PostgreSQL `16.15`.
- `22` matching Migration ledger rows.
- `50` Canonical tables.
- `41` RLS policies.
- One active synthetic SERVICE principal and no other principals.
- Zero people, families, Consent grants, cases, documents, Education applications, Identity cases and Learning enrollments.
- Zero residual session contexts and exchange tickets.
- Container healthy with `PORTS={}`.

Backup `backups/phoenix_canonical_20261023T082057Z.dump` passed archive verification with `867` entries. A fresh `--network none` container restored it successfully, matched all 22 migration files, restored 50 tables and 41 policies, and reported zero families. The restored audit ledger contains one synthetic administrative event created by this authorization exercise.

## 5. Corrected test-harness attempts

Three preliminary harness attempts were retained as raw evidence:

- Attempt 1 directly called the internal-only `auth.is_internal_service()` function from the app role. PostgreSQL correctly denied the call. The final test validates only the app-exposed context functions.
- Attempt 2 used `has_function_privilege('PUBLIC', ...)`, which PostgreSQL interpreted as a nonexistent role. The final query inspects ACL entries with grantee OID `0`.
- Attempt 3 used two obsolete plural table names in a read-only zero-row query. The final query uses `core.family_memberships` and `learning.enrollment`.

These were test-harness errors. They did not create family, person or other business records. The final read-only state is captured separately.

## 6. Remaining HOLD

| Item | Status | Required next input or implementation |
|---|---|---|
| Application-side OIDC/JWT/JWKS validation | HOLD | Approved identity provider facts, issuer/audience/JWKS location and gateway implementation |
| Real external identity mappings and staff accounts | HOLD | Two-person reviewed real provisioning plan and approved source identities |
| Production credentials and production deployment | HOLD | Production release gate, security review and explicit cutover approval |
| Real data or legacy migration | HOLD | Separate approved migration phase and evidence |

The database-side non-production authorization gate is complete. It does not represent production application authentication or production deployment.
