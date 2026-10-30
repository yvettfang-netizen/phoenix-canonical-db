# M2 Data Dictionary

| Table | Key | Core constraints / indexes |
|---|---|---|
| `crm.leads` (reused) | `lead_id` UUIDv7 | Controlled status now includes LOST; no contact attribute is a unique identity key. |
| `crm.lead_attributions` | `lead_attribution_id` UUIDv7 | Lead/Source/Campaign/Partner FKs; FIRST_TOUCH or CONVERSION_TOUCH; four Compass values; source system and model version; unique Lead/kind; immutable; source/time index. |
| `crm.lead_duplicate_candidates` | `lead_duplicate_candidate_id` UUIDv7 | Ordered Lead pair; SHA-256 evidence; PENDING/CONFIRMED/DISMISSED; proposer/reviewer; distinct review; one pending pair. |
| `crm.lead_merge_decisions` | `lead_merge_decision_id` UUIDv7 | Confirmed candidate and source/target Lead FKs; previous status; ACTIVE/REVERSED; actor/timestamps; one active merge per source. |
| `crm.referrals` (extended) | `referral_id` UUIDv7 | Existing subject/referrer FKs plus Partner Relationship and Lead Source pair; RECORDED/CONFIRMED/REVOKED. |
| `crm.referral_events` | `referral_event_id` UUIDv7 | Referral FK; controlled event/status; reason; actor; timestamp; immutable; referral/time index. |

Money, medical questionnaire data and raw contact identifiers are not introduced.
