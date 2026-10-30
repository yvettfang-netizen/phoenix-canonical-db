# M5 Rollback & Recovery

M5 is forward-only. Rollback disables the 0035 application commands while retaining task transfers, templates, version references and immutable delivery events. Corrections use a later Migration; accepted/withdrawn deliveries and retired templates are never reactivated or deleted.

PG16/PG17 acceptance exports through the dedicated backup LOGIN, verifies the dump SHA-256 manifest, restores a fresh isolated cluster and rechecks 35 ledger rows, 92 tables, 83 policies, version-bound delivery rows, immutable events and exact ACLs.

The manifest is an integrity checksum, not a cryptographic signature. Offsite destination, retention and production RPO/RTO remain outside this local milestone.
