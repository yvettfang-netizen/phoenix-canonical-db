# M1 Test Report

Synthetic-only; no production/Tencent connection or secret.

| Gate | PG16 | PG17 |
|---|---|---|
| Fresh 0001–0031 | PASS | PASS |
| Existing local 0030 -> 0031 upgrade / health | PASS | PASS |
| Repeat / 31-file = 31-ledger assertion | PASS | PASS |
| Missing/extra/checksum drift refusal | PASS | PASS |
| Forced atomic rollback | PASS | PASS |
| Existing F10 + split-LOGIN M1 positive/negative | PASS | PASS |
| Manifest-verified fresh-cluster restore + ACL/RLS | PASS | PASS |

Evidence:

- `evidence/v2.0-m1-0031-pwsh-f10-pg16.txt`
- `evidence/v2.0-m1-0031-pwsh-f10-pg17.txt`
- `evidence/v2.0-m1-0031-pwsh-audit-db-ids-pg16.txt`
- `evidence/v2.0-m1-0031-pwsh-audit-db-ids-pg17.txt`
- `evidence/v2.0-m1-0031-pwsh-audit-reconcile-pg16.txt`
- `evidence/v2.0-m1-0031-pwsh-audit-reconcile-pg17.txt`

Final engineering result: `PASS`; both isolated restore runs reported 31 ledger rows, 81 tables and 72 RLS policies.
