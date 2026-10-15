# Phoenix Canonical Production Database — Founder Decision Register V1.0

**Status:** PENDING FOUNDER INPUT  
**Purpose:** Record decisions that cannot be inferred from SQL, tests or an unverified historical document.  
**Security:** Do not paste passwords, private keys, tokens, client secrets or document bytes here.

## How to complete

For every item, select one decision, attach the source or rationale, and fill in the approver and date. A typed approval in the current Codex session may be recorded as the approval event; legal signatures should be handled in the organization's normal contract process.

## Decisions requiring Founder input

### FD-1 — Production scope

- [ ] Approve an empty Canonical database as the only production scope for the next release.
- [ ] Approve real-data migration in a later gate after all remaining decisions close.
- [ ] Hold production use.

**Founder input:**

- Decision: `[ ]`
- Rationale or referenced plan:
- Approver name and role:
- Approval date/time and timezone:
- Signature or typed approval:

### FD-2 — Family Context and identity authority

- [ ] Approve `CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md` as the greenfield production identity baseline.
- [ ] Replace it with a supplied final Family Context contract.
- [ ] Hold until the historical Family Context V1 original is recovered.

Required confirmation: `core.people` is the only natural-person master; Student is a Person profile; Guardian is time-bounded; UUIDv7 is the internal ID authority; legacy IDs require source-qualified evidence.

**Founder input:**

- Selected option:
- Final source path or attachment:
- Source SHA-256:
- Changed clauses:
- Approver/date/signature:

### FD-3 — Founder OS and Operations reuse

- [ ] No Founder OS, D1 or Operations data/IDs/assets will enter Canonical in this release.
- [ ] Approve a specific reuse plan after the original Founder OS freeze and reconciliation evidence are attached.
- [ ] Hold.

**Founder input:**

- Selected option:
- Exact repository/branch/commit or file path:
- Source SHA-256:
- Reused entities/assets, if any:
- Approver/date/signature:

### FD-4 — Legacy ID reconciliation

- [ ] No legacy IDs or real records are imported in this release.
- [ ] Approve a later reconciliation project using explicit `source_system + entity_kind + legacy_id` mappings and evidence states.
- [ ] Hold.

Required source inventory: system name, table/file, owner, ID examples (synthetic if necessary), collision policy, supersession policy, reviewer and audit retention.

**Founder input:**

- Selected option:
- Source systems in scope:
- Mapping owner:
- Evidence standard:
- Approver/date/signature:

### FD-5 — Documents, Submission and object storage

- [ ] Approve metadata-only Canonical deployment until private object storage is approved.
- [ ] Approve a real private object store and adapter after the fields below are complete.
- [ ] Hold.

Required fields: provider, account/project, bucket/container name (no secret), region, encryption owner, retention schedule, legal-hold authority, purge authority, cross-border rule, backup destination and incident owner.

**Founder input:**

- Selected option:
- Provider/region:
- Retention and purge rule:
- Legal-hold authority:
- DS-1–DS-5 final source path and SHA-256:
- Approver/date/signature:

### FD-6 — Application authentication and trusted context

Required fields: token issuer, audience, JWKS/discovery URL, principal-to-Person resolution owner, binder service owner, app/binder connection-pool separation, pool clear-on-return mechanism, expiry policy, audit event owner and incident response owner.

**Founder input:**

- Authentication contract path/version:
- Issuer/audience:
- Binder owner:
- Application owner:
- Pool reset mechanism:
- Approver/date/signature:

### FD-7 — Operations, backup and recovery

Required fields: target RPO, target RTO, backup frequency, retention duration, private backup destination, restore rehearsal cadence, alert channel, on-call owner, incident severity rules and rollback window.

**Founder input:**

- RPO:
- RTO:
- Backup retention:
- Restore cadence:
- On-call owner:
- Rollback window:
- Approver/date/signature:

### FD-8 — Production cutover gate

- [ ] Approve only the isolated empty Canonical runtime.
- [ ] Approve application staging integration after FD-1 through FD-7 are closed.
- [ ] Approve real-data migration and production cutover after a separate runbook review.
- [ ] Hold.

Required fields: exact target environment, change window, operator, preflight checklist, backup ID, rollback command/runbook, monitoring owner, abort conditions and post-cutover verification owner.

**Founder input:**

- Selected option:
- Target environment:
- Change window:
- Operator and approver:
- Rollback reference:
- Approver/date/signature:

## Approval record

By signing or giving a typed approval tied to this file and its SHA-256, the approver confirms only the selected decisions. Unselected items remain `HOLD`.

- Register version:
- Register SHA-256:
- Founder/approver:
- Role:
- Date/time/timezone:
- Signature or typed approval:
