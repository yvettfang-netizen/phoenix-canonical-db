# Phoenix Canonical PostgreSQL Phase 1 evidence report

**Decision: PHASE 1 DATABASE FOUNDATION = HOLD** (2026-10-11)

The isolated branch and database foundation files exist. PostgreSQL initialization, PostgreSQL 17 compatibility, migration execution, security behavior and restore have **not** been run because `docker` is unavailable on this host. The reviewed schema contracts and amendment originals were not present in the current Phoenix repository evidence set. Design files are not counted as built database evidence.

## Repository and source evidence

- Isolated branch: `codex/canonical-postgresql-phase1`, based on local `origin/main` at `846f77c120cd00a49d89635dd4297b020af7d03a`; worktree: `D:\CODEX\01_PHOENIX\01_NOVA\_worktrees\canonical-postgresql-phase1`.
- The source worktree `D:\CODEX\01_PHOENIX\01_NOVA\phoenix` remains on `codex/phoenix-main-post-merge-audit-2026-08-28` with its preexisting untracked `docs/` evidence. The broad Nova workspace has preexisting changes and was not used for edits.
- Read `FOUR_PORTALS_UNIFIED_ARCHITECTURE_V1.1.md` (design candidate), `PHOENIX_CORE_IDENTITY_AND_CONSENT_MINIMUM_CONTRACT_V1.md` (`NEEDS FIX`, migration not approved), `HK_IDENTITY_JOURNEY_SUBMISSION_CONTRACT_DRAFT_V0.1.md` (draft), `README_CLAUDE_HANDOFF.md`, and `FOUNDER_OS_V0.2.1_FREEZE_SOURCE_LOCATOR.md` (locator only). These are under the source worktree's untracked `docs/architecture/` directory.
- **EVIDENCE HOLD:** Claude Code R4 Architecture Gap Review, Canonical PostgreSQL V1.2 Reviewed, Family Context Contract Amendment approval, final Document & Submission Contract, verified Founder OS ID Decision Freeze original, and current migration conflict report were not found in the current repository. The locator identifies a separate exact SHA but does not itself verify the original.

## Implemented versus deferred

| Area | In files | Executed and verified | Gate |
|---|---|---|---|
| Isolated Git branch/worktree | Yes | Yes, local Git command | PASS |
| PostgreSQL 16 Compose and local port | Yes | No Docker CLI | HOLD |
| PostgreSQL 17 compatibility service | Yes | No Docker CLI | HOLD |
| `phoenix_canonical_dev` initialization | Scripted | No Docker CLI | HOLD |
| New canonical migration namespace | `0001_foundation.sql` and checksum runner | Static file only | HOLD |
| `core`, `consent`, `audit`, `integration`, `docs`, `casework` | Empty schema DDL | Not run | HOLD |
| Minimal capability roles | SQL DDL; no login credentials | Not run | HOLD |
| Synthetic test reset and repeat migration | Scripted | Not run | HOLD |
| Backup and restore into exact test database | Scripted | Not run | HOLD |
| Person/Student/Guardian mapping and FK rules | No | No | CONTRACT HOLD |
| Cross-family, advisor and partner denial | No table/RLS contract yet | No | CONTRACT HOLD |
| Consent withdrawal and guardian expiry | No approved identity contract | No | CONTRACT HOLD |
| Immutable document versions/manifests | No final document contract | No | CONTRACT HOLD |

## Migration inventory

| Namespace/file | Purpose | Status |
|---|---|---|
| `canonical/0001_foundation.sql` | Migration ledger, empty schemas, NOLOGIN roles and schema grants | Authored, not executed |

No conflicting old `006` is reused. There are no historical data migrations. The migration runner verifies stored SHA-256 checksums and runs the same SQL safely if interrupted before ledger registration.

## Acceptance run still required

After Docker becomes available, run the commands in `README.md` and retain command output. Required engineering tests still to implement after contract approval are: real FK/uniqueness/ID mapping rules; cross-family, advisor and partner negative access; immediate consent withdrawal and guardian authority expiry; immutable file versions and submission manifests. All fixtures must remain synthetic. The current foundation test checks only schema presence, denied schema creation for app/reader, hidden migration ledger, and repeated migration count.

## Education / Identity next-stage dependencies

1. Obtain the exact R4 review, Canonical PostgreSQL V1.2 Reviewed, approved Family Context Amendment, final Document & Submission Contract, verified Founder OS freeze bytes/SHA, and migration conflict report.
2. Freeze Person, Student, Guardian, Family and UUIDv7/legacy ID mapping semantics without duplicating identity masters.
3. Approve service assignment, consent, resource scope and RLS rules before adding business tables.
4. Approve document version and manifest immutability rules; use local mock object storage until private storage is separately authorized.
5. Add Education Application and Identity Case in their owning domains. Keep `casework` to generic collaboration references only.
6. Execute PostgreSQL 16/17, negative access, migration repeat, backup and restore tests in the isolated worktree before changing this report to PASS or CONDITIONAL.
