# Phoenix Canonical PostgreSQL — Phase 2C / Phase 3 execution gates

**Status:** Phase definitions authorized by the Founder's 2026-10-12 instruction. Phase 2C passed on PG16/17 on 2026-10-14; see `../PHASE2C_EXECUTION_REPORT.md`. This file defines work boundaries and acceptance; it does **not** approve the unresolved Family Context, Document/Submission, Founder OS, or domain contracts.

## Phase 2C — local synthetic negative-acceptance closure

**Entry:** Phase 2B audit PASS for the isolated PG16/17 foundation; existing `0001`/`0002` checksums intact; only synthetic data and disposable test objects. This entry is satisfied.

**Execution result:** PASS on PostgreSQL 16.15 and 17.11. Withdrawal/new-submission refusal, existing snapshot preservation, legal-hold purge refusal, pooled-session clear/rebind, atomic migration rollback, migration checksum drift refusal, dump/manifest tamper refusal, valid restore and probe cleanup all passed with synthetic data.

**Scope:** Extend disposable tests for document withdrawal versus prior submitted evidence, legal-hold purge refusal, pooled-session context clearing/rebinding, migration checksum-drift refusal, and backup provenance/tamper refusal. Run on PG16 and PG17. Keep the eight domain schemas empty and leave the Canonical migration ledger at `0001`/`0002`. Do not create production-like identity, family, Consent, document, Education Application, or Identity Case tables.

**Exit:** Every negative case returns the expected denial on both versions; allowed prior snapshots remain intact; rollback leaves no probe object; backup refusal leaves restore-test databases intact; report identifies test-only mechanisms and missing formal contracts. **PASS** applies only to synthetic test harness behavior.

**Stop:** Any probe creates a persistent business table, uses real data/storage/credentials, changes an applied migration, or requires an unresolved business decision. Stop that item and record HOLD rather than choosing a contract value.

## Phase 3 — approved Canonical business-schema build and formal acceptance

**Entry is conditional and currently HOLD.** Before any dependent `0003+` migration, collect and hash the original Family Context V1, record an effective approved amendment resolving FC-1 through FC-5, decide `auth` versus `core` principal ownership and UUIDv7/public/legacy mapping, approve the Document/Submission contract resolving DS-1 through DS-5, approve Education/Identity field lists and states, and specify trusted application identity binding. Founder OS freeze original plus D1 reconciliation is required for any Founder/Operations ID or data reuse. Every approval record needs approver, date, exact file hash and changed clauses.

**Execution sequence after entry:**

1. Draft new Canonical migrations from the effective contracts, with one master per natural person and no reuse of old `006` or PR #14 migration numbers. Review the actual SQL and the role/RLS matrix before applying it.
2. Apply on fresh synthetic PG16 and PG17 databases; verify repeat checksum safety, foreign keys, uniqueness, source-qualified ID mapping, and transaction rollback. Apply to isolated development only after these checks pass.
3. Test actual business-table RLS through a trusted application session: cross-family, advisor, partner, Consent withdrawal, guardian expiry, and forged context denial. Verify denial audit records.
4. Test immutable document versions, submitted manifest snapshots, withdrawal and legal hold against final tables and local mock storage. Verify database and object backup/restore together with synthetic records.
5. Report each domain as PASS, CONDITIONAL, or HOLD with catalog readback and test evidence. Do not equate an approved design with an applied migration.

**Phase 3 exit:** PG16/17 formal business acceptance passes for the approved scope; the exact applied migration list, tables, RLS policies, role grants, negative tests and restore results are documented. Any failed or unapproved domain remains HOLD. The Founder's 2026-10-14 instruction authorizes Tencent deployment only after all stages are complete. That deployment condition is not satisfied while the Phase 3 entry remains HOLD; real-data migration, COS, push and merge remain outside scope.
