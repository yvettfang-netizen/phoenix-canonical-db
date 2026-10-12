# Phoenix Canonical PostgreSQL — Phase 2A start gate

**Decision:** `PHASE 2A ISOLATED PREPARATION = STARTED`; `PHASE 2 BUSINESS TABLES = HOLD` until the listed approvals. Empty `education` and `identity` schemas and a synthetic mock-store test are now executed; see `../PHASE2A_EXECUTION_REPORT.md`. This gate is for the existing local worktree and synthetic PG16/17 only. It does not approve production, legacy migration, push, merge, or deployment.

## What is verified and available now

- Phase 1 report: PG16.15/PG17.11 local clusters healthy on an internal network with no published host port; checksum-locked `canonical/0001_foundation.sql`; six original empty schemas; restricted local roles; backup and restore tests passed. Phase 2A adds checksum-locked `0002_education_identity_skeleton.sql` and two more empty schemas.
- Synthetic RLS and document-integrity probes pass on both versions and roll back without leaving domain tables.
- Four-Portals original design file and six correction-gate drafts have file hashes recorded; the new migration conflict report independently checks the listed local Git refs and both local database catalogs.
- FD-P1 **conditional design approval** and FD-P5 **technical design approval** are reported in the supplied `00_STATUS_SOURCES_VERDICT.md`. Those are not final Family Context or Docs contract approvals.

## Phase 2A work authorized by the current local-development request

1. Prepare `education` and `identity` boundaries, directory layout, migration tests, and empty schemas without disputed Person/Student/Guardian keys or application/identity case tables.
2. Continue synthetic PG16/17 probes for mapping refusal, trusted-context binding, Consent withdrawal, guardian expiry, document-version immutability, submission snapshots, and negative access. Test-only schemas must roll back.
3. Define a local mock object-store interface and restore test; do not use COS or real documents.
4. Draft exact new migrations only after their own table contract is approved. Keep the old `006` and PR #14 lineages separate and read-only.

## Decisions required before dependent business DDL

| Gate | Required evidence / decision |
|---|---|
| Identity contract | Exact original Family Context V1; approved redline of `FAMILY_CONTEXT_AMENDMENT_V1.1_REVIEW_CANDIDATE.md`; `auth` versus `core` principal ownership; UUIDv7/public/legacy mapping rules |
| Documents contract | `docs` versus `documents`; final manifest ownership and freeze point; retention, deletion, legal-hold authority, storage region; access policy tied to trusted identity |
| Education/Identity | Domain-owner field lists, states, official submission evidence, and business-rule acceptance cases; no invented high-talent A/B/C rules |
| Founder OS / Operations | Exact Founder OS freeze bytes at the named commit, plus reviewed D1 asset/migration reconciliation; Operations remains deferred |

The user can review the four adjacent iteration files without treating any missing original as verified. When a gate is closed, record approver, date, exact file hash, and changed clauses before applying the dependent migration. A file's presence or a design filename containing “Reviewed” is not an approval event.

**Execution boundary:** Phase 2A has begun with isolated scaffolding and synthetic tests. Full business schema/RLS, real data, external storage, and release remain HOLD.

**2026-10-12 continuation:** PG16/17 also passed nondestructive, rolled-back mapping-refusal, Consent-withdrawal, guardian-expiry, and submitted-manifest snapshot probes. See `../PHASE2A_EXECUTION_REPORT.md`. This does not close any contract gate above.
