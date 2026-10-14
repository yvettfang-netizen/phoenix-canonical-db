# Phoenix Canonical PostgreSQL — Phase 2C execution report

**Executed:** 2026-10-14 (Asia/Shanghai)  
**Result:** `PHASE 2C LOCAL SYNTHETIC NEGATIVE ACCEPTANCE = PASS`  
**Phase 3 entry at execution time:** `HOLD — REQUIRED CONTRACT DECISIONS AND SOURCE EVIDENCE WERE NOT PRESENT`

> Subsequent status: the Founder authorized a new prospective greenfield baseline on 2026-10-14. Phase 3 later passed under that new contract; see `PHASE3_EXECUTION_REPORT.md`. This does not turn the missing historical files into verified originals.

## Executed database evidence

All checks ran against the existing isolated Docker Compose services with synthetic data only. PostgreSQL 16.15 and PostgreSQL 17.11 were healthy. Each development catalog contains exactly the checksum-locked Canonical migrations `0001_foundation.sql` and `0002_education_identity_skeleton.sql`. The eight domain schemas contain zero tables and zero RLS policies. No `acceptance_probe` schema remains after testing.

| Acceptance | PG16 | PG17 | Executed evidence |
|---|---:|---:|---|
| Fresh synthetic test DB and repeat-safe migration | PASS | PASS | Reset allowlisted test DB; applied `0001`/`0002`; repeat run skipped only after checksum match |
| Transactional probe cleanup | PASS | PASS | Every access/document probe rolled back; catalog readback shows no probe schema |
| Withdrawal blocks new manifest | PASS | PASS | Withdrawn document version rejected from new item and from draft-to-submitted transition |
| Existing submitted snapshot survives withdrawal | PASS | PASS | Existing pinned version and digest remained available and unchanged |
| Legal hold blocks Mock object purge | PASS | PASS | Delete rejected and synthetic object row remained present |
| Pooled backend context clear and rebind | PASS | PASS | Cleared backend returned no previous-family row; rebind returned only the second synthetic family |
| Atomic migration failure | PASS | PASS | Forced SQL failure left neither probe schema nor migration-ledger row |
| Applied migration checksum drift | PASS | PASS | Altered copy of `0002` was rejected and registered checksum stayed unchanged |
| Backup dump tamper refusal | PASS | PASS | Appended-byte copy rejected before restore-test reset; guard row remained intact |
| Backup provenance tamper refusal | PASS | PASS | Altered manifest purpose rejected before restore-test reset; guard row remained intact |
| Valid backup restore | PASS | PASS | New manifested custom-format dumps restored into exact allowlisted restore-test DBs and passed foundation assertions |
| Mock object backup/restore | PASS | version independent | SHA-256 content key, deduplication, ZIP restore and restored-content digest passed |

The error printed by the atomicity test is deliberate synthetic failure evidence; the surrounding audit action returned PASS after proving complete rollback.

## What this phase does and does not establish

Phase 2C verifies reusable database-enforcement mechanisms and refusal paths. The withdrawal, legal-hold and trusted-context objects exist only inside rolled-back probe transactions. They are not production business tables, authentication, legal retention policy or external object storage.

No real customer record, old database, Feishu record, Founder OS/D1 asset, Tencent service, COS bucket or production secret was read or written in this phase.

## Phase 3 entry audit

The current repository contains review candidates, not effective contracts. It does not contain the original Family Context V1, an effective amendment resolving FC-1 through FC-5, a final `auth`/`core` and ID mapping decision, a final Document/Submission contract resolving DS-1 through DS-5, approved Education/Identity field and state definitions, or a production trusted-session binding contract. The Founder OS freeze original also remains unavailable and is required before any Founder/Operations ID or data reuse.

Accordingly, no `0003+` business migration can be derived without inventing product semantics. Phase 3 business DDL, formal business-table RLS acceptance, and a production business database remain on HOLD. This report does not count candidate prose or test-only tables as implemented schema.

## Deployment boundary

The tested two-migration empty-domain foundation is technically reproducible. It is not the completed Phase 3 business database. Deployment must remain conditional on the Phase 3 entry evidence listed in `phase2-gate/PHASE2C_AND_PHASE3_EXECUTION_GATES.md`; an authenticated server check is also required to avoid overwriting an existing service or volume.
