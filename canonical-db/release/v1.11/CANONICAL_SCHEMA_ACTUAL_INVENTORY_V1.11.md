# Canonical Schema actual inventory V1.11

**Verified:** 2026-10-20, local PG16 and PG17 `phoenix_canonical_dev`  
**Evidence:** `evidence/v1.11-0019-local-upgrade-pg16.txt`, `evidence/v1.11-0019-local-upgrade-pg17.txt`  
**Deployment status:** local isolated development only; Tencent task B remains paused.

## Catalog

| Item | Actual |
|---|---:|
| Canonical migrations | 20 (`0001`–`0020`) |
| Business tables | 34 |
| RLS policies | 27 |
| Education domain rows in both development databases | 0 |

The seven tables added by 0019 are:

- `education.institution`
- `education.program`
- `education.academic_record`
- `education.score_record`
- `education.language_test`
- `education.plan`
- `education.plan_target`

`education.applications` now has nullable `institution_id` and `program_id` references while retaining its display labels.

## Enforced boundaries

- Institution and program versions are append-only. Controlled APIs can create `DRAFT` versions only.
- There is no activation API. Initial master data and two-person activation remain HOLD.
- Academic and language evidence must be an unwithdrawn `EDUCATION` document for the same family and student.
- Family and verified guardian access requires EDUCATION authority; advisor access requires an active open/paused assignment plus active `EDUCATION_CASE` Consent.
- A SERVICE context can write through controlled functions for its bound family but receives zero Education student-record rows through RLS.
- The application role has no direct Education table DML.

## Migration hashes

| Migration | SHA-256 |
|---|---|
| `0019_education_master_and_records.sql` | `425b72e7c62916da9c8c22624dc3d2beca547a0b8b96297a68604ecf574cec94` |
| `0020_education_service_read_hardening.sql` | `20435da63432175396bf118d6b6b3b5c9865e7b8b8ba8343f0da84f273d1eedd` |

