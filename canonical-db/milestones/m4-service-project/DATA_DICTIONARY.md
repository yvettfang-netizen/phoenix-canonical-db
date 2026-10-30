# M4 Data Dictionary

| Table | Key | M4 controls |
|---|---|---|
| `service.projects` (reused) | `service_project_id` UUIDv7 | Client/Family/optional Deal, code/name, status, primary domain, schedule. |
| `service.project_parties` (extended) | `project_party_id` UUIDv7 | Person/Organization XOR, controlled role, ACTIVE/ENDED, temporal validity and ending actor. |
| `service.project_subject_authorizations` | `project_subject_authorization_id` UUIDv7 | Project/Family/subject, PATIENT_SELF or LEGAL_GUARDIAN, HEALTH scope, authorizer, evidence SHA-256, validity, ACTIVE/REVOKED. |
| `service.project_subjects` (extended) | `project_subject_id` UUIDv7 | Project/Family/Person, data scope, reference-only access, authorization FK for HEALTH, ACTIVE/ENDED validity. |
| `service.project_domains` (reused) | `project_domain_id` UUIDv7 | One controlled business domain per Project. |
| `service.project_assignments` (extended lifecycle) | `project_assignment_id` UUIDv7 | Project/Principal/role, ACTIVE/ENDED validity and actors. |
| `service.project_events` (extended) | `project_event_id` UUIDv7 | Party, subject, authorization, assignment and Project lifecycle events; immutable. |

Authorization evidence stores only a digest; raw consent or medical content is not stored.
