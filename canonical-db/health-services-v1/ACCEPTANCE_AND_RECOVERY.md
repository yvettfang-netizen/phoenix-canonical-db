# Health synthetic acceptance and recovery plan

Status: **NOT RUN — migration implementation blocked by missing authority DDL**.
Existing baseline reports are historical evidence and are not new Health tests.

## Required acceptance before a migration PR can pass

| Gate | Required evidence | Current result |
|---|---|---|
| Source | Pin approved member/project/lead/task DDL, PK types and ownership | HOLD |
| ID compatibility | Preserve application-issued UUIDv7 and existing public/legacy mappings; no Health replacement masters | Existing baseline verified; Health NOT IMPLEMENTED |
| Fresh PG16 / PG17 | Apply current baseline and new Health migration to new synthetic-only clusters | NOT RUN |
| Upgrade / repeat | Upgrade baseline to Health; checksum-lock all old migrations; rerun skips identical files and rejects drift | NOT RUN |
| FK / constraints | Wrong family/member/project/case combinations rejected; nullable relationships and status transitions tested | NOT RUN |
| Split LOGIN / roles | Binder/app/reader separated; direct table DML/read and PUBLIC function privileges denied | NOT RUN |
| Context spoofing | Forged GUC/header/member ID, unknown principal, expired ticket, wrong nonce/backend, disabled principal denied | NOT RUN |
| Consent | Patient/project/scope/recipient positives; no family-admin override; verified proxy and capacity checks; expiry/revoke deny next access | NOT RUN |
| Isolation | Cross-family, same-family different patient, same-patient different project/case, unauthorized coordinator/provider denied | NOT RUN |
| Answers | Closed questionnaire validation; CRM/Founder/Timeline cannot read raw answers; no auto-lead or clinical score | NOT RUN |
| Documents | No public URL; wrong patient/case rejected; revoked grant denies proxy access even with prior access handle | NOT RUN |
| Retention | Approved retention/legal-hold rules, restricted delete/purge and post-delete denial | NOT RUN |
| Audit | Allow and deny events, minimal payload, rollback reconciliation and no sensitive logging | NOT RUN |
| Existing modules | Current F10, family mapping, Education, Identity, Learning and Operations reference suites still pass | NOT RUN |
| API / end to end | Real loopback HTTP through authenticated gateway, separate pools, RLS and private storage mock | NOT RUN |
| Recovery | Synthetic-only verified backup and fresh-cluster restore, ledger/FK/RLS/ACL verification | NOT RUN |

Synthetic fixtures should include two families, two patients in one family, a
second project for the same patient, a verified proxy, an expired proxy, separate
coordinator/translator/provider principals, and revoked/expired grants. IDs and
records must be synthetic; no production snapshots or patient text may be used.
Fixtures cannot invent missing business master DDL just to make FKs compile.

The existing `tests/f10_local_acceptance.ps1` pins 25 migrations and current
catalog counts. After a real Health migration is ready, extend the inventory and
catalog expectations deliberately and keep the previous regression suites;
simply adding a SQL file will not constitute acceptance.

## Recovery boundary

No executable down-migration is supplied because no Health migration exists.
Never place a speculative `DROP SCHEMA health CASCADE` in the normal rollback
path. A Health runtime disablement should first close access/ingestion while
retaining records under the approved policy.

Once implemented, rehearse the following only on disposable synthetic clusters:

1. Capture a hash-verified baseline schema/ledger/role inventory and synthetic
   backup using the existing controlled test mechanism.
2. Apply the Health migration transactionally with ledger registration; inject a
   failing constraint and prove there is no partial schema or ledger residue.
3. Exercise writes and patient authorization, then disable the synthetic runtime.
4. Restore the verified backup to a new isolated cluster; compare baseline ledger,
   FK types, RLS, owner/role ACLs and run existing regression suites.
5. Separately test recovery with persisted synthetic Health records so an older
   schema restore cannot be misrepresented as preserving newer data. Record
   loss window, reconciliation and evidence retention explicitly.

Any production migration, storage enablement, real identity binding or restoration
remains a separate Founder action. This package contains no environment file,
credentials, real records, database backup or production executable command.
