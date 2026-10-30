# M3 Data Dictionary

| Table | Key | M3 controls |
|---|---|---|
| `crm.consultations` (extended) | `consultation_id` UUIDv7 | Lead/Client/Family/subject, domain, type, four-Compass kind, owner, schedule, status, result code and next-action code. |
| `crm.consultation_events` | `consultation_event_id` UUIDv7 | Consultation FK, create/status/owner event, old/new values, reason, actor, time; immutable. |
| `crm.deals` (extended) | `deal_id` UUIDv7 | Client/Family, optional Lead/Referral, domain, NUMERIC(18,2) amount, ISO currency, expected close, owner, controlled status, win/loss reason. |
| `crm.deal_events` | `deal_event_id` UUIDv7 | Status, amount, owner, scope and project-candidate history; immutable. |
| `crm.sales_assignments` | `sales_assignment_id` UUIDv7 | Deal/Principal, role, temporal validity, active/revoked state, actor/reason; non-overlapping primary owner. |
| `crm.deal_project_candidates` | `deal_project_candidate_id` UUIDv7 | Deal, candidate code, domain, Compass, proposed/approved/dismissed state. |
| `crm.deal_items` (extended) | `deal_item_id` UUIDv7 | Existing scope line; Health Compass added to the approved Compass constraint. |
| `crm.follow_ups` (reused) | `follow_up_id` UUIDv7 | Lead/Deal/Client target, assignee, due time and controlled pending/completed/cancelled state. |

No payment, invoice, contract, diagnosis, questionnaire-answer or medical-record column is introduced.
