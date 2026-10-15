# Phoenix Canonical Production Database Solution V1.0 — Technical Draft

**Status:** TECHNICAL BASELINE COMPLETE / PRODUCTION APPROVAL HOLD  
**Scope:** New Canonical PostgreSQL foundation and production-readiness design  
**Database:** `phoenix_canonical_dev` for isolated development and rehearsal  
**Last audited:** 2026-10-14 (Asia/Shanghai)

## 1. What is already implemented

The greenfield Canonical baseline is implemented by six checksum-locked migrations in `migrations/canonical/`:

- `auth`: login principals and server-bound trusted session contexts.
- `core`: the single natural-person master, families, memberships, student profiles and guardian authority.
- `consent`: scoped grants, withdrawal and expiry.
- `audit`: controlled access-decision events.
- `integration`: public IDs, source-qualified legacy mappings and subject-specific channel grants.
- `docs`: document metadata, immutable versions, submission manifests and pinned items.
- `casework`: generic advisor collaboration without duplicating Education Application or Identity Case.
- `education`: applications, status events and external official facts.
- `identity`: identity cases, status events and external official facts.

Current evidence is recorded in `../PHASE3_EXECUTION_REPORT.md` and `../TENCENT_DEPLOYMENT_EXECUTION_REPORT.md`.

## 2. Production target architecture

### 2.1 Runtime and network

- PostgreSQL 16 is the production candidate. PostgreSQL 17 remains a compatibility test target.
- The image is pinned by SHA-256. Tencent Cloud uses the reachable Tencent registry endpoint with the same image digest.
- PostgreSQL is on a private Docker network. No host port mapping for 5432 is allowed.
- The existing host PostgreSQL listener remains bound to `127.0.0.1`; Canonical does not replace or reconfigure it.
- Application traffic must come from an explicitly joined private network or a private tunnel. Public database access is forbidden.

### 2.2 Identity and access

- `core.people` is the only natural-person master in Canonical.
- Internal IDs are application-issued UUIDv7. Public IDs and legacy IDs are separate mappings with source and entity-kind qualifiers.
- The application uses a separate `phoenix_canonical_app` capability. It cannot bind trusted context, change schema, change roles or read the private context table.
- A separate context-binder service performs `auth.bind_context` and `auth.clear_context` only after application authentication.
- RLS requires the bound principal, actor, family, channel, expiry, Consent and authority checks.
- Reader, migrator, binder and backup capabilities remain separate. Bootstrap is installation-only.

### 2.3 Documents and object storage

- PostgreSQL stores metadata, immutable versions, SHA-256 digests, opaque storage keys and submission manifests.
- Private object bytes remain outside PostgreSQL.
- Document version rows and submitted manifests are immutable. Corrections create new versions/manifests.
- Legal Hold, Consent withdrawal, retention expiry and purge authorization are database decisions.
- A real object-store provider, region, retention schedule and deletion authority require the Founder Decision Register before production use.

### 2.4 Migration and release discipline

- The Canonical namespace is independent of old `006` and other migration lineages.
- Applied migration bytes and SHA-256 values are immutable. Any schema change receives a new migration number.
- Every release runs fresh initialization, repeat migration, checksum-drift refusal, atomic rollback, RLS negative tests and backup/restore tests on PG16 and PG17.
- No migration that depends on an unresolved ID, retention, storage or application-auth decision may be created.

### 2.5 Backup, restore and operations

- The deployment backup script writes a unique custom-format dump and a SHA-256 manifest.
- Backup and health checks use container-local sockets and non-bootstrap roles.
- Backup artifacts are mode 600 and must be copied to an approved private backup destination after the storage decision is signed.
- Restore rehearsal must run against an allowlisted disposable database before every production release.
- RPO, RTO, backup retention, restore cadence, alert owner and incident escalation are Founder inputs in the Decision Register.

## 3. Production gates

| Gate | Status | Required closure |
|---|---|---|
| Greenfield schema and RLS | PASS | Six migrations, 24 tables, 20 policies, PG16/17 tests |
| Tencent isolated runtime | PASS | Healthy PG16 container, private network, no public 5432 |
| Family Context final contract | HOLD | Final source or explicit approval of the replacement baseline |
| Founder OS / Operations reuse | HOLD | Exact freeze source and D1/Operations reconciliation, or explicit no-reuse decision |
| Legacy ID reconciliation | HOLD | Source inventory, mapping rules, evidence and conflict handling |
| Documents and Submission final contract | HOLD | DS-1–DS-5 final decisions, retention, storage region and purge authority |
| Education/Identity operational rules | HOLD | Domain-owner field/state/transition approval |
| Application authentication integration | HOLD | Token issuer/audience/JWKS, binder boundary, pool lifecycle and audit owner |
| Production operations | HOLD | RPO/RTO, backup destination, monitoring and rollback approval |
| Real-data cutover | HOLD | All gates above PASS plus a separate cutover approval |

## 4. Implementation after approvals

1. Hash and register the supplied originals.
2. Diff each original against the greenfield baseline and record conflicts.
3. Produce a migration impact plan. Do not alter migrations 0001–0006.
4. Add new migrations only for approved changes, with PG16/17 fresh and repeat tests.
5. Implement the approved private object-store adapter and retention/purge workflow.
6. Integrate the application authentication gateway and trusted context lifecycle.
7. Run synthetic staging rehearsal, backup/restore rehearsal and security review.
8. Obtain the signed cutover gate, then schedule production migration separately.

## 5. Definition of production-ready

Production readiness requires all gates above to be `PASS`, source hashes and approval records to be complete, no unresolved identity or retention conflict, a tested rollback path, a tested restore path, and a separate Founder approval for any real-data import or application cutover.

The current isolated Tencent database is **not** a production cutover. It is the approved empty Canonical runtime and rehearsal target.
