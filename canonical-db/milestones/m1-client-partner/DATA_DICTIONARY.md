# M1 Data Dictionary

| Table | Key | Core constraints | Index purpose |
|---|---|---|---|
| `crm.clients` (reused) | `client_id` UUIDv7 | Family FK; unique current Family relationship; ACTIVE/PAUSED/ENDED; ended timestamp. | Family history and current lifecycle. |
| `crm.client_parties` | `client_party_id` UUIDv7 | Composite Client/Family FK; PERSON/ORGANIZATION XOR; controlled five-role vocabulary; validity and ACTIVE/ENDED; actor FKs; non-overlap per Client/role/subject. | Client/status/role lookup. |
| `crm.client_relationship_events` | `client_relationship_event_id` UUIDv7 | Client FK; optional Client Party FK; controlled event kind; from/to status; reason; Principal actor; immutable. | Client chronological history. |
| `crm.partner_relationships` | `partner_relationship_id` UUIDv7 | PERSON/ORGANIZATION XOR; controlled relationship type; Lead Source FK for Referral/Channel; validity and ACTIVE/ENDED; actor FKs; non-overlap. | Source/status/type lookup. |
| `crm.partner_relationship_events` | `partner_relationship_event_id` UUIDv7 | Partner relationship FK; controlled event; status; reason; Principal actor; immutable. | Relationship chronological history. |

All timestamps are `TIMESTAMPTZ`; no contact or identifier plaintext is copied into these relationship tables.
