# Phoenix Canonical PostgreSQL — FIX EXECUTION REPORT V1.26

- **Execution date:** 2026-10-29 (Asia/Shanghai)
- **Execution owner:** Codex
- **Founder authorization:** continue the approved first three read-only application routes
- **Scope:** exact response-field contract, live handler wiring and local synthetic HTTP-to-RLS acceptance
- **Result:** `PASS (LOCAL APP + PG16/17 E2E) / HOLD (REAL RECORDS, ENABLEMENT, TENCENT, PRODUCTION)`

## 1. Boundary confirmation

- Work was performed only in `codex/canonical-postgresql-phase1`.
- No Tencent connection, deployment, restart or remote file change was made.
- No production key, real identity, real family/student mapping, customer record, legacy import or Feishu data was used.
- No Migration was added or changed. Migrations `0001`–`0023` remain byte-preserved.
- The local HTTP tests used synthetic in-memory application records and synthetic Canonical rows only.
- Each disposable database published PostgreSQL on a random `127.0.0.1` port only; the container and temporary credential files were removed after the run.
- Runtime activation remains opt-in and fail-closed. No production switch was enabled.

## 2. Exact response-field contract

Artifact: `integration/auth-gateway/APPLICATION_READ_RESPONSE_FIELD_MAP_V1.0.md`

| Route | Response source | Exact response boundary |
|---|---|---|
| `GET /v1/me/family` | existing application Store | existing application family DTO; `fam_*` stays the public ID |
| `GET /v1/me/students` | existing application Store | existing application student DTO array owned by the current application family |
| `GET /v1/me/students/:studentId` | existing application Store | one application student DTO after exact owner-family verification |

Canonical PostgreSQL supplies the authorization decision only. Canonical UUIDv7 values and natural-person records are not copied into the response. A Canonical-source student DTO remains HOLD until VERIFIED `STUDENT_PROFILE` mapping authority exists.

## 3. Handler and RLS wiring

The server now constructs `CanonicalApplicationRouteBridge` only when both the approved first-party broker and context runtime are explicitly configured. On each approved GET route it:

1. authenticates the existing application session;
2. derives the trusted application user and owned family/student from the Store;
3. issues and cryptographically verifies a short-lived broker token;
4. calls the binder-only 0023 atomic identity/family resolver;
5. redeems the one-use ticket using the separate app LOGIN pool;
6. queries `core.families` under the bound FAMILY context and RLS;
7. returns only the enumerated application DTO fields;
8. clears context, verifies it is empty, commits and discards the app connection.

Any identity, mapping, membership, ticket or RLS failure prevents Store data from being returned. The student detail route still rejects a cross-family application student before token issuance.

## 4. Application regression

Command:

`npm.cmd test`

Result: `116/116 PASS`.

Raw evidence: `evidence/v1.26-application-tests.txt`
SHA-256: `7178dabb0933ec19477a0957995c6ddb678119f8b0be60073cb27ee9eb4dea28`.

## 5. PG16 / PG17 isolated HTTP end-to-end

Commands:

- `pwsh -File canonical-db/tests/run_v26_http_e2e.ps1 -Version 16`
- `pwsh -File canonical-db/tests/run_v26_http_e2e.ps1 -Version 17`

| Verification | PG16 | PG17 |
|---|---:|---:|
| Fresh 0001–0023 apply | PASS | PASS |
| Migration inventory / ledger | 23 / 23 | 23 / 23 |
| Catalog | 50 tables / 41 RLS policies | 50 tables / 41 RLS policies |
| Separate binder/app runtime LOGINs | PASS | PASS |
| Real loopback HTTP request | PASS | PASS |
| ES256 broker issue and verifier | PASS | PASS |
| Binder atomic resolver and one-use ticket | PASS | PASS |
| App-pool RLS family read | PASS | PASS |
| Exact family/list/detail application DTO | PASS | PASS |
| Cross-family application student denial | PASS | PASS |
| Unbound app LOGIN sees families | 0 | 0 |
| Residual session contexts | 0 | 0 |
| Residual unredeemed tickets | 0 | 0 |

Raw evidence:

- `evidence/v1.26-pg16-http-e2e.txt` — SHA-256 `1e3cacd8e2527223d146e58e8ebab1cd27e0c17e63724447a8dfc1057468ceda`
- `evidence/v1.26-pg17-http-e2e.txt` — SHA-256 `3f42a1137f6ff9cb418446bc56e67f1d4a5df9c4aa6aecc86544172a50fae4d5`

The E2E runner SHA-256 is `38b204987c45ed8c508d0c33d238558f74cad9fe741dac560f40dbb9d2503d28`; the Node HTTP E2E test SHA-256 is `f26924e256de9925a040475a3d124222f17bbfb1c2a358a39fee295aaa3a01ab`.

## 6. Security review

| Area | Result |
|---|---|
| Authentication | Real broker signing and verifier claim/signature checks exercised with synthetic keys |
| Authorization | Exact three-route allowlist and trusted Store ownership retained |
| Least privilege | Separate binder and app LOGIN accounts used; app cannot call the binder resolver |
| Tenant/RLS | Bound family visible; unbound app connection sees zero family rows; cross-family student rejected |
| Secrets | Random synthetic passwords were held in temporary files/process environment and were not written to evidence |
| Session cleanup | One-use tickets consumed; context cleared; pools closed; zero residual context/tickets |
| Audit | Three successful routes produced three minimal `CONTEXT_TRANSACTION_READY` allow events |

No critical or high issue was found in the implemented local scope. The main remaining risk is governance of future real identity/family/student mappings, which remains fail-closed.

## 7. Commit and remote state

Implementation commit: `d7affca0068749df8ad7dc563a22bdae7742a664`.

Private-branch synchronization and the final report commit are recorded in the execution handoff. No public origin, merge or PR is used.

## 8. Remaining HOLD and unique next action

Still HOLD:

- creation of any real `auth.external_identities` or VERIFIED family mapping row;
- VERIFIED `STUDENT_PROFILE` mapping authority and any Canonical-source student DTO;
- explicit runtime enablement with protected non-synthetic credentials;
- Tencent update, real identity integration and all production use;
- legacy/real-data migration.

**Unique next action:** prepare the per-record operator/evidence package and controlled registration runbook for the first real application identity plus family mapping, without creating the record. Actual registration remains a separate Founder-reviewed action because it introduces real identity data.
