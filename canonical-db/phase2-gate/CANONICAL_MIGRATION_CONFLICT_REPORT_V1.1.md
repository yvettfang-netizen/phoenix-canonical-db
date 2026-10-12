# Canonical Migration conflict report V1.1 — independently checked local evidence

**Status:** Verified for the listed **local Git refs and running isolated PG16/17 databases** on 2026-10-12. This is a new report; it does not claim to be the missing original Claude Code Migration conflict report. It does not inspect production databases or real records.

## Direct evidence

| Lineage | Ref / commit | Direct observation | Boundary |
|---|---|---|---|
| New Canonical | `HEAD` at `caa5f6c9137a5053c2cbdc45d0b5dcae778fff0a` before this report | `canonical-db/migrations/canonical/0001_foundation.sql`, SHA-256 `eea8d1deece72afdc3832d075fcfb42b71b4c1fe4fdccc8900104a0e0ca78a2d`; six empty domain schemas and one ledger table | Applied on both local PG16 and PG17; no domain tables |
| Education Compass older identity | `codex/core-identity-consent-v1` at `7e846a18bf864d8dedb7889979fff665d4a405e2` | `server/migrations/006_core_identity_foundation.sql` (Git blob `f0628a42fdc54b4e6bc29efbdb05babb541b80d7`) creates `core.members`, `core.families`, `core.students` with `text` primary keys; this ref also has `007_core_consent_grants.sql` and `008_core_legacy_entity_mappings.sql` | A separate migration lineage; not applied to Canonical |
| PR #14 Family Core sandbox | `origin/pr/14` at `6141d863475f146ec2494ebadd39c447fd38e9f5` | `family-core-sandbox/migrations/0010_core_identity_family.up.sql` (Git blob `1bbc2c896502391780c430a3bd0692b8e9ec8890`) creates `core.members.member_pk uuid`, `core.users.user_id text` constrained to `usr_<32hex>`, `core.families.family_id text` constrained to `fam_<32hex>`, `core.students.student_id text`, and `core.guardians.guardian_id text` | Sandbox lineage; different ownership and ID meaning |
| Current `origin/main` | Existing tracked EC `001`–`005` and Family OS questionnaire `001`; no Canonical migration | No reviewed Canonical ID tables in the base tree | Does not provide a production schema baseline |

Direct SQL catalog readback on both running development databases returned one `canonical_migrations.applied` row (`0001_foundation.sql` with the checksum above) and **zero tables** in `core`, `consent`, `audit`, `integration`, `docs`, and `casework`. Tests on PG16/17 applied `0001` to synthetic test databases, then skipped it on repeat with a checksum match. No legacy `006`, PR #14 sandbox migration, or SQLite migration was executed in these clusters.

## Conflicts that matter for the next migration

| ID | Conflict | Resolution boundary |
|---|---|---|
| MC-1 | Same `core` names carry different keys and concepts: EC `members.id text`, PR #14 `members.member_pk uuid`, and Canonical R2 proposes `people/person_id uuid` | Do not `ALTER` or reuse old tables. Choose the final Person/Principal model in an approved contract before dependent DDL |
| MC-2 | EC `students` and PR #14 `students` are first-class tables, while the amendment candidate treats Student as a Person-linked profile | Keep old IDs as source strings; no automatic `stu_` authority or direct FK |
| MC-3 | PR #14's prefixed text IDs and Canonical proposed internal UUIDv7 keys may look compatible externally while differing internally | Explicit mapping and reconciliation only; no shape-based trust |
| MC-4 | Migration numbers belong to different runners, namespaces, and histories | New files stay in `canonical-db/migrations/canonical/` with checksum ledger; never copy/rename old `006` as a Canonical step |
| MC-5 | R2 drafts use `docs` and `core.principals`; later R3/original design use `documents` and `auth.principals` | Resolve owner/name before a table migration; do not create duplicate masters or silently rename the existing empty `docs` schema |

The supplied `01_ARCHITECTURE_GAP_MATRIX.md`, `06_FEISHU_FIELD_MAPPING.md`, `11_BUNDLE_EVIDENCE_REVIEW.md`, and Operations preservation report contain broader conflict claims about Feishu, Masters `006`, Founder OS SQLite `0002/0004`, and remote data. They are **secondary evidence here**; those claims were not independently reproduced by this local Git/catalog check. In particular, no old database was connected and no real source row was compared.

## Migration gate

1. Preserve `canonical/0001_foundation.sql` byte-for-byte; its applied SHA must continue to match on both engines.
2. Any next migration gets a new number and is first applied to fresh synthetic test DBs on PG16 and PG17, then repeated safely and restored from backup.
3. A table that embodies MC-1, MC-2, MC-3, or MC-5 waits for the approved contract and negative-test specification.
4. Do not migrate Feishu, D1, MySQL, SQLite, UAT, or `phoenix_core` data in this phase.

**Gate:** New isolated migration namespace and test harness = VERIFIED. Business identity and legacy migration = HOLD.
