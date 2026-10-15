# Phoenix Canonical PostgreSQL — Phase 3 execution report

**Executed:** 2026-10-14 (Asia/Shanghai)  \
**Result:** `PHASE 3 GREENFIELD CANONICAL DATABASE = PASS`  \
**Legacy migration:** HOLD  \
**Tencent deployment:** PASS for the isolated empty database; see `TENCENT_DEPLOYMENT_EXECUTION_REPORT.md`

## Effective scope

The missing historical Family Context original was not fabricated. A new prospective contract, `phase2-gate/CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md`, is effective for the greenfield Canonical database. Its approval hash and scope are recorded in `phase2-gate/PHASE3_APPROVAL_REGISTER.md`. Historical ID and data reuse remain excluded.

## Completion audit — 2026-10-14

| Area | Status | Evidence or remaining gate |
|---|---|---|
| Greenfield Canonical schema (`core`, `consent`, `audit`, `integration`, `docs`, `casework`, `education`, `identity`) | PASS | Six checksum-locked migrations; 24 tables; 20 RLS policies on PG16/17 |
| Migration repeat, atomicity and drift refusal | PASS | Local PG16/17 audit actions passed |
| Access isolation and consent/guardian/document rules | PASS | Local PG16/17 synthetic probes passed |
| Backup digest, tamper refusal and restore rehearsal | PASS | Local PG16/17 audit-backup passed; Tencent backup manifest and archive listing verified |
| Tencent isolated runtime | PASS | PG16.15 healthy; deployment files and migration hashes match local |
| Historical Family Context and Founder OS freeze integration | HOLD | Original effective evidence is unavailable; the greenfield contract remains bounded |
| Legacy ID reconciliation and real-data migration | HOLD | Requires recovered source records and an approved mapping decision |
| Private object storage and real document bytes | HOLD | Mock storage only; retention/location contract remains unapproved |
| Web authentication, application integration and production cutover | HOLD | Application-owned token/context integration and release approval are pending |

## Actual database catalog

| Evidence | PostgreSQL 16 | PostgreSQL 17 |
|---|---:|---:|
| Engine | 16.15 | 17.11 |
| Applied checksum-locked migrations | 6 | 6 |
| Canonical business tables | 24 | 24 |
| RLS policies | 20 | 20 |
| Persistent domain rows after acceptance | 0 | 0 |
| Context binder | NOLOGIN, non-superuser | NOLOGIN, non-superuser |

Schemas: `auth`, `core`, `consent`, `audit`, `integration`, `docs`, `casework`, `education`, `identity`, plus the migration ledger.

## Implemented tables

- `auth`: principals, backend-bound trusted session contexts.
- `core`: people, families, family memberships, student profiles, guardian authorities.
- `consent`: scoped grants with withdrawal/expiry enforcement.
- `integration`: public IDs, source-qualified legacy mappings, subject-specific channel grants.
- `audit`: append-only access decision events through controlled functions.
- `casework`: generic cases and time-bounded advisor assignments.
- `education`: applications, status events, external official facts.
- `identity`: cases, status events, external official facts.
- `docs`: documents, immutable versions, submission manifests and pinned items.

## Executed acceptance

Both engines passed fresh initialization, repeat migration, checksum drift refusal, forced atomic rollback, UUIDv7 rejection, source-qualified ID uniqueness, family RLS, cross-family denial, advisor assignment and Consent enforcement, advisor overreach denial, channel cross-subject and cross-family denial, Consent withdrawal, guardian expiry, document version immutability, submitted-manifest immutability, withdrawal/new-submission refusal, prior snapshot preservation, Legal Hold purge refusal, trusted context anti-forgery, context clear/rebind, denial audit events, backup digest/provenance tamper refusal, valid database restore, and Mock object backup/restore.

Application, reader and binder local logins were authenticated independently on PG16 and PG17 and checked for least privilege. The application role cannot execute the context-binding function or read its private table.

## Remaining release boundaries

- No legacy IDs or real records have been reconciled or imported.
- No Founder OS, Operations OS, Feishu, D1 or old `phoenix_core` data is reused.
- Document bytes are not deployed; Tencent Phase 3 contains metadata tables only until a private object-store gate is approved.
- Web authentication and token validation remain application responsibilities. PostgreSQL accepts only the separately bound trusted context.

**Phase 3 database verdict:** PASS for a new empty Canonical deployment, including the isolated Tencent runtime. Existing production data and application cutover are not approved by this report.
