# Phoenix Canonical Phase 3 approval register

**Decision:** APPROVED FOR GREENFIELD CANONICAL IMPLEMENTATION  \
**Authorization event:** Founder instruction in the current Codex session, 2026-10-14 (Asia/Shanghai)  \
**Approval scope:** Synthetic PG16/17 implementation and a new Tencent-hosted Canonical database after local Phase 3 acceptance. No legacy or real-data migration.

| Effective source | SHA-256 | Approved clauses |
|---|---|---|
| `CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md` | `f89a1bbe3cff78ed96e8e6620fce7d41837ae4d30de0b9fd91929f2f6bcf4c93` | Identity/family FC-1–FC-5 replacement baseline; `auth`/ `core` ownership; UUIDv7/public/legacy mapping; trusted binder; Consent/guardian; Docs/Submission DS-1–DS-5; casework; Education/Identity core fields and states |

## Supersession and compatibility

This approval supersedes the local review candidates for new Canonical implementation only. It does not certify them as historical originals. If a recovered historical contract conflicts with this baseline, the new baseline remains authoritative for greenfield Canonical records until a later explicit amendment.

Legacy ID reconciliation, Founder OS/D1 reuse, Feishu migration, Operations asset reuse, real customer import, external object storage and production application token integration remain separate gates. Those holds do not block an empty greenfield Canonical database.

## Implemented migration evidence

| Migration | SHA-256 |
|---|---|
| `0001_foundation.sql` | `eea8d1deece72afdc3832d075fcfb42b71b4c1fe4fdccc8900104a0e0ca78a2d` |
| `0002_education_identity_skeleton.sql` | `bef7d9a902e8ad34491b7455987d7791667dcb8a5ab31945cf609a6aa97e4e7f` |
| `0003_core_consent_access.sql` | `7dc0c5060237fae9069915ba8a1ecc39323cf74ab8ea0d49dd832ef9d8330618` |
| `0004_casework_education_identity.sql` | `aec2be38c6ad363f5594d65016b8a2dfcb79fe76e77a225271379bb991a443e9` |
| `0005_documents_submissions.sql` | `7bd581d16bb8c21278bd5bc013496779fe08f509d84bf74b652e5ce3b21cdbec` |
| `0006_access_decision_api.sql` | `2a3d6cd19febd62b7128c9ad4a2d7c94abdb9a4e11d499f36f4050eb2c2ed9d8` |

Any byte change requires a new migration number and a new approval record. Applied files are immutable.
