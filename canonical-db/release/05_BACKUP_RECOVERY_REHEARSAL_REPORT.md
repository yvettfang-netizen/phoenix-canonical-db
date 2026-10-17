# 05 · 备份与恢复演练报告

**基线：** `c5e81e6`，0001–0017。
**环境：** 本机 Docker 29.8.2，一次性容器或独立的 compose 项目，合成数据。

**规则来源：** 补充 V1.3 的 FD-7，空库阶段适用：
- RPO 24 小时，RTO 8 小时，回滚窗口 24 小时；
- 每天 03:00 备份并校验，本地保留 14 天，至少保留 3 份；
- 每月一次、每次发布前一次做恢复演练；
- 审计日志按天做链式哈希，保留不少于 180 天。

## 1. 已执行的演练

| # | 演练 | 方法 | 结果 | 证据 |
|---|---|---|---|---|
| R1 | F10 全新集群恢复（PG16 / PG17） | 专用 backup LOGIN `pg_dump -Fc` → 计算摘要 → 在全新一次性集群（只读挂载备份卷）恢复 → 9 个恢复后套件（含目录权限回归、不可修改触发器、T3 撤回触发器） | PASS：账本 17、表 27、策略 20、合成人员 8、导出条目 493 | `evidence/v1.8-f10-sh-pg16.txt` / `-pg17.txt`（"backup LOGIN dump and fresh-cluster restore"节） |
| R2 | 部署包 `backup.sh` → `restore.sh` 到全新卷 | 第二个 compose 项目，全新卷；`restore.sh` 校验清单摘要，补齐角色后 `pg_restore --exit-on-error` | PASS：账本 17、表 27、策略 20；恢复后健康检查正常；1 个合成家庭和 1 个服务主体保留 | `evidence/v1.8-deploy-rehearsal.txt` 第 5–7 步 |
| R3 | 篡改备份 | 修改清单中的摘要后执行 `restore.sh` | 被拒（`backup manifest digest mismatch`），在接触数据库之前就退出 | 同上，第 6 步 |
| R4 | 备份可读性校验 | `backup.sh` 用 `pg_restore --list` 读取目录：493 个条目，写入 `.verified` 标记 | PASS | 同上，第 5、8 步 |
| R5 | 保留期清理 | 构造 4 个过期备份（其中 1 个未校验）：预演 → 执行 | 预演不改动文件；执行后正好删除 3 个，保留最新 3 份已校验备份 | 同上，第 9 步 |
| R6 | 恢复演练脚本 | `restore_drill.sh`：一次性容器、`--network none`；账本与 Migration 文件逐条核对 | `RESULT=PASS`，`LEDGER_MATCHES_MIGRATION_FILES count=17`，**耗时 8–9 秒**（两次运行；空库阶段的 RTO 实测，远低于 8 小时目标） | 同上，第 10 步；报告写入 `drills/` |
| R7 | 升级失败后的恢复 | 0006 库带合成数据加阻断行 → 升级在 0012 整体回滚 → 数据不变 → 移除阻断 → 升级到 0017 | PASS（PG16 / PG17） | `evidence/v1.8-upgrade-path-pg16.txt` / `-pg17.txt` |
| R8 | 审计链 | 当天提取 → 链校验 → 篡改 → `CHAIN_BROKEN` 并触发告警 | PASS | `evidence/v1.8-deploy-rehearsal.txt` 第 11–13 步 |

## 2. 恢复后有效性

恢复后，权限和触发器都已实际验证（R1 的 9 个套件）：
- `f10_catalog_regression.sql`：app 写权限 0、PUBLIC 执行 0、SECURITY DEFINER 都有 `search_path`；
- D6 不可改写触发器、T3 撤回触发器：恢复后仍然生效；
- 基线 RLS 与可信上下文测试通过。

R2 中，恢复后的库还验证了 reader 运行账号的健康检查，以及 backup 运行账号可读。

## 3. 目标对照（空库阶段）

| 目标 | 状态 |
|---|---|
| RPO 24 小时（每天一次备份） | **脚本就绪**；定时任务尚未安装到服务器（HOLD：G-8 / 任务 B） |
| RTO 8 小时 | 实测恢复演练 8–9 秒（空库加合成数据），**本地达标**；生产数据量下需要重测 |
| 本地保留 14 天、至少 3 份 | `prune_backups.sh` 已验证 |
| 每月一次、每次发布前一次恢复演练 | `restore_drill.sh` 已验证；排期写入 `07` |
| 审计日志保留不少于 180 天 | `audit_extract.sh` 只追加、从不删除；异地副本 HOLD（G-4） |
| 异地加密备份（30 天，对象锁定，境内） | **HOLD**：G-4 凭据轮换后才创建存储桶和子账号 |

## 4. 已知限制

- **备份方式：** 只有逻辑备份（`pg_dump`），没有 WAL 归档 / PITR。按 FD-7，导入真实数据前须重新决定。
- **加密：** 备份文件本身没有加密，本地权限为 0600 / 0700。加密只在异地上传前进行（FD-7 第 3 条），尚未实施。
- **备份角色：** 带 BYPASSRLS，属于必要的高权限账号，其凭据按 F-16 管理。
