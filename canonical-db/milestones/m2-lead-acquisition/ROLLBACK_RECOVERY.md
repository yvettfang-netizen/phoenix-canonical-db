# M2 Rollback & Recovery

M2 is forward-only. Rollback stops new M2 writers and retains additive history; any correction is a later migration. No Lead, attribution, referral or merge history is deleted.

PG16/17 acceptance exports through the backup LOGIN, verifies the dump manifest, restores a fresh isolated cluster and rechecks the 32-row ledger, 85 tables, 76 policies, four-Compass attribution, merge/reversal, referral history and exact ACLs.
