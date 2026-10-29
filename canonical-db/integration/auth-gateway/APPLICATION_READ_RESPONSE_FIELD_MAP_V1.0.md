# Application Read Response Field Map V1.0

Status: **IMPLEMENTED LOCALLY / SYNTHETIC EVIDENCE ONLY**
Scope: the first three approved read-only Phoenix Family OS routes.

## Boundary

Canonical PostgreSQL is the authorization and RLS gate for these routes. It is
not yet the response-data source. The existing application Store remains the
source of the response fields and of the public `fam_*` / `stu_*` identifiers.
Canonical UUIDv7 values are never returned by these routes.

The student routes first verify application-side ownership, then enter the
Canonical family context, redeem a one-use ticket on the separate app pool and
require one visible `core.families` row under RLS. A future Canonical-source
student DTO remains **HOLD** until VERIFIED `STUDENT_PROFILE` mapping authority
is approved.

## Exact field map

| Route | JSON path | Source | Fields |
|---|---|---|---|
| `GET /v1/me/family` | `family` | application `families` Store record | `id`, `userId`, `familyName`, `parentName`, `phone`, `location`, `goal`, optional `profileStatus`, optional `profileSchemaVersion`, `createdAt`, `updatedAt` |
| `GET /v1/me/students` | `students[]` | application `students` Store records owned by the authenticated user's application family | `id`, `familyId`, `name`, optional `age`, optional `gender`, optional `school`, optional `educationSystem`, optional `grade`, optional `interest`, optional `goal`, `studentVersion`, optional `profileStatus`, optional `profileSchemaVersion`, optional `gradeStage`, `createdAt`, `updatedAt` |
| `GET /v1/me/students/:studentId` | `student` | one application `students` Store record after exact owner-family verification | same student fields as the list route |

No field is copied, inferred or transformed from a Canonical natural-person or
student row. Canonical contributes only the access decision. If the identity,
family mapping, current membership, ticket redemption or RLS check fails, the
application response is denied before Store data is returned.
