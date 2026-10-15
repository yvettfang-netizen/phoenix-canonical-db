# Phoenix Canonical PostgreSQL — 复审缺陷修复执行报告 V1.1

**日期：** 2026-10-15（Asia/Shanghai）
**范围：** `codex/canonical-postgresql-phase1` 本地工作树、合成数据、PG16/17 专用测试库。
**工程结论：** `R-1–R-4 LOCAL FIX = PASS`；`PRODUCTION READY = HOLD`。
**工程提交：** `77a757efb444e8d07bcbdea1c5a24abd09a6296c`（`fix(canonical-db): close reaudit expiry and cleanup findings`）。
**部署：** 未连接或更新腾讯云；未执行 R-6 开发库重建；未推送、合并、建 PR 或导入真实数据。

## 1. 依据与字节边界

依据为 `phase2-gate/CLAUDE_CANONICAL_DATABASE_REAUDIT_REPORT_V1.1.md` 第 4 节及附录 T6c–T6f。它是独立复审证据，不是业务合同批准件。本轮只新增 `migrations/canonical/0008_expiry_and_ephemeral_cleanup.sql`；`0001`–`0007` 未修改。完整哈希原始输出见 [`evidence/migration-hashes-v1.1.txt`](evidence/migration-hashes-v1.1.txt)。

`migrations/canonical/.gitattributes` 将该目录 SQL 固定为 LF 换行，避免 Windows Git 自动换行改变摘要；检查后 0001–0008 的工作树哈希与本轮证据一致。Git 属性和 0008 哈希的原始输出见 [`evidence/git-line-endings-v1.1.txt`](evidence/git-line-endings-v1.1.txt)。

| Migration | SHA-256 |
|---|---|
| `0008_expiry_and_ephemeral_cleanup.sql` | `51215c0b4d76e242c28197187bf1e017362700128ddd562e2da5d64980a8588d` |

## 2. R 编号、实际修改与结果

| 项 | 0008 中的机制 | PG16 / PG17 实测 | 结果 |
|---|---|---|---|
| R-1 | Consent、顾问分配和监护授权在 INSERT 时计算到期状态；新的 ACTIVE 行写入前，将同一唯一键下自然过期的 ACTIVE 行转为 EXPIRED。受限的 `auth.sweep_expired_authorizations()` 可执行全表维护。授权判定仍校验时间范围，未清理的过期行不能授权。 | T6c：自然过期 Consent 可新授，已过期 INSERT 自动变 EXPIRED；T6d：分配和监护授权的已过期 INSERT 与自然过期后新授均通过，旧行 EXPIRED、新行 ACTIVE。 | **PASS（本地合成）** |
| R-2 | 顾问分配和监护授权对旧行的撤销/过期状态做终态保护；撤销后不能清空 `revoked_at`，自然过期或已标记 EXPIRED 后不能延长 `valid_until`。 | T6e / T6f：两类记录的撤销回滚和过期续期都被拒绝，终态未改变。 | **PASS（本地合成）** |
| R-3 | 四个指定函数均 `REVOKE EXECUTE FROM PUBLIC`；`core.can_read_subject_basics(uuid)` 仅显式授予 app/reader。新清理函数和触发器函数也撤销 PUBLIC 执行权。 | 目录检查四个函数的 PUBLIC EXECUTE 为 0；独立 app/reader LOGIN 权限检查通过。 | **PASS（本地合成）** |
| R-4 | `auth.cleanup_ephemeral_state()` 删除不存在后端或已过期的会话上下文及过期票据；binder 可调用，票据签发/兑换时也自动调用。 | 合成残留各 1 行，binder 独立 LOGIN 清理返回 `1|1`，之后两表指定行数均为 0。 | **PASS（本地合成）** |

清理在票据流量到来时自动发生，也提供可由外部调度器调用的受限入口。本轮未在腾讯或本地开发库安装定时任务；生产调度、监控和保留策略仍需后续运维门禁。

T6c–T6f 使用实际 `phoenix_canonical_backup_local` LOGIN，独立于 bootstrap、binder、app 和 reader。仅在精确命名的可重置测试库中临时授予三张表的写权限及 UUID 校验函数执行权；测试库最后被重置，正式 app 写入权限未开放。F-02 的 binder 与 app 票据流程也继续使用分离的真实 LOGIN 连接。

## 3. 原始命令与原始输出

以下命令在上述工作树根目录实际执行。`Tee-Object` 保存未删节 stdout/stderr；原始文件中的预期 `SYNTHETIC FORCED MIGRATION FAILURE` 是原子回滚探针的输入，后续 `PASS` 证明它未留下迁移残留。

```powershell
pwsh -NoLogo -NoProfile -File canonical-db/tests/phase3_defect_regression.ps1 -Version 16 *>&1 | Tee-Object -FilePath canonical-db/evidence/phase3-defect-regression-v1.1-pg16.txt
pwsh -NoLogo -NoProfile -File canonical-db/tests/phase3_defect_regression.ps1 -Version 17 *>&1 | Tee-Object -FilePath canonical-db/evidence/phase3-defect-regression-v1.1-pg17.txt
pwsh -NoLogo -NoProfile -File canonical-db/scripts/db.ps1 -Action audit-migration -Version 16 *>&1 | Tee-Object -FilePath canonical-db/evidence/migration-audit-v1.1-pg16.txt
pwsh -NoLogo -NoProfile -File canonical-db/scripts/db.ps1 -Action audit-migration -Version 17 *>&1 | Tee-Object -FilePath canonical-db/evidence/migration-audit-v1.1-pg17.txt
pwsh -NoLogo -NoProfile -File canonical-db/scripts/db.ps1 -Action reset-test -Version 16 *>&1 | Tee-Object -FilePath canonical-db/evidence/reset-test-v1.1-pg16.txt
pwsh -NoLogo -NoProfile -File canonical-db/scripts/db.ps1 -Action reset-test -Version 17 *>&1 | Tee-Object -FilePath canonical-db/evidence/reset-test-v1.1-pg17.txt
```

| 命令/证据 | 原始输出中可核对的结果 |
|---|---|
| [PG16 回归](evidence/phase3-defect-regression-v1.1-pg16.txt) / [PG17 回归](evidence/phase3-defect-regression-v1.1-pg17.txt) | 两版均 `APPLIED ... 0001–0008`、`SKIP ... 0001–0008 checksum verified`、六套既有合成探针 PASS；T6c/T6d/T6e/T6f、R-3、R-4 和既有 F/T 回归均 PASS；最后 `RESET phoenix_canonical_test_16/17`。 |
| [PG16 迁移审计](evidence/migration-audit-v1.1-pg16.txt) / [PG17 迁移审计](evidence/migration-audit-v1.1-pg17.txt) | 两版均 `PASS ... atomic migration rollback` 与 `PASS ... applied-migration checksum drift refusal`。 |
| [PG16 最终重置](evidence/reset-test-v1.1-pg16.txt) / [PG17 最终重置](evidence/reset-test-v1.1-pg17.txt) | 最后再次执行精确测试库重置，均输出 `RESET phoenix_canonical_test_16/17`。 |
| [容器状态](evidence/container-status-v1.1.txt) / [数据库版本](evidence/postgres-versions-v1.1.txt) | PG16.15 与 PG17.11 容器均 healthy；Compose 仅显示容器内部 `5432/tcp`，没有宿主机发布端口。 |
| [Migration 哈希](evidence/migration-hashes-v1.1.txt) / [证据凭据扫描](evidence/credential-scan-v1.1.txt) | 八个文件的 SHA-256 已记录；本轮输出文件未匹配口令赋值模式。 |

首次 PG16 运行因合成测试 LOGIN 对 `core.is_uuid_v7` 缺执行权限而失败，原始失败输出保留在 [attempt1](evidence/phase3-defect-regression-v1.1-pg16-attempt1.txt)。仅补测试库临时权限后，第二次运行通过，见 [attempt2](evidence/phase3-defect-regression-v1.1-pg16-attempt2.txt)；最终增加已过期 INSERT 和监护授权自然过期断言后，两版最终回归重新通过。没有删改失败记录。

## 4. 已验证范围与未验证范围

- **已验证：** 全新 PG16/17 测试库顺序应用 0001–0008、重复执行、既有六套合成验收、分离 LOGIN 的缺陷回归、迁移漂移拒绝及原子回滚。
- **已验证：** 测试结束后只保留空的 allowlist 测试库；本轮没有留下合成业务行或临时验收 schema。开发数据库 `phoenix_canonical_dev` 没有被迁移或重建。
- **未在本轮重跑：** 全新集群备份恢复和 PG HBA 演练。`phase3_fresh_cluster_restore.ps1` 的迁移数量断言已随 0008 改为 8，但本报告不把该改动当作已执行的恢复证据。
- **R-6 HOLD：** 复审报告记录现有 PG16/17 开发库的 0007 账本摘要与当前文件不一致，旧数据卷本地认证仍为 trust。本轮未复查或重建这些数据卷，也不把现有开发库作为 0008 验收证据。
- **生产 HOLD：** 腾讯运行时、真实数据、Web 鉴权、应用写入 API、业务合同/ID 前缀、备份策略与生产切换均未在本轮批准或实施。合同状态保持原样，Codex 草案不标为 EFFECTIVE/APPROVED。

**本轮结论：** 0008 对复审 R-1 至 R-4 的本地合成验收通过；数据库整体仍不得用于生产业务切换。
