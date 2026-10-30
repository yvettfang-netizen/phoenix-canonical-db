# M1 Migration Manifest

| Order | File | SHA-256 |
|---:|---|---|
| 0031 | `migrations/canonical/0031_m1_client_partner_relationships.sql` | `a58d07ffd116a5890c46f6ca13c97034632b0905522ebdf1f464301746043936` |

Expected post-M1 inventory: 31 files = 31 ledger rows, 81 tables and 72 RLS policies. Migration is one transaction and relies on the existing checksum/advisory-lock runner. Historical migrations `0001`–`0030` remain unchanged.
