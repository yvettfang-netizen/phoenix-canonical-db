# Health permission matrix and API contract — candidate

Status: DESIGN ONLY. No API or policy in this document is implemented or enabled.
All business FKs remain subject to the [dependency gate](README.md).

## Existing mechanisms to reuse

- Trusted context getters: `auth.current_principal_id()`,
  `auth.current_actor_person_id()`, `auth.current_family_id()`.
- Separate binder/runtime credentials and one-use tickets: `0007`/`0008`/`0012`
  define the ticket/context lifecycle; `0017` adds external identities and request
  tracing; `0018` hardens advisor scope and binder execution boundaries;
  `0023`–`0025` add the application family resolver and managed family-mapping
  lifecycle/lock ordering.
- `auth.write_context_is_live()` and the principal/channel checks in the latest
  migrations. A SERVICE principal may have no Person; never coerce its ID into
  a patient/member ID.
- `audit.record_access_event(...)` and latest
  `audit.record_write_decision(...)` implementation. Retain existing structured
  rollback-resistant audit behavior; log only action/resource/decision/reason/
  correlation metadata, never answer bodies, document keys or medical text.
- Verified `core.guardian_authorities` and `core.civil_capacity_history`.
  Existing GENERAL authority does not automatically establish medical consent.

Do not give runtime roles direct access to raw Health tables. Prefer the existing
domain pattern: forced RLS, exact grants to reviewed functions, fixed search_path,
protected owner privileges and controlled audited read/write entry points. RLS,
database role privileges and server authorization must all be tested. A custom
GUC or client-supplied member/family ID never creates an authenticated context.

## Permission matrix

All positive entries require an active trusted principal, current family,
patient-specific authority, applicable consent and exact project/case scope.
Every unspecified privilege defaults to denied.

| Actor | Consultation | Assessment summary / raw responses | Cases / appointments / tasks | Documents / claims | Consent administration |
|---|---|---|---|---|---|
| Patient | Own minimal request | Own authorized assessment; separate raw-answer read | Own authorized project/case | Explicit scope and fresh decision | Grant/revoke within verified capacity |
| Family administrator / other relative | No automatic access | No automatic summary or raw-answer access | Only patient-authorized service-status DTO | Denied without separate patient authority | Family admin role alone cannot grant |
| Verified guardian / legal proxy | Subject only after applicable authority check | Purpose-bound grant and capacity check | Explicit case/project scope | Explicit sensitive-data scope | Evidence and validity required; never infer proxy status |
| Assigned coordinator | Scoped request only | Raw answers denied by default | Active assignment plus patient grant | Only separately granted document/claim purpose | Cannot self-grant access |
| Medical translator | No general CRM/medical browse | Denied unless separately authorized | Minimum coordination details | Named translation scope, case and validity | Cannot expand consent |
| Named institution recipient | No directory-wide access | Denied by default | Explicit sharing scope only | Exact documents and destination allowed | Cannot delegate or widen grant |
| Ordinary CRM / Founder OS | Approved business request/aggregate DTO only | No raw answers | Minimal service delivery DTO | No raw medical or claim contents | No patient-consent override |
| Family OS | Authorized selected-family service status | Raw answers denied | Authorized reminder/progress DTO | No default documents or claims | Patient-directed controlled action only |
| General SERVICE / reader | No implicit Health authority | Denied | Denied | Denied | Denied |
| Dedicated Health runtime | Only via exact audited API | Explicit patient scope; no blanket service bypass | Required patient + project authorization | Fresh access authorization for every object request | Cannot bypass grantor verification |

Consent scopes must distinguish case read, document read, appointment
coordination, translation, claims assistance and sharing with a named provider.
Do not represent all six as a single generic `HEALTH_READ` permission.

## Proposed application mapping

Route names below are suggestions for review; no live request is made.
The gateway authenticates the caller and resolves authoritative IDs. It rejects
unknown request keys and arbitrary JSON before any DB operation. Resource IDs in
a route locate a target; they never authorize it. Mutations require idempotency,
bounded payloads and server-derived caller attribution.

| Candidate endpoint | Input / source | Output and boundary |
|---|---|---|
| `POST /api/health/consultations` | Closed service/channel vocabulary; explicit submit + consultation authorization | Minimal request ID/status. No answer payload, symptom text or automatic CRM lead |
| `POST /api/health/assessments` | Approved question version; authenticated subject/family resolution; explicit persistence consent | Assessment reference. Existing navigation tool must remain usable without silent persistence |
| `PUT /api/health/assessments/{id}/responses` | Approved question keys and closed answer values | Restricted write acknowledgment. No CRM forwarding or clinical score |
| `POST /api/health/assessments/{id}/complete` | Existing approved result contract | Navigation result only; no automatic consultation/lead creation |
| `POST /api/health/consultations/{id}/convert` | Dedicated scoped conversion actor and explicit user consultation authorization | Existing lead and service-project references; HOLD until their canonical APIs/FKs are identified |
| `GET /api/health/cases/{id}` | Patient + family + project/case scope | Minimal allowed case DTO; no disease/diagnosis/treatment fields |
| `POST /api/health/documents/{id}/access` | Current consent, assignment, patient, case and requested purpose | Server-proxied private access; DB holds no public download URL |
| `POST /api/health/consents` / `.../{id}/revoke` | Verified grantor capacity/proxy, named grantee, purpose, scope and exact resource binding | Controlled decision and audit reference; revoked/expired grant fails next decision |
| `GET /api/family/health-service-status` | Trusted current family and patient authorization | Allowlisted service status, appointment reminder and task progress only |
| `GET /api/founder/health-operations-summary` | Internal business role and scope | Controlled delivery/operating aggregates. No small-cell sensitive disclosure or patient clinical content |

The international-medical consultation path does not require an assessment ID or
fourteen answers. The family-planning path may use the Compass or a separate
consultation. Website service selection is not proof of patient consent.

## Files, revocation and retention

Use controlled private storage; `encryption_key_reference` is an opaque reference,
never encryption-key material. Private bytes are retrieved only after a fresh
server decision. A preissued bearer storage URL can remain usable after consent
revocation; immediate denial therefore requires an authorization proxy or an
equally revocable serving mechanism. Short TTL alone does not prove revocation.
An already downloaded copy cannot be recalled by database RLS.

Approval is still needed for concrete storage provider/key custody, per-class
retention periods, legal-hold interaction and deletion semantics. Prepare but do
not enable collection until these are explicit. Revocation, soft deletion and
retention expiry must stop later reads; authorized retention does not grant
ordinary operating users access. Do not reuse existing Identity/Education
document policies for Health without reviewed Health-specific scope.

External application observation for API mapping only: the inspected local website
has a transient Compass and a consultation-preparation demo. This is not evidence
of the deployed website or an approved revision. No website/Family OS/Founder OS
code was modified. Their owner must pin the approved contract and version before
wiring.
