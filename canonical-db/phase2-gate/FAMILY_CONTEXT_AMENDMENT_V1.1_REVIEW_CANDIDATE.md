# Family Context Contract Amendment V1.1 — review candidate

**Status:** Ready for isolated Phase 2A contract tests; **not an effective amendment**. The original `FAMILY_CONTEXT_CONTRACT_V1` was not available in the checked Phoenix repository or the supplied correction-gate directory. This file must not be represented as a redline against that original.

## Verified source register

| Source | SHA-256 | Role |
|---|---|---|
| Supplied `04_FAMILY_CONTEXT_CONTRACT_AMENDMENT_DRAFT.md` | `a4d0ae15156b5a4b42fba58f09897442e94370c5b8bd8b5a451cdaffa968843d` | Amendment draft; explicitly not effective |
| Supplied `03_CANONICAL_POSTGRESQL_V1.2_REVIEWED.md` | `f344bb9de6a30b98952702a1515b64fe19bef3dffeb65b47c53c01d84ebae78e` | R2 database design draft |
| Supplied `10_R3_AMENDMENTS.md` | `4d2df59a8b48bf6ea65c117ca446f695a5208e29473c6886b3346ab6a6a40ed3` | Later draft changes; moves login entities from `core` to `auth` |
| Four-Portals Unified Architecture V1.1 | `4671a4d57bcaa752db83da1521c131d5bb61cc5df06e5a5b5e841c35114499d9` | Original design text; recommends UUIDv7 and legacy mapping |

`00_STATUS_SOURCES_VERDICT.md` describes FD-P1 as a **conditional design approval**, while also saying the Family Context amendment has not taken effect. Its SHA-256 is `bd083cd80fb461587f3fbbbdc98a2f83866c8cf8b3a3f73689b89366694dad93`. The user's authorization permits isolated development; it does not supply the absent original contract text.

## Proposed compatible model for isolated tests

1. Every internal identity key is a PostgreSQL `uuid` generated as UUIDv7 by a trusted application component. A version check rejects v4 or arbitrary legacy values at internal-key boundaries.
2. Public `usr_`, `fam_`, `stu_`, `gdn_`, and `per_` identifiers are issued and resolved through an explicit mapping record. Their shape alone never proves identity or authority.
3. Legacy identifiers remain typed source strings in `integration.legacy_id_mappings`; the same apparent identifier in two source systems is not an automatic match. No real legacy records enter Phase 2A.
4. `core.people` is the one natural-person master. A student is a profile linked to one Person. A guardian is a relationship and scoped authority, not another Person type. A biological relationship alone grants no document access.
5. `active_context` comes from a verified server session; client-supplied `person_id`, `family_id`, or `active_context` is never trusted to authorize access. Context switches are rechecked and audited.
6. Consent withdrawal and assignment expiry must take effect on the next decision. `SELF_DECLARED_LEGACY` guardianship cannot authorize identity documents.

These are **candidate contract statements**, suitable for synthetic tests. They do not authorize creation of `core.people`, student, guardian, mapping, or consent tables until the decisions below are closed.

## Blocking differences to resolve against the original contract

| ID | Difference | Required resolution before dependent DDL |
|---|---|---|
| FC-1 | Original Family Context V1 is absent; its exact ID authority and envelope cannot be redlined | Obtain exact original file and hash; produce clause-by-clause amendment |
| FC-2 | R2 puts principals and identities in `core`; R3 and Four-Portals original put login in `auth` | Approve one owner and migration path; avoid duplicate principal masters |
| FC-3 | `stu_` profile and `gdn_` guardianship differ from older first-class Student/Guardian IDs | Approve public compatibility API and explicit rejection of unmapped legacy forms |
| FC-4 | `minor_until` depends on jurisdiction and verified age evidence | Approve expiry calculation and evidence policy before automatic guardian authority |
| FC-5 | Source classification and reconciliation can map two source IDs to one Person | Approve evidence threshold and supersession workflow; never merge by name/phone alone |

## Phase 2A acceptance design

Use only synthetic identities. Implement the supplied draft's N1–N12 as a versioned negative-test matrix; include unmapped lookalike IDs, ambiguous mappings, expired guardianship, withdrawn Consent, cross-family and partner reads, and client-forged context. Each denial must have a stable reason code and an audit event. Tests may first run against disposable probe tables; they are not formal business RLS acceptance until FC-1 through FC-5 and trusted session binding are resolved.

## Approval record needed for effect

- Exact original Family Context V1 and its checksum.
- Founder approval of this amendment against that original, including FC-1 through FC-5.
- Signed schema ownership and API compatibility decision.
- PG16/17 synthetic negative tests against the final migrations.

**Gate:** Phase 2A contract and test development = STARTABLE. Family/Person/Student/Guardian business DDL and public contract activation = HOLD.
