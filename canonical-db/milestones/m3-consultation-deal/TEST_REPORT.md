# M3 Test Report

Synthetic-only; no production/Tencent connection or secret.

| Gate | PG16 | PG17 |
|---|---|---|
| Fresh 0001–0033 | PASS | PASS |
| Existing local 0032 → 0033 upgrade / health | PASS | PASS |
| Repeat / 33-file = 33-ledger assertion | PASS | PASS |
| Missing/extra/checksum drift refusal | PASS | PASS |
| Forced atomic rollback | PASS | PASS |
| Existing F10 + M3 split-LOGIN regression | PASS | PASS |
| Manifest-verified fresh restore + ACL/RLS | PASS | PASS |

Evidence: `evidence/v2.0-m3-0033-pwsh-f10-pg16.txt`, `...pg17.txt`, and matching audit-log, audit-db-ids and audit-reconcile files.

Final engineering result: `PASS`; both isolated restores reported 33 ledger rows, 89 tables and 80 policies.
