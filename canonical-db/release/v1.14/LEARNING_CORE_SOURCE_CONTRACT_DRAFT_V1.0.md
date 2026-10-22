# Phoenix Learning Core Source Contract Draft V1.0

**Status:** DRAFT / NOT EFFECTIVE

**Purpose:** define a reviewable source contract for local Migration 0022

**Product boundary:** internal Phoenix Family OS and Education service-delivery data capability; this contract does not create a new public product or brand

## 1. Domain boundary

1. `learning` stores course versions, enrollments, teaching assignments, schedules, attendance, after-class cards, publications, and stage reports.
2. Natural-person and family identity remains in `core`. Learning creates no second student, guardian, teacher-person, or family master.
3. Course purchase and entitlement authority remains in Operations. Learning calls `operations_ref.has_valid_entitlement(..., 'COURSE', course_id)` and does not duplicate external orders, entitlement numbers, prices, invoices, discounts, or commissions.
4. Education applications remain in `education`; Learning has no foreign key to `education.applications`.
5. ASKWISE session, model, dialogue, diagnostic, knowledge-state, and error-taxonomy data is excluded.
6. Founder OS aggregation and Family OS growth-summary views are excluded.
7. No legacy or real data is imported in the local 0022 stage.

## 2. Authorization vocabulary

Subject to Founder approval, 0022 adds:

| Existing object | New value |
|---|---|
| `auth.principals.principal_kind` | `TEACHER`, `SUPERVISOR` |
| Session channel | `STAFF` |
| `consent.grants.purpose` | `LEARNING_RECORD` |
| `consent.grants.data_class` | `LEARNING` |
| `core.guardian_authorities.scope` | `LEARNING` |

`TEACHER` and `SUPERVISOR` principals must reference existing `core.people`. `STAFF` tickets bind only these two kinds. They cannot bind through `FAMILY`, `ADVISOR`, `PARTNER`, or `INTERNAL`.

Real login authentication remains an application integration HOLD. Local acceptance uses separate synthetic LOGIN accounts and one-time tickets.

## 3. Consent and access contract

1. Buying or holding a course entitlement never creates Consent and never grants access to learning-sensitive records.
2. An adult student may grant or withdraw `LEARNING_RECORD` / `LEARNING` Consent for their own records.
3. A verified guardian with active `LEARNING` authority may grant or withdraw Consent for the represented student.
4. For 0022, the grantee is an individual teacher's existing `core.people.person_id`. No organization is represented as a synthetic person.
5. A teacher needs both current Consent and an ACTIVE, unexpired assignment to the relevant OPEN or RUNNING class.
6. A supervisor needs current Consent for student-level sensitive reads. Supervisor status alone does not bypass Consent.
7. Student and guardian reads remain limited to the current family and subject.
8. Cross-family, expired, withdrawn, unassigned, closed-class, wrong-subject, and wrong-channel access fails closed.

## 4. Write and read interfaces

1. Runtime roles receive no direct INSERT, UPDATE, or DELETE on Learning tables.
2. Sensitive runtime reads use controlled SECURITY DEFINER functions that record access decisions. Runtime roles receive no direct table SELECT on sensitive Learning tables.
3. Published course catalog reads may use a dedicated controlled read function without exposing drafts.
4. Every function has a fixed `search_path`; PUBLIC execution is revoked; grants are signature-specific.
5. All Learning tables enable and force RLS as defense in depth.
6. Successful and denied writes are recorded through the established write-decision audit mechanism.
7. Successful and denied sensitive reads are recorded through the established access-event mechanism without storing learning content in the audit row.

## 5. Tables in Migration 0022

| Module | Tables |
|---|---|
| Course catalog | `learning.course`, `learning.course_version` |
| Enrollment | `learning.enrollment`, `learning.enrollment_status_event` |
| Teaching | `learning.teacher`, `learning.teacher_assignment` |
| Class and schedule | `learning.class`, `learning.enrollment_class`, `learning.schedule_slot` |
| Attendance | `learning.attendance_record`, `learning.attendance_correction` |
| Family-visible output | `learning.after_class_card`, `learning.publication`, `learning.stage_report` |

`learning.external_entitlement_ref` and `learning.askwise_session_link` from the earlier candidate dictionary are explicitly removed from 0022.

## 6. State and integrity rules

- Course: `DRAFT -> PUBLISHED -> ARCHIVED`.
- Course version: `DRAFT -> ACTIVE -> RETIRED`; one active version per course.
- Enrollment: `PENDING -> ACTIVE`; `ACTIVE <-> SUSPENDED`; terminal `COMPLETED` or `WITHDRAWN`.
- Teacher assignment: `ACTIVE -> ENDED` or `REVOKED`; terminal history cannot reactivate.
- Class: `PLANNED -> OPEN -> RUNNING -> CLOSED`.
- Schedule slot: `SCHEDULED -> COMPLETED` or `CANCELLED`.
- Card: `DRAFT -> SUBMITTED -> PUBLISHED -> RETRACTED`; teacher cannot publish.
- Publication and attendance corrections are append-only.
- One current enrollment per student and course version.
- One lead teacher per class; one current assignment per teacher/class.
- One attendance record and one after-class card per slot/enrollment.
- Enrollment, class, attendance, card, publication, and report references must preserve family and subject consistency through composite keys or validation triggers.
- Schedule overlap uses a `btree_gist` exclusion constraint. Migration 0022 may install the extension only through the migration owner path.

## 7. Enrollment contract

1. A Learning SERVICE in an INTERNAL context requests enrollment creation.
2. The course and version must be active, the student must exist, and family membership must be current.
3. A matching active Operations `COURSE` entitlement must exist for the same family, student, and course.
4. Enrollment starts as `PENDING`.
5. Activation requires valid `LEARNING_RECORD` / `LEARNING` Consent. Entitlement alone is insufficient.
6. Later entitlement revocation prevents new enrollments. It does not delete attendance or published history; suspension policy after revocation remains fail closed for new teaching writes until a future explicit operational rule is approved.

## 8. Publication contract

1. A teacher with current assignment may draft and submit a card for an enrolled student and scheduled/completed slot.
2. A teacher cannot publish, retract, or alter another teacher's card.
3. A SUPERVISOR in a STAFF context may publish a submitted card after rechecking family, enrollment, assignment, and Consent.
4. Families can read only PUBLISHED cards and reports for the current subject and family.
5. Retraction immediately removes family visibility while retaining immutable history.

## 9. Local acceptance

PG16 and PG17 acceptance must include:

- fresh 0001–0022 apply, repeat safety, missing/extra/drift refusal, and atomic rollback;
- separate TEACHER, SUPERVISOR, FAMILY, SERVICE, app, and binder LOGIN accounts with one-time tickets;
- positive and negative permission coverage for student, guardian, teacher, supervisor, service, cross-family, expired assignment, withdrawn Consent, entitlement mismatch, class state, capacity, schedule overlap, publication, and retraction;
- proof that entitlement creation does not create Consent;
- proof that ASKWISE absence does not block the Learning closed loop;
- protected backup, manifest verification, and fresh-cluster recovery on PG16 and PG17;
- no persistent synthetic business rows or temporary schemas after testing.

## 10. Exclusions and HOLD items

- real authentication provider and Web integration;
- real teachers, students, courses, schedules, cards, or legacy assignments;
- Operations source worker and production entitlement synchronization;
- ASKWISE and Family OS summary schemas;
- Founder OS metrics;
- production deployment and Tencent task B;
- Push, Merge, or PR state changes.

This contract becomes effective only when the Founder approves its exact SHA-256 in the accompanying decision record.
