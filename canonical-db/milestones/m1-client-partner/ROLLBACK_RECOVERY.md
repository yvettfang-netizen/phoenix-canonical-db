# M1 Rollback & Recovery

M1 is additive and forward-only. No destructive down migration is supplied. A release rollback stops new M1 writers and preserves the additive schema/history until a corrective forward migration is approved.

Acceptance exports through the dedicated non-superuser backup LOGIN, validates the SHA-256 manifest, restores roles and data into a fresh network-isolated cluster, then rechecks 31 ledger rows, 81 tables, 72 policies, M1 lifecycle rows and exact ACLs. Evidence is listed in `TEST_REPORT.md`.
