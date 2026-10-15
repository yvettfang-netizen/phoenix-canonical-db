# Phoenix Canonical Production Database — Evidence Request V1.0

**Status:** OPEN — evidence collection  
**Incoming location:** `canonical-db/phase2-gate/evidence/incoming/`  
**Approved evidence location:** `canonical-db/phase2-gate/evidence/approved/`  
**Rule:** Incoming files are preserved byte-for-byte. An item becomes approved only after its SHA-256, source, reviewer and decision are recorded in the Founder Decision Register.

## Required evidence

| ID | Evidence | Minimum content | Current status |
|---|---|---|---|
| EV-1 | Final Family Context contract | Person/Student/Guardian ownership, ID authority, family/consent semantics, effective version | Missing; current amendment is a review candidate |
| EV-2 | Founder OS Freeze original | Exact repository/branch/commit, original bytes, ID registry and integration clauses | Missing; current file is evidence-only locator |
| EV-3 | Final Docs & Submission contract | DS-1–DS-5, retention, legal hold, purge, storage region and submission freeze | Missing; current file is a review candidate |
| EV-4 | Education/Identity domain rules | Fields, states, transitions, official facts, owner and acceptance cases | Partial greenfield baseline; operational approval missing |
| EV-5 | Legacy source inventory | Source systems, tables/files, owners, ID formats, collision and supersession policy | Missing for real-data migration |
| EV-6 | Object-store contract | Provider, region, encryption, retention, purge, legal hold, backup and incident owner | Mock only; production contract missing |
| EV-7 | Application auth/context contract | Issuer, audience, JWKS, principal resolution, binder service, pool lifecycle and expiry | Application-owned input missing |
| EV-8 | Operations SLO and cutover plan | RPO/RTO, backup retention, monitoring, rollback, change window and on-call owner | Missing |

## Source integrity record

Complete one record for each supplied file:

```text
Evidence ID:
Original source URL/repository/path:
Branch/tag/commit (if applicable):
Local filename:
SHA-256 of exact bytes:
Received by:
Received date/time/timezone:
Conflicts found:
Decision Register item:
Reviewer:
Approval date:
```

## What may be supplied safely

- Contract text, decision records, schema diagrams, field lists, synthetic examples and source hashes.
- Redacted screenshots or exports that preserve the clause and version information.
- Repository references and exact commits for Founder OS or Operations assets.

## What must not be supplied in these files or chat

- SSH private keys, database passwords, API tokens, COS secrets, JWT signing keys or unredacted customer/student records.
- Real identity documents or document bytes. Provide a secure storage reference and authorization record instead.

## Completion rule

When EV-1 through EV-8 are either approved or explicitly marked out of scope by the Founder, Codex can produce the final production migration impact plan. Any unresolved conflict remains `HOLD`; no migration is created by inference.
