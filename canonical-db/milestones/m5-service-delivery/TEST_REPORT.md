# M5 Test Report

Synthetic-only; no production/Tencent connection or secret.

| Gate | PG16 | PG17 |
|---|---|---|
| Fresh 0001–0035 | PASS | PASS |
| Existing local 0034 → 0035 upgrade / health | PASS | PASS |
| Repeat / 35-file = 35-ledger assertion | PASS | PASS |
| Missing/extra/checksum drift refusal | PASS | PASS |
| Forced atomic rollback | PASS | PASS |
| Existing F10 + M5 split-LOGIN regression | PASS | PASS |
| One-use ticket, tenant/RLS/ACL negative cases | PASS | PASS |
| Task transfer + template + version-bound delivery lifecycle | PASS | PASS |
| Manifest-verified fresh restore + restored M5 regression | PASS | PASS |

Evidence: `evidence/v2.0-m5-0035-pwsh-f10-pg16.txt`, `...pg17.txt`, and matching audit-log, audit-db-ids and audit-reconcile files.

Final engineering result: `PASS`; both isolated restores reported 35 ledger rows, 92 tables and 83 policies.
