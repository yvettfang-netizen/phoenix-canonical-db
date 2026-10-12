# Phoenix Canonical PostgreSQL Phase 2B — isolated access-boundary start

**PHASE 2B SYNTHETIC ACCESS PROBE = PASS** · **BUSINESS SCHEMA / TRUSTED IDENTITY = HOLD**

Executed locally on 2026-10-12 (Asia/Shanghai) in the existing isolated worktree. The repository contains no separately approved Phase 2B specification, so this start is limited to the contract-neutral access boundary already allowed by the Phase 2A gate. It does not treat review candidates as effective contracts.

## Actual execution

The new `tests/trusted_context_probe.sql` (SHA-256 `926041190031ad978495cd6051864d1f0ecde3bb8c31d902e50786d7ba6f20cf`) ran through the existing nondestructive `probe` action on PG16 and PG17. Both returned `PASS`. It creates only disposable synthetic tables and an RLS policy inside a transaction, then rolls back. The runner confirms the probe schema is absent afterward.

| Check | PG16.15 | PG17.11 |
|---|---|---|
| Healthy internal-only Compose service | PASS | PASS |
| Unbound application role reads no resource | PASS | PASS |
| Caller-forged family/partner session settings do not grant or change scope | PASS | PASS |
| Application role cannot read or update the protected context table | PASS | PASS |
| Bound family sees only its resource; unassigned advisor sees none; bound partner sees only its resource | PASS | PASS |
| Revoked or expired protected context denies on the next query | PASS | PASS |
| Disposable schema absent after probe | PASS | PASS |

Catalog readback on both development databases still shows only Canonical `0001` and `0002`, **zero domain tables**, and **zero domain RLS policies**. No new migration was applied. Existing PostgreSQL roles, empty schemas, backups, and mock storage were not changed. Docker Compose publishes no host port; `5432/tcp` in `ps` is internal to each container.

## Evidence limit and next gate

The test's bootstrap role simulates a trusted binder for the current database backend. There is no implemented or verified web login, signed identity assertion, request-scoped connection cleanup, token handling, or production audit path. This probe proves only that PostgreSQL can enforce a protected context while ignoring arbitrary client session settings. It is not a deployable authorization design.

Before a business-table migration or formal RLS acceptance, close the Family Context and Document/Submission contract decisions in `phase2-gate/PHASE2A_START_GATE.md`, settle `auth`/`core` and `docs`/`documents` ownership, obtain domain field/state approvals, and implement and test a real trusted application binding. Founder OS freeze evidence remains on HOLD. No real records, old-data migration, Tencent server, production secret, COS, push, merge, or deployment were used.
