# Codex Instruction Migration 0022 after Learning Contract Approval V1.0

**Status:** READY BUT BLOCKED

**Start condition:** signed `FOUNDER_DECISION_LEARNING_0022_V1.0.md` approving the exact SHA-256 of `LEARNING_CORE_SOURCE_CONTRACT_DRAFT_V1.0.md`

## Boundaries

1. Work only in `codex/canonical-postgresql-phase1`.
2. Do not modify Migration 0001–0021.
3. Create exactly one new forward migration beginning with `0022_`.
4. Use only synthetic data and isolated local PG16/PG17 environments.
5. Do not read or import legacy Learning, Education Compass, Operations, ASKWISE, Founder OS, Feishu, or customer data.
6. Do not connect to Tencent, deploy, push, merge, change a PR, or delete historical volumes.
7. Stop 0022 and report HOLD if the approved decision changes identity, Consent, read-audit, entitlement, publication, or packaging rules without a corresponding contract revision.

## Required implementation

1. Add the approved auth, Consent, guardian-scope, and context-channel vocabulary with forward constraint replacement.
2. Add `learning` and only the tables listed in the approved contract.
3. Reuse `operations_ref.has_valid_entitlement`; do not create an entitlement copy.
4. Add controlled write and audited read functions with fixed `search_path`, signature-specific grants, and PUBLIC revoked.
5. Enable and force RLS on every Learning table. Runtime roles receive no direct DML or sensitive table SELECT.
6. Enforce terminal history, family/subject integrity, assignment scope, capacity, schedule overlap, card publication, and retraction.
7. Update migration-count, table-count, restore, security-catalog, owner-transfer, archive, and deployment-package count assertions without executing deployment.

## Required acceptance

- Run full F10 on PG16 and PG17 with `APPLIED 0022` present.
- Run permanent Learning positive and negative tests using separate LOGIN accounts and one-time tickets.
- Preserve all historical regression results.
- Produce least-privilege backup, verify manifest, restore into fresh PG16 and PG17 clusters, and rerun the complete suite.
- Apply 0022 forward to existing local development databases only after disposable acceptance passes.
- Verify zero Learning business rows in the local development databases.

## Deliverables

- Migration 0022 and SHA-256;
- permanent Learning regression and restore tests;
- raw PG16/PG17 F10, audit, backup, restore, local migration, repeat, probe, and catalog evidence;
- updated inventory, access matrix, risk register, numbering addendum, and README;
- `FIX_EXECUTION_REPORT_V1.15.md`;
- local implementation and report commit hashes.
