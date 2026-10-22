# Canonical Schema Actual Inventory V1.15

**Verified:** 2026-10-22 against local PG16 and PG17 `phoenix_canonical_dev`  
**Scope:** Founder-approved local Migration 0022; synthetic data only  
**Deployment status:** local isolated development only; Tencent task B remains paused.

## Catalog

| Item | Actual |
|---|---:|
| Canonical migrations | 22 (`0001`–`0022`) |
| Business tables | 50 |
| RLS policies | 41 |
| Learning tables | 14 |
| Learning rows in each local development database | 0 |

Migration 0022 adds the `learning` schema and these tables:

- `course`, `course_version`, `teacher`, `class`
- `enrollment`, `enrollment_status_event`, `enrollment_class`
- `teacher_assignment`, `schedule_slot`
- `attendance_record`, `attendance_correction`
- `after_class_card`, `publication`, `stage_report`

It adds no Learning copy of entitlement or order data. Enrollment checks reuse `operations_ref.has_valid_entitlement`.

## Enforced boundaries

- Staff contexts use `TEACHER` or `SUPERVISOR` principals on the `STAFF` channel.
- Teacher access requires an effective assignment and current `LEARNING_RECORD` Consent for the subject.
- Course entitlement validates enrollment only and never creates Consent.
- Teachers submit cards and reports; supervisors publish or retract cards.
- Schedule overlap is rejected with a `btree_gist` exclusion constraint.
- Terminal and historical records cannot be silently rewritten or reactivated.
- All 14 Learning tables have forced RLS and deny direct runtime reads; reads and writes use controlled, audited functions.
- Family and staff reads remain bound to the current family and subject.

## Hashes and evidence

| Item | SHA-256 / path |
|---|---|
| Approved source contract | `3a3c95d671dfd66c872ffb61c4855bb04eff6dabdb8a41f1c61a44f5ba43fc16` |
| `0022_learning_core.sql` | `4df4b55cc9b2830c357d676906a77a9fa7ac981bbe4673c156285aa40fba2f5f` |
| Bash PG16 / PG17 | `evidence/v1.15-0022-f10-pg16.txt`, `evidence/v1.15-0022-f10-pg17.txt` |
| PowerShell PG16 / PG17 | `evidence/v1.15-0022-pwsh-f10-pg16.txt`, `evidence/v1.15-0022-pwsh-f10-pg17.txt` |
| Local zero-row catalog | `evidence/v1.15-0022-local-zero-catalog-pg16.txt`, `evidence/v1.15-0022-local-zero-catalog-pg17.txt` |

