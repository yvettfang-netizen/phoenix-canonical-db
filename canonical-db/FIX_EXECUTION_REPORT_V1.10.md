# Phoenix Canonical PostgreSQL — 0018 Fix Execution Report V1.10

**Execution date:** 2026-10-19
**Scope:** Founder-approved N-2 and D-2, local isolated development only
**Verdict:** **PASS**
**Production / Tencent status:** **HOLD — not connected, not deployed**

## 1. Approval and boundary

The Founder approved both items named in the preceding gate:

- **N-2:** promote the verified E-R6 candidate into formal Migration 0018;
- **D-2:** remove the context binder capability role's access to the legacy direct `auth.bind_context` entry point.

The approval record is `release/v1.9/FOUNDER_APPROVAL_0018_N2_D2_2026-10-19.md`.

No Tencent connection, deployment, push, merge, pull request change, real-data import, historical-volume deletion, N-3 lifecycle change, or D-1/D-1b ownership change occurred. Task B remains **PAUSED**.

## 2. Delivered migration

| Item | Result |
|---|---|
| File | `migrations/canonical/0018_advisor_session_scope_and_binder_hardening.sql` |
| SHA-256 | `063f8ba5b57de24208579369ce75424526737953319544d0174c5a31e3f5d74b` |
| E-R6 | `core.can_read_subject_basics`, `casework.is_current_advisor_for_case`, and `assignments_read` now require the case to be `OPEN` or `PAUSED` for advisor access |
| D-2 | `phoenix_canonical_context_binder` no longer has `EXECUTE` on the legacy `auth.bind_context` function |
| Preserved binder APIs | One-time ticket issuance and external-identity resolution remain available |
| Frozen history | 0001–0017 unchanged |

The final verification output proves that the E-R6 portion is equivalent to the previously tested candidate and that 0001–0017 have no working-tree changes:

- `evidence/v1.10-0018-final-verification.txt`

## 3. Permanent regression changes

| File | Purpose |
|---|---|
| `tests/f10_v19_e_r6_repro.sh` | E-R6 closed-case, cross-family, revoked-assignment, expired-assignment and expired-context behavior; now a permanent F10 gate |
| `tests/f10_v20_0018_acl.sh` | Separate LOGIN proof that binder direct bind is denied while ticket and identity APIs remain available |
| `tests/f10_v20_0018_restore_regression.sql` | Post-restore catalog proof for the E-R6 status gates and D-2 privilege boundary |
| `tests/phase3_acceptance.sql` | Replaced legacy binder direct binding in positive tests with one-time ticket issuance and redemption |
| `tests/f10_ephemeral_init.sh` | Default migration inventory raised to 18 |
| `tests/f10_ephemeral_restore.sh` | Restore expectations raised to 18 and the 0018 restore regression added |
| `tests/f10_local_acceptance.ps1`, `.sh` | 0018 inventory, missing/extra migration, E-R6 and D-2 regression coverage |
| `scripts/db.ps1` | Local binder check now requires direct bind denial and retained ticket/identity capabilities |

## 4. Executed acceptance

### 4.1 Full F10 — PowerShell path

Commands:

```text
pwsh -NoProfile -File tests/f10_local_acceptance.ps1 -Version 16
pwsh -NoProfile -File tests/f10_local_acceptance.ps1 -Version 17
```

| Version | Result | Raw output |
|---|---|---|
| PostgreSQL 16 | PASS | `evidence/v1.10-0018-pwsh-f10-pg16.txt` |
| PostgreSQL 17 | PASS | `evidence/v1.10-0018-pwsh-f10-pg17.txt` |

### 4.2 Full F10 — Git Bash path

Commands:

```text
tests/f10_local_acceptance.sh 16 evidence/v1.10-0018-bash-f10-pg16.txt
tests/f10_local_acceptance.sh 17 evidence/v1.10-0018-bash-f10-pg17.txt
```

| Version | Result | Raw output |
|---|---|---|
| PostgreSQL 16 | PASS | `evidence/v1.10-0018-bash-f10-pg16.txt` |
| PostgreSQL 17 | PASS | `evidence/v1.10-0018-bash-f10-pg17.txt` |

Both paths proved:

- 0018 applied and registered with the expected SHA-256;
- repeat migration was safe;
- extra and missing migration inventories were rejected;
- checksum drift and forced atomic failures were rejected;
- E-R6 completed with `findings=0`;
- binder direct bind returned `permission denied`;
- ticket issuance, identity resolution, ticket redemption and context clearing remained available to the intended capability roles;
- the dedicated backup LOGIN created a mode-600 dump;
- a new PG16 and PG17 cluster restored to 18 ledger rows, 27 tables and 20 RLS policies;
- post-restore 0018 catalog assertions passed;
- source and restore containers used `network=none` with no host port bindings;
- disposable containers and volumes were removed.

### 4.3 Existing local development databases

Commands:

```text
pwsh -NoProfile -File scripts/db.ps1 -Action migrate -Version 16
pwsh -NoProfile -File scripts/db.ps1 -Action migrate -Version 17
pwsh -NoProfile -File scripts/db.ps1 -Action health -Version <16|17>
pwsh -NoProfile -File scripts/db.ps1 -Action provision-local-roles -Version <16|17>
pwsh -NoProfile -File scripts/db.ps1 -Action probe -Version <16|17>
```

| Check | PG16 | PG17 | Evidence |
|---|---:|---:|---|
| 0018 applied | PASS | PASS | `evidence/v1.10-0018-local-migrate-pg16.txt`, `evidence/v1.10-0018-local-migrate-pg17.txt` |
| Health | PASS | PASS | `evidence/v1.10-0018-local-health-roles-probe-pg16.txt`, `evidence/v1.10-0018-local-health-roles-probe-pg17.txt` |
| Local role boundary | PASS | PASS | same files |
| Nondestructive probes | PASS | PASS | same files |
| Ledger | 18 | 18 | `evidence/v1.10-0018-local-catalog-pg16.txt`, `evidence/v1.10-0018-local-catalog-pg17.txt` |
| Tables / RLS policies | 27 / 20 | 27 / 20 | same files |
| Selected domain rows | 0 | 0 | same files |

The running engines reported PostgreSQL `16.15` and `17.11`. Both containers remained internal-only with `5432/tcp` and no published host port.

## 5. Audit evidence

The D-9 server-log reconciliation still passed after 0018:

- PG16: 277 attempts, 276 persisted matches, 1 expected rollback-only attempt;
- PG17: 277 attempts, 276 persisted matches, 1 expected rollback-only attempt.

Raw files:

- `evidence/v1.10-0018-pwsh-audit-log-pg16.txt`
- `evidence/v1.10-0018-pwsh-audit-log-pg17.txt`
- `evidence/v1.10-0018-pwsh-audit-db-ids-pg16.txt`
- `evidence/v1.10-0018-pwsh-audit-db-ids-pg17.txt`
- `evidence/v1.10-0018-pwsh-audit-reconcile-pg16.txt`
- `evidence/v1.10-0018-pwsh-audit-reconcile-pg17.txt`

No credential or private-key marker was found in the V1.10 evidence files. Source `.sh`, `.sql` and `.yaml` files outside ignored runtime/backup directories contain zero carriage-return bytes.

## 6. Local commit and remaining gates

Implementation and raw evidence commit:

`3bb16a3075ca10cb38aeb2f8e091a98369d70752`

Remaining HOLD items:

- Tencent task B and all remote deployment work;
- N-3 case-close assignment lifecycle semantics;
- D-1/D-1b database ownership and restore model;
- 0019 and later scope that depends on unavailable or unapproved source decisions;
- production authentication, rollout and data migration.

**Final result: MIGRATION 0018 LOCAL IMPLEMENTATION AND PG16/PG17 ACCEPTANCE = PASS.**
