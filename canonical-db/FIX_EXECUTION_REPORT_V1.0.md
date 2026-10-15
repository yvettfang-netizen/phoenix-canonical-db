# Phoenix Canonical PostgreSQL — Audit Fix Execution Report V1.0

**执行范围：** 现有工作树 `codex/canonical-postgresql-phase1`，仅本地隔离环境。  
**日期：** 2026-10-15（Asia/Shanghai）  
**结论：** `PHASE 3 AUDIT FIXES = CONDITIONAL PASS`  
**腾讯云：** 本轮未连接、未部署、未更新。  
**真实数据/口令：** 未使用；报告与证据文件不含口令值。

## 1. 证据规则

本报告只把实际执行命令及其原始输出作为工程证据。原始输出保存在 `canonical-db/evidence/`，包括：

- `foundation-postfix-pg16.txt` / `foundation-postfix-pg17.txt`
- `phase3-defect-regression-pg16.txt` / `phase3-defect-regression-pg17.txt`
- `phase3-fresh-restore-pg16-*.txt` / `phase3-fresh-restore-pg17-*.txt`（以最新成功 transcript 为准）
- `phase3-pg-hba-pg16.txt` / `phase3-pg-hba-pg17.txt`
- `audit-migration-pg16.txt` / `audit-migration-pg17.txt`
- `audit-backup-pg16.txt` / `audit-backup-pg17.txt`
- `shell-static-checks.txt`、`compose-static-checks.txt`

所有回归测试仅使用合成数据，测试结束后由精确 allowlist 的 reset 流程清理测试库。恢复演练使用一次性容器并在 finally 中删除容器、dump 和 manifest。

### 实际执行命令

```text
pwsh -File .\canonical-db\scripts\db.ps1 -Action test -Version 16
pwsh -File .\canonical-db\scripts\db.ps1 -Action test -Version 17
pwsh -File .\canonical-db\tests\phase3_defect_regression.ps1 -Version 16
pwsh -File .\canonical-db\tests\phase3_defect_regression.ps1 -Version 17
pwsh -File .\canonical-db\tests\phase3_fresh_cluster_restore.ps1 -Version 16
pwsh -File .\canonical-db\tests\phase3_fresh_cluster_restore.ps1 -Version 17
pwsh -File .\canonical-db\tests\phase3_pg_hba_auth_regression.ps1 -Version 16
pwsh -File .\canonical-db\tests\phase3_pg_hba_auth_regression.ps1 -Version 17
pwsh -File .\canonical-db\scripts\db.ps1 -Action audit-migration -Version 16
pwsh -File .\canonical-db\scripts\db.ps1 -Action audit-migration -Version 17
pwsh -File .\canonical-db\scripts\db.ps1 -Action audit-backup -Version 16
pwsh -File .\canonical-db\scripts\db.ps1 -Action audit-backup -Version 17
```

每条命令的未删节输出均保存在上面的对应 evidence 文件。最新成功的全新集群 transcript 是 `phase3-fresh-restore-pg16-263c6464d7e64803a5c168cbc6d9527f.txt` 与 `phase3-fresh-restore-pg17-6cbd95b5ba3f43efb44ad6dcef41e3e0.txt`。

## 2. Migration

新增唯一 Canonical migration：

| 文件 | SHA-256 |
|---|---|
| `migrations/canonical/0007_security_boundary_fixes.sql` | `49ec737393a4a4bc5f1e287add369db4f04fbde1c021521e8b4cf781f966ff93` |

`0001`–`0006` 工作树字节未改变，当前 SHA-256 为：

```text
0001_foundation.sql eea8d1deece72afdc3832d075fcfb42b71b4c1fe4fdccc8900104a0e0ca78a2d
0002_education_identity_skeleton.sql bef7d9a902e8ad34491b7455987d7791667dcb8a5ab31945cf609a6aa97e4e7f
0003_core_consent_access.sql 7dc0c5060237fae9069915ba8a1ecc39323cf74ab8ea0d49dd832ef9d8330618
0004_casework_education_identity.sql aec2be38c6ad363f5594d65016b8a2dfcb79fe76e77a225271379bb991a443e9
0005_documents_submissions.sql 7bd581d16bb8c21278bd5bc013496779fe08f509d84bf74b652e5ce3b21cdbec
0006_access_decision_api.sql 2a3d6cd19febd62b7128c9ad4a2d7c94abdb9a4e11d499f36f4050eb2c2ed9d8
```

## 3. F 编号逐项结果

| F | 修改 / 实际验收 | 结果 |
|---|---|---|
| F-01 | `auth.session_contexts` 增加 `backend_start`；查询同时核验 PID 与启动时间；绑定/清理时删除过期及不存在后端；回归覆盖 PID 相同、启动时间不同和断开重连。 | **PASS**，PG16/17，`phase3-defect-regression-*` |
| F-02 | 新增一次性、≤60 秒、指定目标 principal 的 `auth.context_exchange_tickets`；binder 签发、app 独立 LOGIN 兑换，兑换即删除；app 无自行 bind 权限。 | **PASS**，正确、伪造、过期、错目标、重复兑换均拒绝；PG16/17 |
| F-03 | advisor assignment 读取必须经 case 的 `family_id = current_family_id()`，并限制有效分配。 | **PASS**，T1，PG16/17 |
| F-04 | people/student/membership/family/assignment policy 收紧至家庭、授权 subject 或有效 advisor assignment。Consent 是否额外要求仍是 Founder 决定，未自行假设。 | **PASS（机制）/HOLD（Consent 决定）**，T2/T3 |
| F-05 | 撤销 app/reader 对 `audit.record_access_event` 的 EXECUTE 与直接 INSERT；只保留受控授权函数内部写审计。 | **PASS**，T7，PG16/17 |
| F-06 | consent/assignment/guardian 使用 active partial unique index；历史行不可改回 ACTIVE；assignment/guardian 增加生命周期状态与再激活拒绝触发器。 | **PASS**，T6，PG16/17 |
| F-07 | submission manifest 触发器校验 target 存在、family 和 subject 一致。 | **PASS**，T8/T8b，PG16/17 |
| F-08 | 仅提交 `F08_DOCUMENT_PURGE_DESIGN_DRAFT.md`；未授予运行时清除权限，保留期/清除授权依赖 DS-5/EV-6。 | **HOLD**，需 Founder 决定 |
| F-09 | EDUCATION 文档映射到 EDUCATION 监护范围；GENERAL 不覆盖 IDENTITY_SENSITIVE。GENERAL 是否覆盖身份敏感数据仍列为 Founder 决定。 | **PASS（默认拒绝）/HOLD（语义决定）**，T13，PG16/17 |
| F-10 | 仅提交 `F10_APPLICATION_WRITE_API_DESIGN_DRAFT.md`；本轮未生成写入 migration。 | **HOLD**，需业务写入契约 |
| F-11 | `phase3_fresh_cluster_restore.ps1`：backup role 导出、全新 PG16/17 容器恢复、ledger=7、tables=25、policies=20、roles=10，并运行全部既有验收。 | **PASS**，最新 PG16/17 transcript |
| F-12 | local/Tencent compose 改为 `auth-local=scram-sha-256`；health/backup/install/restore 使用 0600 pgpass；新增 fresh-container HBA 回归；`PGPASSWORD` 未使用。 | **PASS**，PG16/17 HBA evidence；Tencent volume 切换仅形成方案 |
| F-13 | 恢复前校验 manifest 摘要；dump 或 manifest 篡改均拒绝并保留恢复库；报告明确 manifest 未签名。定时、异地、保留期、加密依赖 FD-7。 | **PASS（完整性）/HOLD（运维策略）** |
| F-14 | deploy/tencent 修改、报告及本轮文件纳入本地提交；当前本轮不部署，因此不存在“腾讯当前运行版本 = 本提交”的证据。 | **PASS（本地提交）/HOLD（部署映射）** |
| F-15 | local PG16/PG17 compose 使用固定 `sha256` digest；Tencent compose 保留相同 PG16 digest。 | **PASS**，compose config evidence |
| F-16 | `deploy/tencent/.env` 未读取、未删除、未输出；提交 `DEPLOYMENT_CREDENTIAL_STORAGE_PROPOSAL_V1.0.md`，等待 Founder 选择安全存放方式。 | **HOLD** |
| F-17 | 合同状态原样保留；Family Context / Founder OS 原件未补造。 | **HOLD**，Founder 未签署 |
| F-18 | 未选择公开 ID 前缀；现有约束继续 fail-closed。 | **HOLD**，需 Founder 决定 |
| F-19 | health 使用只读 reader runtime；backup 使用 BYPASSRLS、NOSUPERUSER backup runtime；无 migrator/bootstrap。 | **PASS**，shell-static-checks + HBA/restore evidence |
| F-20 | install.sh 增加外层 BEGIN/COMMIT/ROLLBACK 检查；本地迁移脚本同步拒绝嵌套事务。 | **PASS**，shell-static-checks + audit-migration PG16/17 |

## 4. PG16/PG17 实际结果

两版本均实际运行：

1. 0001–最新 migration 首次执行及重复执行；
2. migration 漂移拒绝和原子回滚；
3. 原有 foundation/RLS/docs/contract/trusted-context/phase3 acceptance；
4. 新增 F-01/F-02/F-03/F-04/F-05/F-06/F-07/F-09 分离 LOGIN 回归；
5. backup digest/provenance 篡改拒绝；
6. backup role → 全新一次性容器恢复；
7. 新鲜容器 local socket 无 pgpass 拒绝、SCRAM HBA 检查通过。

恢复后实际目录统计：`ledger=7`、`tables=25`、`policies=20`、`roles=10`。

## 5. 已知本地开发库证据 HOLD

现有 `phoenix_canonical_dev` 曾在本轮早期应用过旧版本 0007，其 ledger 摘要为：

```text
5fcff42cce9df982bef9ee6b857126545b4246f76778dd89dd7e80802a5aee9a
```

当前工作树 0007 摘要为 `49ec737393a4a4bc5f1e287add369db4f04fbde1c021521e8b4cf781f966ff93`。为遵守“不修改已应用 migration、不中断既有开发库”的边界，本轮没有改账本、没有 DROP/重建该数据库。所有最终证据来自全新 allowlisted 测试库和一次性恢复容器。后续如要继续使用该开发库，必须先经 Founder 确认采用新的本地开发卷/数据库轮换方案。

## 6. Founder 决定清单（本轮不代决）

- ADVISOR / PARTNER 读取基本信息是否还需要 Consent（F-04）；
- GENERAL 监护范围是否覆盖 `IDENTITY_SENSITIVE`（F-09）；
- 公开 ID 前缀选择（F-18）；
- F-10 写入 API 草案批准；
- F-08 清除角色、保留期、审批和审计要求；
- F-13 备份目的地、保留期、RPO/RTO、加密与签名策略（FD-7）；
- F-16 本机/腾讯部署凭据的安全存放方式。

## 7. 未执行事项

- 未连接腾讯云、未更新腾讯数据卷、未运行 install.sh；
- 未迁移旧库、Founder OS、Operations OS、真实学生/家庭/身份文件；
- 未读取或输出 `deploy/tencent/.env`；
- 未 push、merge、创建 PR 或部署；
- 未将任何草案标记为 EFFECTIVE/APPROVED。

## 8. 本地提交

本轮工程修复已创建本地提交 `eea5ac62da4f26d5c04cc1f6f1be1aa0895448c6`（`fix(canonical-db): close audit findings with 0007`）。本报告的回填提交随后产生；最终工作树仍只保留本地提交，不会 push、merge 或改变 PR 状态。

