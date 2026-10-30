# M3 Rollback & Recovery

M3 is forward-only. Rollback disables M3 writers and retains Consultation, Deal, assignment and event history; corrections use a later Migration. No lifecycle history is deleted.

PG16/PG17 acceptance exports through the backup LOGIN, verifies the dump manifest, restores a fresh isolated cluster and rechecks 33 ledger rows, 89 tables, 80 policies, M3 synthetic lifecycle rows and exact ACLs.
