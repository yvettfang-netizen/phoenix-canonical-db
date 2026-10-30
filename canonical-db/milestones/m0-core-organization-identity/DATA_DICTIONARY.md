# M0 Data Dictionary

## Existing authority reused

| Entity | Key | Meaning |
|---|---|---|
| `core.people` | `person_id` UUIDv7 | Unique natural person. |
| `core.families` | `family_id` UUIDv7 | Family authority. |
| `core.family_memberships` | `family_membership_id` UUIDv7 | Time-bounded Person role in a Family. |
| `core.student_profiles` | `person_id` FK | Education-facing extension of Person. |
| `auth.principals` | `principal_id` UUIDv7 | Login or service actor; not a Person synonym. |
| `core.organizations` | `organization_id` UUIDv7 | Unique legal/operating institution master. |

## New in 0030

| Table | Primary key | Important fields and constraints | Index rationale |
|---|---|---|---|
| `core.organization_identifiers` | `organization_identifier_id` UUIDv7 | Organization FK; controlled identifier type; ISO alpha-2 country; issuer; SHA-256 digest only; validity; ACTIVE/REVOKED; actor FKs. Overlapping active values are excluded by country/type/digest/time range. | Organization/status/type lookup. |
| `core.organization_relationships` | `organization_relationship_id` UUIDv7 | Source and target Organization FKs; distinct endpoints; controlled type; ACTIVE/ENDED; validity and actor FKs. Overlapping identical relationships are excluded. | Target/status/type lookup. |
| `core.organization_name_history` | `organization_name_history_id` UUIDv7 | Organization FK; legal/display names; non-overlapping validity; actor FK; one current row. | Exclusion plus current-row unique index. |
| `core.organization_events` | `organization_event_id` UUIDv7 | Organization FK; controlled event kind; related resource; from/to status; normalized reason; actor; timestamp. Immutable. | Organization/time event stream. |

## Public ID

`integration.public_ids` accepts `entity_kind='ORGANIZATION'` and `org_<UUID without hyphens>`. Public ID does not replace the UUIDv7 canonical key.

All time values are `TIMESTAMPTZ`; all sensitive registration values are digests, not plaintext identifiers.
