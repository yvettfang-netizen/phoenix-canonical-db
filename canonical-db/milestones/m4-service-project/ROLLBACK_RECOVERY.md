# M4 Rollback & Recovery

M4 is forward-only. Rollback disables M4 writers and retains parties, authorizations, subjects, assignments and events. Corrections use a later Migration; terminal history is not deleted or reactivated.

PG16/PG17 acceptance exports through the backup LOGIN, verifies the manifest, restores a fresh isolated cluster and rechecks 34 ledger rows, 90 tables, 81 policies, closed-project authority shutdown and exact ACLs.
