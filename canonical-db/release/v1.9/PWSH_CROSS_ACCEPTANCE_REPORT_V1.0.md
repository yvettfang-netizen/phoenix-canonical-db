# PowerShell 跨路径验收报告 V1.0

**执行日期：** 2026-10-19（Asia/Shanghai）

**范围：** W-22；PostgreSQL 16 / 17；Migration 0001–0017；仅本地合成数据。

**结论：** **PASS**。PowerShell 路径已覆盖 0016、0017，未连接腾讯、未推送、未部署，也未创建 0018。

## 1. 执行基线

| 项 | 值 |
|---|---|
| 分支 | `codex/canonical-postgresql-phase1` |
| 工程与原始证据提交 | `072ea74cb24ff21361cf93e85a7a2bd443011d6f` |
| PowerShell | 7.6.5 |
| Docker Engine | 29.8.2，Linux/AMD64 |
| PG16 镜像 | `postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d` |
| PG17 镜像 | `postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3` |
| 数据边界 | 合成数据；一次性容器 `--network none`；无宿主端口 |

## 2. 实际执行结果

| 套件 | PG16 | PG17 | 关键结果 |
|---|---|---|---|
| `f10_local_acceptance.ps1` | PASS | PASS | 账本 17、表 27、RLS 策略 20；重复迁移、缺失/额外文件、漂移和原子回滚均按预期；分离 LOGIN、一次性票据、0016、0017、备份恢复通过 |
| `phase3_defect_regression.ps1` | PASS | PASS | F-01/F-02、T1–T3、T6/T6c–T6f、T7、T8/T8b、T12、T13、R-3/R-4 全部通过 |
| `phase3_pg_hba_auth_regression.ps1` | PASS | PASS | 本地 socket 无口令被拒；local/host 均为 SCRAM |
| `phase3_fresh_cluster_restore.ps1` | PASS | PASS | backup LOGIN 导出；新集群恢复后账本 17、表 27、策略 20、角色 10；六套基础回归通过 |
| D-9 审计对账 | PASS | PASS | 日志 249，持久化匹配 248，1 条为预期的客户端回滚记录 |

F10 的每版原始记录各有 188 行 `PASS`，意外失败为 0。迁移库存探针中出现的 `FAIL migration inventory`、漂移拒绝与强制原子失败是预期负向测试，随后均有对应 `PASS ... refused/rejected`。

全新集群启动轮询初次出现的 socket 不存在信息发生在 PostgreSQL 尚未就绪时；脚本随后成功连接并完成目录与回归断言，最终进程返回 0。

## 3. 原始命令

```powershell
pwsh -NoLogo -NoProfile -File canonical-db/tests/f10_local_acceptance.ps1 -Version 16
pwsh -NoLogo -NoProfile -File canonical-db/tests/f10_local_acceptance.ps1 -Version 17
pwsh -NoLogo -NoProfile -File canonical-db/tests/phase3_defect_regression.ps1 -Version 16
pwsh -NoLogo -NoProfile -File canonical-db/tests/phase3_defect_regression.ps1 -Version 17
pwsh -NoLogo -NoProfile -File canonical-db/tests/phase3_pg_hba_auth_regression.ps1 -Version 16
pwsh -NoLogo -NoProfile -File canonical-db/tests/phase3_pg_hba_auth_regression.ps1 -Version 17
pwsh -NoLogo -NoProfile -File canonical-db/tests/phase3_fresh_cluster_restore.ps1 -Version 16
pwsh -NoLogo -NoProfile -File canonical-db/tests/phase3_fresh_cluster_restore.ps1 -Version 17
```

## 4. 原始证据

- F10：`evidence/v1.9-pwsh-f10-pg16.txt`、`evidence/v1.9-pwsh-f10-pg17.txt`
- 审计对账：`evidence/v1.9-pwsh-audit-log-pg16.txt`、`-pg17.txt`；`v1.9-pwsh-audit-db-ids-*`；`v1.9-pwsh-audit-reconcile-*`
- 缺陷回归：`evidence/v1.9-pwsh-phase3-defect-pg16.txt`、`-pg17.txt`
- SCRAM：`evidence/v1.9-pwsh-hba-pg16.txt`、`-pg17.txt`
- 全新集群恢复：`evidence/v1.9-pwsh-fresh-restore-pg16.txt`、`-pg17.txt`

证据扫描未发现口令、私钥或云密钥模式。

## 5. 脚本修正与清理

1. PowerShell F10 使用独立 `v1.9-pwsh-*` 资源与证据名，避免覆盖历史 V1.8 证据。
2. F10、fresh restore、HBA 的一次性容器清理增加 `-v`，同步删除容器匿名卷。
3. 本轮结束时，匹配本轮命名的一次性容器数量为 0；历史悬空匿名卷仍为 125，本轮没有清理这些旧卷，也没有新增。
4. PG16/17 本地 Compose 开发容器保持健康，且未发布宿主端口。

## 6. 门禁状态

- W-22：**CLOSED / PASS**。
- W-26：脚本侧新增匿名卷问题已关闭；历史 125 个卷仍等待明确清单与删除决定。
- N-5：不再需要在 bash 与 pwsh 之间做发布取舍；两条路径均已有 PG16/17 证据。
- 0018：仍为 **HOLD**。N-2（E-R6 正式进入 0018）与 D-2（撤销旧 binder 入口）尚未获 Founder 批准。
