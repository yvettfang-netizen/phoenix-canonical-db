# Phoenix Canonical Production Database Package

**Package status:** TECHNICAL BASELINE COMPLETE / PRODUCTION APPROVALS PENDING  
**Current runtime:** Isolated empty Canonical PostgreSQL on Tencent Cloud  
**Current database:** `phoenix_canonical_dev`

## Files in this package

| File | Purpose | Who completes it |
|---|---|---|
| `PRODUCTION_DATABASE_SOLUTION_V1.0_DRAFT.md` | Technical production database solution and release gates | Codex maintains; Founder reviews scope |
| `PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md` | Decisions and approvals that cannot be inferred from code | Founder completes and signs |
| `PRODUCTION_DATABASE_EVIDENCE_REQUEST_V1.0.md` | Exact originals and evidence required to close HOLD items | Founder supplies or points to source |
| `CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md` | Effective greenfield baseline used by migrations 0001–0006 | Already effective for greenfield only |
| `PHASE3_APPROVAL_REGISTER.md` | Hashes and scope for the greenfield approval | Already recorded |
| `../PHASE3_EXECUTION_REPORT.md` | Local PG16/17 design and acceptance evidence | Updated |
| `../TENCENT_DEPLOYMENT_EXECUTION_REPORT.md` | Tencent isolated runtime evidence | Updated |

## Current decision boundary

The technical baseline and empty database are complete. Production use with real records requires the Founder Decision Register and the evidence items listed in the Evidence Request. No secrets belong in these Markdown files or in chat.

## How to finish the package

1. Place source originals in the incoming evidence location described in `PRODUCTION_DATABASE_EVIDENCE_REQUEST_V1.0.md`.
2. Complete only the `FOUNDER INPUT` blocks in `PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md`.
3. Record each final source SHA-256 and approval date.
4. Codex performs a contract-diff review and drafts the next migration plan.
5. Founder approves the migration plan and production cutover gate separately.

Until steps 1–3 are complete, the database remains an empty isolated Canonical environment.
