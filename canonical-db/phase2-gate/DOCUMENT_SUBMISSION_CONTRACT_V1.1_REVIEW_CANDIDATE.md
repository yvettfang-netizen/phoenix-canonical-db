# Document & Submission Contract V1.1 — review candidate

**Status:** Generic mechanism is suitable for isolated Phase 2A design and synthetic testing; final business contract remains on hold. No real files, COS connection, signed download URL, or production retention rule is authorized.

## Verified sources and difference

| Source | SHA-256 | Meaning |
|---|---|---|
| Supplied `05_DOCS_AND_SUBMISSION_CONTRACT.md` | `cc64fd99ca0d0ae7714764164dee6f5231db431310cae0dba69eecaa35252d7b` | R2 mechanism draft; uses `docs` |
| Supplied `10_R3_AMENDMENTS.md` | `4d2df59a8b48bf6ea65c117ca446f695a5208e29473c6886b3346ab6a6a40ed3` | Later draft; changes namespace to `documents` and manifest shape |
| Four-Portals Unified Architecture V1.1 | `4671a4d57bcaa752db83da1521c131d5bb61cc5df06e5a5b5e841c35114499d9` | Original design uses `documents.documents`, `document_versions`, `submission_manifests` |

`00_STATUS_SOURCES_VERDICT.md` reports FD-P5 **technical design approval** for the generic mechanism, with retention, deletion, and cross-border storage left to a later compliance gate. The current local foundation has an empty `docs` schema because the Phase 1 instruction explicitly named `docs`. **Do not create a second `documents` namespace or rename the existing one until the schema-name conflict is decided.**

## Mechanism contract for synthetic implementation

1. Metadata and version records live in PostgreSQL; content lives only in an isolated local mock object store. `storage_ref` is an opaque private key, never a public URL and never derived from a person's name.
2. `document_versions` has a unique `(document_id, version_no)` and a content digest. Content identity columns are immutable. A new upload creates a new version; it cannot overwrite an old version or an old submission reference.
3. A submission is a distinct event for each first application, renewal, supplement, or resubmission. It pins exact document-version IDs and digests. A submitted manifest cannot be updated or deleted; a correction is a new submission event.
4. Reuse of an unchanged version means two submission records may point to the same version. Referential integrity prevents dangling version references.
5. Prepared, confirmed, and submitted actors are recorded separately. A verified document is not automatically an official submission. Receipt and decision are separate sourced facts.
6. Withdrawal blocks use in a new submission while preserving lawful access to an existing evidentiary snapshot. `LEGAL_HOLD` blocks content purge. Physical deletion, retention term, and cross-border location remain undecided.
7. Document reads require a trusted server-side policy decision and audit. Family membership, payment, founder/admin status, or partner status alone never grants document-body access.

The current PG16 and PG17 `tests/docs_probe.sql` checks immutable version content, immutable submitted items, unique version numbering, valid foreign-key references, and pinned references **inside a rolled-back synthetic transaction**. It establishes database mechanism feasibility, not a built or approved `docs` table.

## Differences that block final DDL

| ID | Open item | Required decision |
|---|---|
| DS-1 | `docs` (current Phase 1 and R2) versus `documents` (Four-Portals original/R3) | One canonical namespace and an explicit compatibility/migration note |
| DS-2 | R2 `submissions` + `submission_items` + `snapshots` versus R3 `submission_manifests` and Identity's separate submissions | Final ownership, FK/soft-reference, sequence and freeze-point model |
| DS-3 | Owner Person, guardian, Consent and advisor assignment depend on Family Context amendment | Complete FC-1 through FC-5 and bind policy to a trusted session |
| DS-4 | Retention duration, content purge, legal hold authority, storage region, and backup of objects | Compliance decision; no default permanent retention |
| DS-5 | Education and Identity material lists, official receipts, business states | Domain-owner approved requirements; no invented A/B/C or school checklist |

## Final acceptance before business use

On PG16 and PG17 with synthetic records, test version overwrite/delete rejection, immutable submitted manifest, exact snapshot digest reproduction, reuse across renewal, withdrawal, legal hold, expired/insufficient guardianship, missing Consent, cross-family and advisor denial, and access audit. Use the same private mock object-store contract in backup/restore tests. None of these results is a production access approval.

**Gate:** Phase 2A synthetic mechanism work = STARTABLE. Canonical `docs`/`documents` business tables, real uploads, retention, and Identity/Education submission integration = HOLD until DS-1 through DS-5 are approved.
