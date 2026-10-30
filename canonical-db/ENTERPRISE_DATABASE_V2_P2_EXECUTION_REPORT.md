# Phoenix Canonical PostgreSQL — Enterprise Database V2.0 P2 Execution Report

Date: 2026-10-30  
Scope: local isolated development only  
Branch: `codex/canonical-enterprise-v2-core`  
Verdict: **P2 SERVICE PROJECT / TASK / DELIVERY = PASS (LOCAL ENGINEERING)**  
HANDOFF_REQUIRED: 白虎（治理、隐私及正式运行边界复核）

## 1. Boundary actually observed

- The existing Canonical database and Migrations `0001`–`0027` were preserved byte-for-byte.
- No second Person, Family, Student, Client, authentication or session-context authority was created.
- Casework Case remains advisor collaboration authority; Learning Task remains Learning delivery authority. Neither was copied into Service Project.
- No Finance transaction table, `contract_id`, payment, refund, invoice or entitlement authority was invented.
- No Health table or Health release was enabled.
- Only synthetic data was used in disposable `--network none` PostgreSQL 16/17 containers.
- No production connection, Tencent connection, production secret, real data, deployment, merge or PR action occurred.

## 2. Forward-only Migration result

| Migration | SHA-256 | Actual role |
|---|---|---|
| `0028_service_project_task_delivery.sql` | `b8ec5d270d34da8f24423771b362d1dd6d3aa6c6f3d78cbd61b12968ebf6e8a2` | Creates the `service` authority, ten RLS-protected tables, Project/Subject/Domain/Assignment/Task APIs and immutable event ledgers. |
| `0029_service_party_milestone_delivery_api.sql` | `898079125502bd5406e64fe50744ea04fe846f519e26d00bd30fe4bbe695fb33` | Forward-only completion of Party, Milestone and Deliverable controlled lifecycles. It was required because 0028 had already been applied locally and therefore was not overwritten. |

Post-Migration catalog: **29 ledger rows / 73 business tables / 64 RLS policies**.

## 3. Implemented Service authority

| Table | Implemented capability | Boundary |
|---|---|---|
| `service.projects` | Multiple projects per Client/Family; optional verified Deal reference; controlled status transitions. | References canonical Client and Deal; no Finance contract authority. |
| `service.project_parties` | Person or Organization party, exactly one target, time-bounded. | A Person must be a current family member; Organization must be active; creates no data-access grant. |
| `service.project_subjects` | Multiple Subjects per Project and domain scope. | Always `REFERENCE_ONLY`; creates no Consent, guardian, advisor or document authority. |
| `service.project_domains` | Multiple business domains per Project. | Controlled vocabulary; does not create a new domain master. |
| `service.project_assignments` | Internal/external assignment to active ADVISOR, CHANNEL or SERVICE principals. | Assignment alone does not grant Subject/document access. |
| `service.tasks` | Exact states `PENDING / IN_PROGRESS / BLOCKED / COMPLETED / CANCELLED`. | Namespaced extensible task type; no Learning Task reuse or replacement. |
| `service.task_events` | Append-only Task lifecycle evidence. | Update/delete trigger rejects changes. |
| `service.project_milestones` | Controlled create and `PENDING → ACHIEVED/CANCELLED`. | Project-family and exact-service scoped. |
| `service.deliverables` | Controlled `DRAFT → READY → DELIVERED → ACCEPTED`, with withdrawal paths. | Optional Document must belong to the Project family and, when Subject-bound, the same Subject; no file storage authority. |
| `service.project_events` | Append-only Project, Party, Subject, Domain, Assignment, Task, Milestone and Deliverable events. | Update/delete trigger rejects changes. |

The runtime service authority is the exact active personless principal label `canonical_service_v2`. Direct application/reader/binder table privileges and all PUBLIC function execution are revoked. Every exposed write is a fixed-search-path `SECURITY DEFINER` function with family/context checks and allow/deny audit decisions.

## 4. Synthetic acceptance actually executed

Both PostgreSQL 16 and PostgreSQL 17 passed:

- clean `0001`–`0029` initialization;
- repeat execution with checksum verification;
- missing, extra and altered Migration refusal;
- atomic rollback;
- separate application and binder LOGINs with one-use tickets;
- exact service identity and wrong-service rejection;
- multiple Projects for one Family;
- multiple Subjects and Domains for one Project;
- controlled Party, Assignment, Milestone, Deliverable and Task lifecycles;
- cross-family Project/Subject refusal;
- direct table DML refusal;
- immutable Task/Project events;
- cross-Project Deliverable/Subject FK refusal;
- no side effects in Casework, Learning or Consent;
- no implicit sensitive-data permission from Project participation;
- dedicated backup LOGIN, SHA-256 manifest verification and fresh-cluster restore;
- source and restore containers with `network=none` and no published ports.

Final evidence:

| Evidence | SHA-256 |
|---|---|
| `evidence/v2.0-0029-pwsh-f10-pg16.txt` | `310dc74a8fba542b8cc2672150ea91ebd9b6833c608271d720d2935340585794` |
| `evidence/v2.0-0029-pwsh-f10-pg17.txt` | `7563489bd736f830bcaff0846c18f2741465dd4da8c2ea89ddb529613822144c` |
| `evidence/v2.0-0029-pwsh-audit-log-pg16.txt` | `285621867d3f9c2726163b7b8ac15cda6f4e079a18ab54abd36467df6f69145d` |
| `evidence/v2.0-0029-pwsh-audit-log-pg17.txt` | `446cafd35c52ff9b3d2c90e9e03cdc64836d4f8e6b0dae95e4ef620fc5ca46b5` |
| `evidence/v2.0-0029-pwsh-audit-reconcile-pg16.txt` | `63040e9223cb5da22c2e278e36f1e15ac64752d3e6e0981947a2f406428ad0d3` |
| `evidence/v2.0-0029-pwsh-audit-reconcile-pg17.txt` | `7b1e96485be2a8c2964c0d16e1fdcab798b8f36a285f04afeda44c4a9c1d3b67` |
| `evidence/v2.0-0029-local-upgrade-health.txt` | `4038848b9180d8c5a65b0855a330f60837d6f04eca59230f3499ff613ec2cef9` |

The existing local `phoenix_canonical_dev` PG16 and PG17 databases were upgraded forward to 0029 without resetting their volumes. A repeat run verified every checksum and both containers remained healthy.

## 5. Not implemented or not claimed

- Production readiness, production cutover and Tencent deployment: **HOLD**.
- Finance transaction ownership, Contract authority and transaction migration: **P3 evidence/design gate**.
- Health Patient/Person mapping, Consent, retention, medical boundary and Health release: **P4 HOLD**.
- Real staff, family, client, project, document or identity records: **not imported**.
- Project participation as an authorization grant: **explicitly not implemented**.
- Physical object storage, COS and real document delivery: **not connected**.

## 6. Unique next action

Complete the P3 Finance data-authority audit and object-ownership design without creating transaction tables or migrating transactions; then produce the P4 Health dependency gate. Both are documentation/evidence gates unless new approved facts authorize further forward Migrations.

