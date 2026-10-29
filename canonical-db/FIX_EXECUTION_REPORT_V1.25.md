# Phoenix Canonical PostgreSQL — FIX EXECUTION REPORT V1.25

- **Execution window:** 2026-10-28 to 2026-10-29 (Asia/Shanghai)
- **Execution owner:** Codex
- **Founder authorization:** approved in the current chat for `PHOENIX_FAMILY_OS`, VERIFIED family mapping authority, binder-only atomic resolution, the first three read-only routes and controlled real identity registration/disablement
- **Scope:** local Migration `0023`, application gateway integration, PG16/17 synthetic acceptance and local development upgrade
- **Result:** `PASS (LOCAL 0023 + PG16/17 + APP GATEWAY) / HOLD (LIVE ROUTES, REAL RECORDS, TENCENT)`

## 1. Boundary confirmation

- Work was performed only in `codex/canonical-postgresql-phase1`.
- No Tencent connection, deployment, restart or server file change was made.
- No production key, real identity, real family mapping, customer record, legacy import or Feishu data was read or written.
- No public remote, merge or PR was used.
- Migrations `0001`–`0022` were not modified. The change is forward-only Migration `0023`.
- `CANONICAL_CONTEXT_GATEWAY_ENABLED=false` remains mandatory; the three routes were not wired into live HTTP handlers.

## 2. Founder-approved decisions implemented

| Decision | Implemented control |
|---|---|
| Application source namespace | Fixed internally to exact `PHOENIX_FAMILY_OS`; caller cannot choose another source |
| Family mapping authority | Exact `integration.legacy_id_mappings` row with kind `FAMILY` and status `VERIFIED` |
| Atomic resolver | One binder-only SECURITY DEFINER call resolves identity, FAMILY principal/person, mapping and current membership, then issues the ticket |
| Initial route scope | Existing allowlist remains exactly the three approved family-owned GET reads |
| Identity lifecycle | Existing controlled SERVICE registration/disablement functions remain the only write path; no auto-provisioning |

No real identity or mapping row was created. Approval of the process is not approval of any future real record.

## 3. Migration 0023

Artifact: `migrations/canonical/0023_application_family_context_resolver.sql`

`auth.issue_application_family_context_ticket(...)` now:

1. accepts only a verified broker `issuer`, controlled `usr_*` subject and `fam_*` application family ID;
2. fixes the mapping source to `PHOENIX_FAMILY_OS` inside the function;
3. requires an ACTIVE external identity and ACTIVE `FAMILY` principal with a person;
4. requires one VERIFIED family mapping whose Canonical target is a real `core.families` row;
5. requires a current family membership for the resolved actor;
6. locks the matched identity/principal/mapping/membership rows during issuance;
7. issues a ≤60-second, one-use `FAMILY` context ticket through the existing validated ticket function;
8. returns no row for unresolved or malformed input, avoiding a mapping oracle;
9. revokes execution from PUBLIC, app and reader roles and grants only the binder role.

SHA-256: `e5587c58895495097dea033f25cecfce67661eb0a6aede15821bdf115633f720`.

## 4. Application integration

- `canonical-application-route-bridge.ts` no longer accepts or injects a separate actor/family mapping object.
- The bridge derives only the authenticated `usr_*` subject and trusted Store-owned `fam_*` ID, issues the internal token, and calls the atomic gateway path.
- `canonical-context-gateway.ts` verifies the token and performs exactly one binder query to the 0023 function before app-pool redemption.
- Canonical actor/family UUIDs are database outputs; they cannot come from request headers, query/body fields or application mapping files.
- The existing one-use redemption, transaction fence, `clear_context`, audit and `DISCARD ALL` behavior is preserved.

Application command: `npm.cmd test`.

Result: `116/116 PASS` including atomic binder call, mapping denial before app-pool use, route ownership denial, transaction control rejection and protected audit checks.

Raw evidence: `evidence/v1.25-application-gateway-tests.txt`  
SHA-256: `044453820744d055be846614c5e79bb75cac03c0f538baf6450c0c4451b58046`.

## 5. PG16 / PG17 acceptance

Both versions ran in disposable containers with `--network none`, no host ports, synthetic random credentials and separate binder/app/backup LOGIN accounts.

| Verification | PG16 | PG17 |
|---|---:|---:|
| Fresh 0001–0023 apply | PASS | PASS |
| Repeat apply / checksum lock | PASS | PASS |
| Missing/extra Migration refusal | PASS | PASS |
| Drift refusal / forced atomic rollback | PASS | PASS |
| 0023 positive atomic resolution | PASS | PASS |
| Wrong family/source, PENDING, REVOKED, malformed, expired membership and disabled identity denial | PASS | PASS |
| App/PUBLIC execute denial; binder execute grant | PASS | PASS |
| Split LOGIN redemption and ticket reuse denial | PASS | PASS |
| Dedicated backup LOGIN export | PASS | PASS |
| Manifest-verified fresh-cluster restore | PASS | PASS |
| Restored catalog | 23 ledger / 50 tables / 41 RLS | 23 ledger / 50 tables / 41 RLS |
| Network/ports | `none` / `{}` | `none` / `{}` |

Raw evidence:

- `evidence/v1.25-0023-pwsh-f10-pg16.txt` — SHA-256 `e6c3ee94badf138df07a36e86b5dcf80cfc8a3f8974fd492df408b36cf5e9c13`
- `evidence/v1.25-0023-pwsh-f10-pg17.txt` — SHA-256 `9f1877b3b7bcf9dac43e18660128e9b64cb66b7de0a537b03df938937c53037c`

The exact disposable containers, anonymous volumes and synthetic env files were removed after each run.

## 6. Local development upgrade

The existing isolated local PG16 and PG17 development databases applied `0023`; repeat migration reported checksum-verified SKIP, health reported accepting connections, and non-destructive transactional probes passed on both versions.

Raw evidence: `evidence/v1.25-local-upgrade-health.txt`  
SHA-256: `a2eb56e80b5d42fcce30a7eb8f766378a140ec25215d76e04369ce0b90343084`.

No real identity, family mapping or business row was inserted into the development databases.

## 7. Security review

| Severity | Result |
|---|---|
| Critical | None found in the implemented local scope |
| High | None found in the implemented local scope |
| Medium | Live HTTP response mapping and real record governance remain disabled/HOLD rather than inferred |
| Low / operational | Runtime enablement still depends on protected credentials, real record evidence and isolated end-to-end review |

Identity, authorization, least privilege, RLS/tenant isolation, secret handling, auditability, negative tests and restore behavior were exercised. No credential material was found in the V1.25 artifacts.

## 8. Commit and remote state

Implementation commit: `81700085432113d125624b885361e0951301e313`.

Before this commit, local HEAD and the existing private branch `canonical-private/codex/canonical-postgresql-phase1` both pointed to `fb187a61a9f07d3ab94da06682493fd06e9a1494`. The report commit and private synchronization are recorded in the final execution handoff.

## 9. Remaining HOLD and unique next action

Still HOLD:

- real `auth.external_identities` and VERIFIED family mapping rows;
- the operator/evidence package for each real mapping;
- HTTP handler wiring and exact application DTO response-field conversion;
- explicit runtime enablement and real identity end-to-end testing;
- Tencent update and all production use.

**Unique next action:** define and review the exact response-field mapping for the three approved read routes, then run an isolated local HTTP → broker → binder → app-pool → RLS end-to-end test with synthetic records. Deployment remains a later gate.
