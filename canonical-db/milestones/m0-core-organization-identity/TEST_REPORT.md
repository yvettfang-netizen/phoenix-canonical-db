# M0 Test Report

Scope: synthetic-only, isolated PostgreSQL 16 and 17. No production/Tencent connection or secret is used.

| Gate | PG16 | PG17 |
|---|---|---|
| Fresh 0001–0030 | PASS | PASS |
| Existing local 0029 -> 0030 upgrade / health | PASS | PASS |
| Repeat / 30-file = 30-ledger assertion | PASS | PASS |
| Missing/extra/checksum drift refusal | PASS | PASS |
| Forced atomic rollback | PASS | PASS |
| Existing F10 + M0 split-LOGIN regression | PASS | PASS |
| Backup + fresh-cluster restore + restored ACL/RLS | PASS | PASS |

Primary evidence paths:

- `evidence/v2.0-m0-0030-pwsh-f10-pg16.txt`
- `evidence/v2.0-m0-0030-pwsh-f10-pg17.txt`
- `evidence/v2.0-m0-0030-pwsh-audit-db-ids-pg16.txt`
- `evidence/v2.0-m0-0030-pwsh-audit-db-ids-pg17.txt`
- `evidence/v2.0-m0-0030-pwsh-audit-reconcile-pg16.txt`
- `evidence/v2.0-m0-0030-pwsh-audit-reconcile-pg17.txt`

Final engineering result: `PASS`. Both versions reported 30 ledger rows, 77 tables and 68 RLS policies; both restore containers used `--network none` with no published ports. Founder merge acceptance remains pending.
