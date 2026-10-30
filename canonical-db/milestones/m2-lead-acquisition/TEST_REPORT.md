# M2 Test Report

Synthetic-only; no production/Tencent connection or secret.

| Gate | PG16 | PG17 |
|---|---|---|
| Fresh 0001–0032 | PASS | PASS |
| Existing local 0031 -> 0032 upgrade / health | PASS | PASS |
| Repeat / 32-file = 32-ledger assertion | PASS | PASS |
| Missing/extra/checksum drift refusal | PASS | PASS |
| Forced atomic rollback | PASS | PASS |
| Existing F10 + M2 split-LOGIN regression | PASS | PASS |
| Manifest-verified fresh restore + ACL/RLS | PASS | PASS |

Evidence: `evidence/v2.0-m2-0032-pwsh-f10-pg16.txt`, `...pg17.txt`, and matching audit-log, audit-db-ids and audit-reconcile files.

Final engineering result: `PASS`; both isolated restores reported 32 ledger rows, 85 tables and 76 policies.
