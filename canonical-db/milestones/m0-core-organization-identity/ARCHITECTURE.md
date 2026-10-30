# M0 Architecture — Core Organization & Identity

Status: implemented by forward Migration `0030`; Founder acceptance remains a separate gate.

## Authority and semantics

- `core.people` remains the only natural-person master. “Member” is a time-bounded role expressed by `core.family_memberships`; it is not a second person table.
- `auth.principals` remains the login/service identity authority and is deliberately not merged with Person. One Person may have several business roles without a duplicate profile.
- `core.families`, `core.family_memberships`, `core.student_profiles`, guardian authority and civil-capacity rules remain authoritative and byte-preserved.
- `core.organizations` is the single organization master. `0030` adds identifiers, relationships, name history and immutable events around that existing master.
- `integration.public_ids` issues the stable `org_<32 lowercase hex>` external identifier while the UUIDv7 remains the internal key.

## Lifecycle

Organization status transitions are controlled: `ACTIVE -> INACTIVE|RETIRED`, `INACTIVE -> ACTIVE|RETIRED`; `RETIRED` is terminal. Name changes append history. Official identifiers are appended and may only be revoked. Organization relationships are appended and may only be ended; a later relationship uses a new UUID and non-overlapping validity interval.

## Existing-system impact

No Person, Family, Student, Principal, Client, Education or Identity table is replaced. Existing callers of the legacy two-argument organization transition lose application execution; the audited three-argument form records an immutable event. Existing migration files `0001`–`0029` are unchanged.

## Ownership

Enterprise master-data SERVICE context (`canonical_enterprise_v2_core`) owns controlled writes. Runtime app, reader and binder accounts have no direct table DML. No production connection, real record or production secret is used.
