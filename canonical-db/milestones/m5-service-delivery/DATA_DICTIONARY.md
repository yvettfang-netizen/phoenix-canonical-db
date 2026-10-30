# M5 Data Dictionary

| Table | Key | M5 controls |
|---|---|---|
| `service.tasks` (reused) | `task_id` UUIDv7 | Project, type/title, status, priority, current assignee and due/completion timestamps. |
| `service.task_events` (extended) | `task_event_id` UUIDv7 | Immutable status history plus `TRANSFERRED` old/new assignee and reason. |
| `service.milestone_templates` | `milestone_template_id` UUIDv7 | Code/version, controlled business domain, title, ACTIVE/RETIRED and actors. No body/content field. |
| `service.project_milestones` (extended) | `project_milestone_id` UUIDv7 | Exact optional template reference, Project-specific code/title, target and status. |
| `service.deliverables` (extended) | `deliverable_id` UUIDv7 | Project/subject, `docs.document_id`, exact `document_version_id`, workflow status, submission round, review/acceptance actors and timestamps. |
| `service.delivery_events` | `delivery_event_id` UUIDv7 | Immutable delivery state event, exact version, submission round, reason and actor. |
| `docs.document_versions` (reused) | `version_id` UUIDv7 | Canonical content digest, Mock storage key, size and version sequence; content remains outside Service. |

New delivery statuses are `DRAFT`, `UNDER_REVIEW`, `CHANGES_REQUESTED`, `REVIEW_APPROVED`, `ACCEPTED` and `WITHDRAWN`. Historical `READY`/`DELIVERED` values remain valid only for compatibility.
