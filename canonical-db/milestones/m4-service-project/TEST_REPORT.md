# M4 Test Report

Synthetic-only; no production/Tencent connection or secret.

| Gate | PG16 | PG17 |
|---|---|---|
| Fresh 0001–0034 | PASS | PASS |
| Existing local 0033 → 0034 upgrade / health | PASS | PASS |
| Repeat / 34-file = 34-ledger assertion | PASS | PASS |
| Missing/extra/checksum drift refusal | PASS | PASS |
| Forced atomic rollback | PASS | PASS |
| Existing F10 + M4 split-LOGIN regression | PASS | PASS |
| Manifest-verified fresh restore + ACL/RLS | PASS | PASS |

Evidence: `evidence/v2.0-m4-0034-pwsh-f10-pg16.txt`, `...pg17.txt`, and matching audit-log, audit-db-ids and audit-reconcile files.

Final engineering result: `PASS`; both isolated restores reported 34 ledger rows, 90 tables and 81 policies.
