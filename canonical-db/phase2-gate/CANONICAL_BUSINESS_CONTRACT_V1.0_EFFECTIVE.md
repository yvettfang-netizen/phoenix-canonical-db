# Phoenix Canonical business contract V1.0

**Status:** EFFECTIVE FOR GREENFIELD CANONICAL DATABASE  \
**Effective date:** 2026-10-14 (Asia/Shanghai)  \
**Authorization:** Founder instruction in the current Codex session to prepare the missing materials, pass Phase 3, and deploy only after all stages pass.

## Evidence boundary

This document is a new prospective baseline. It is not the missing historical Family Context V1, Founder OS freeze, or a reconstructed redline. It authorizes new synthetic and greenfield Canonical schema work only. Legacy record migration, automatic legacy-ID equivalence, Founder OS/D1 reuse, Feishu import, Operations asset reuse, and real customer data remain HOLD until their original evidence is recovered and reconciled.

## Identity and family decisions (FC-1 through FC-5)

1. `auth` owns login principals and trusted database session context. `core` owns natural persons, families and family relationships. A principal may reference one Person; a Person does not require a login.
2. Internal entity keys are application-issued UUIDv7 and are checked at database boundaries. PostgreSQL sequences and random UUIDv4 values are not Canonical identity authority.
3. `core.people` is the only natural-person master. Student is a one-to-one profile of Person. Guardian is a time-bounded relationship and authority between two Persons within one Family.
4. Public IDs use an explicit `entity_kind + public_id -> canonical_id` mapping. Legacy IDs use `source_system + entity_kind + legacy_id -> canonical_id`. Identifier shape, name, phone or email never establishes equivalence.
5. A mapping can be `PENDING`, `VERIFIED`, `REVOKED`, or `SUPERSEDED`. Only one active verified mapping is allowed for a source tuple. Reconciliation and supersession require recorded evidence and actor; Phase 3 uses synthetic evidence only.
6. Minor status and guardian expiry are supplied from verified evidence. No jurisdiction or age is inferred by the database. `SELF_DECLARED_LEGACY` evidence never authorizes identity-document access.
7. Family membership does not automatically grant document access. Active Consent and, when acting for another Person, active Guardian Authority are both required.

## Trusted session binding

1. A separate server-side gateway credential holds only `phoenix_canonical_context_binder`. Application query credentials hold only `phoenix_canonical_app`. They are separate secrets and connection pools.
2. Only the binder may execute `auth.bind_context` and `auth.clear_context`. Client-provided GUC values, headers, person IDs and family IDs are ignored by RLS.
3. Context is stored for the current PostgreSQL backend PID with principal, actor Person, active Family, channel, expiry and a random request nonce. Rebinding replaces the complete row. Pool return must call clear; expiry is checked on every policy decision.
4. Binder calls are accepted only after the application has authenticated the principal outside PostgreSQL. Authentication implementation and token validation are application responsibilities; the database enforces the bound result.
5. Every deny-capable business action writes a stable reason code to `audit.access_events` through a controlled function. RLS filtering itself does not leak rows.

## Consent and authority

1. Consent is scoped by grantor Person, subject Person, Family, purpose and data class.
2. Consent states are `ACTIVE`, `WITHDRAWN`, and `EXPIRED`. Withdrawal is effective on the next database decision. The original grant and withdrawal timestamps remain immutable.
3. Guardian Authority has evidence level `VERIFIED` or `SELF_DECLARED_LEGACY`, explicit start and expiry, and a scope. Identity-document access requires `VERIFIED`.
4. Advisor access requires an active case assignment plus required Consent. Channel/partner access requires an active, subject-specific channel grant plus required Consent. Neither role grants cross-family access.

## Documents and submissions (DS-1 through DS-5)

1. The canonical namespace is `docs`; `documents` is not created. Database metadata and private object bytes remain separate.
2. A Document belongs to one Family and one subject Person. Each upload creates a new immutable `document_versions` row with a private opaque storage key and SHA-256 digest. Existing version identity, digest and storage key cannot be updated or deleted.
3. Submission manifests live in `docs`. Each manifest targets exactly one Education Application or one Identity Case. `SUBMITTED` manifests and their items are immutable. Corrections create a new manifest.
4. Withdrawal prevents a document version from entering a new submitted manifest. Existing submitted evidence remains readable when authorization still permits it. Legal Hold blocks metadata purge and object-purge authorization.
5. Each Document requires `retention_until`; the database supplies no legal default. Physical purge is allowed only after that timestamp, with no Legal Hold, no submitted-manifest reference, and an authorized purge workflow. Phase 3 uses local synthetic Mock storage. Tencent deployment stores metadata only until a private object-store decision is separately approved.
6. Supported data classes are `GENERAL`, `EDUCATION`, and `IDENTITY_SENSITIVE`. Identity-sensitive reads require explicit Consent and verified Guardian Authority when acting for another Person.

## Casework, Education and Identity

1. `casework.cases` is generic advisor collaboration and does not duplicate an Education Application or Identity Case. States: `OPEN`, `PAUSED`, `CLOSED`.
2. Education Applications belong to one Family and Student Person. States: `DRAFT`, `READY`, `SUBMITTED`, `DECIDED`, `WITHDRAWN`. Required core fields are application ID, family ID, student Person ID, program label, institution label, cycle label, state and timestamps. School-specific material rules remain configuration outside this migration.
3. Identity Cases belong to one Family and subject Person. States: `DRAFT`, `EVIDENCE_PENDING`, `UNDER_REVIEW`, `RESOLVED`, `CLOSED`. Required core fields are case ID, family ID, subject Person ID, case kind, state and timestamps.
4. State changes are append-audited. Official receipt and decision facts are separate records and must carry source, external reference and observed time.
5. Generic casework may reference an Education Application or Identity Case but cannot own or copy its domain state.

## Role and release boundary

- Migrator: DDL and migration ledger only.
- Context binder: bind/clear trusted backend context only.
- Application: exact table operations through RLS; no schema creation, role changes or ledger access.
- Reader: read-only RLS-filtered metadata; no document object access.
- Bootstrap: installation only; it is not an application credential.

Phase 3 release requires PG16 and PG17 fresh migration, repeat checksum verification, RLS negative tests, immutability tests, synthetic backup/restore, and catalog evidence. Production real-data import and legacy reconciliation are excluded.
