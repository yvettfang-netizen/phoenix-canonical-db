# M0 Migration Manifest

| Order | File | Purpose | SHA-256 |
|---:|---|---|---|
| 0030 | `migrations/canonical/0030_m0_organization_identity_governance.sql` | Organization public IDs, identifier/relationship/name history, immutable events, controlled APIs and ACL/RLS. | `c0559ba97ad9edeaa8cb6559b9d382030e27ef4c9a109e97ab7ea99c43eb2d2e` |

Runner expectations after M0: 30 migration files = 30 ledger rows; 77 base tables; 68 RLS policies. The runner holds the existing advisory lock, records the file digest in the same transaction and refuses missing, extra or changed files.

Historical migrations `0001`–`0029` are not modified by M0.
