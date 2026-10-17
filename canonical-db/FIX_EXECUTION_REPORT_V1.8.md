# Phoenix Canonical PostgreSQL — V1.8 执行报告（D7：FD-6 / FD-7 本地实现，0017）

**结论：PASS。**
- 补充 V1.3 批准的 FD-6 / FD-7 本地部分已全部实现（原指令 D7 / 第五批）；
- PG16 / PG17 完整 F10、0006→0017 升级路径、部署包加运维全流程演练均通过；
- 本地开发库已升级到 0017。

**执行：** Claude Code，2026-10-17 14:15–14:30 +0800，依据 `PHOENIX-DB-FINAL-CLOSEOUT-20261017` 授权。
**依据：** `phase2-gate/FOUNDER_DECISION_ADDENDUM_V1.3_FD6_FD7.md`（`956fcd5a…`）的"实施与验收要求"，以及 `CODEX_INSTRUCTION_V1.3_NEXT.md` 的 D7 节。
**边界：** 未连接腾讯，未创建任何云资源，告警只写本地文件，未推送远程，只用合成数据。

## 1. Migration 0017 `0017_external_identity_request_trace.sql`

**SHA-256：** `c701f74897ca13d503c8c165fd2182d77a06583afa832760dc80f8dd9524aab6`

| FD-6 规则 | 实现 |
|---|---|
| 第 3 条：外部身份按"签发方 + subject"唯一对应一个主体；只经管理接口；不自动开户；停用立即失效 | 新表 `auth.external_identities`：开启 RLS，任何角色都没有直接权限；同一签发方 + subject 只允许一条 ACTIVE。管理接口 `auth.register_external_identity` / `auth.disable_external_identity`：只允许 SERVICE 调用，FAMILY 主体须属于当前家庭，SERVICE 主体不能被映射，重复映射返回审计拒绝 `ALREADY_ACTIVE`。解析函数 `auth.resolve_external_identity` 只授予 binder；映射或主体任一不是 ACTIVE 时返回空 |
| 第 7 条：请求编号贯穿网关与数据库审计 | 新函数 `auth.current_request_nonce()`；`audit.access_events` 新增 `request_nonce` 列；`PHOENIX_AUDIT` 日志行末尾追加 `request_nonce=…`（放在行末，原有解析规则不受影响） |

## 2. FD-7 运维脚本（`deploy/tencent/`）

| 规则 | 脚本 | 实现 |
|---|---|---|
| 第 2 条：每日备份并校验 | `backup.sh` | 新增 `pg_restore --list` 可读性校验，通过才写 `.verified` 标记；清单格式不变 |
| 第 2 条：保留 14 天，至少保留 3 份 | `prune_backups.sh`（新增） | 默认只预演，`--apply` 才删除；最新 3 份已校验的备份永远保留；`--keep` 不得小于 3 |
| 第 4 条：恢复演练 | `restore_drill.sh`（新增） | 在一次性容器（`--network none`，没有端口，合成口令）中恢复最新的已校验备份；先校验清单摘要；核对账本与 Migration 文件逐条一致；记录耗时；报告写到 `drills/` |
| 第 5 条：日志按天轮转 | `compose.yaml` | `logging_collector=on`，每天一个文件 `postgresql-%Y-%m-%d.log`，权限 0600；容器日志限制为 20 MB × 5 |
| 第 5 条：审计提取与链式哈希，保留 ≥180 天 | `audit_extract.sh`（新增） | 按天提取 `PHOENIX_AUDIT` 到只追加文件（0400）；`chain.txt` 链式 SHA-256；已提取的日子拒绝重写；`--verify` 重算全部哈希；脚本从不删除提取文件 |
| 第 6 条：告警 | `alert_check.sh`（新增） | 覆盖 8 个条件：备份过期（>26h）、最新备份未校验、恢复演练失败或超过 35 天、数据库不可用、账本不一致、磁盘 >80%、审计链断裂、对账出现仅在日志中的记录；**只写本地文件** `alerts/`，有告警时退出码为 1 |

## 3. 安全加固（审计发现 R-L1）

建角色的 SQL 带着口令原文。出错时，PostgreSQL 会把出错语句和 PL/pgSQL 错误上下文写进服务器日志。`install.sh` 与 `restore.sh` 的建角色会话现在先设置 `log_min_messages = panic` 与 `log_min_error_statement = panic`。

## 4. 测试结果

| 项 | PG16 | PG17 | 证据 |
|---|---|---|---|
| 完整 F10（bash），含新增 `f10_v18_identity_pool.sh`（33 项断言） | PASS，退出码 0，PASS 228 项，无意外 FAIL | 同左 | `evidence/v1.8-f10-sh-pg16.txt`、`-pg17.txt` |
| FD-6：身份映射正反例；解析权限（app 被拒，binder 读不到表）；停用映射或主体后解析为空 | PASS | PASS | 同上 |
| FD-6：请求编号同时出现在审计行和服务器日志行 | PASS | PASS | 同上 |
| 连接池（同一后端）：清除后读到 0 行、写被拒；换绑家庭隔离；票据重复使用、过期、错主体、主体已停用，均被拒；事务级连接池隐患已演示 | PASS | PASS | 同上 |
| D-9 对账 | 日志 249 条，与数据库对上 248 条，仅在日志中 1 条（预期的回滚） | 同左 | 同上 |
| 升级路径 0006→0017（含阻断回滚与恢复） | PASS | PASS | `evidence/v1.8-upgrade-path-pg16.txt`、`-pg17.txt` |
| 部署包加运维全流程演练（14 步） | PASS，退出码 0 | 不适用（部署包用 PG16） | `evidence/v1.8-deploy-rehearsal.txt` |
| 开发库升级 0016→0017（先跑预检） | PASS | PASS | `evidence/v1.8-dev-db-upgrade.txt` |
| 安全目录审计 | PASS（见 `release/04`） | PASS | `evidence/v1.8-security-catalog-pg16.txt`、`-pg17.txt` |

**部署演练第 8–14 步的结果：**
- **备份：** 第二次备份带 `.verified` 标记（493 个条目）。
- **保留期清理：** 构造 4 个过期备份；预演不改动任何文件；执行后正好删掉 3 个未受保护的，保留最新 3 份已校验备份。
- **恢复演练：** `RESULT=PASS`，账本 17 条与文件一致，耗时 8 秒。
- **审计提取：** 当天提取 2 行，只有 ID 和代码；重复提取被拒；链校验通过。
- **告警检查：** 0 条告警。
- **篡改检测：** 改动审计文件后，链校验报出 `CHAIN_BROKEN`；告警报出 `AUDIT_CHAIN_BROKEN`，并因伪造行在数据库中没有对应记录，另报 `RECONCILE_LOG_ONLY`。
- **口令加固：** 失败的建角色语句，加固会话泄露 0 次，对照会话泄露 2 次；6 个部署口令在服务器日志中均为 0 次。

## 5. 测试与守卫改动

| 文件 | 改动 |
|---|---|
| `tests/foundation.sql` | 业务表数守卫 26→27（新增 `auth.external_identities`） |
| `tests/f10_ephemeral_init.sh` | 默认 Migration 数 17 |
| `tests/f10_ephemeral_restore.sh` | 恢复断言改为账本 17、表 27 |
| `tests/phase3_fresh_cluster_restore.ps1` | 表数守卫改为 27 |
| `tests/f10_local_acceptance.ps1` | 加入 v18 测试，用 0018 / 0017 做多文件、缺文件检查（本机没有 pwsh，NOT RUN） |
| `tests/f10_local_acceptance.sh` | 加入 v18 测试，增加服务器日志中请求编号的断言 |
| `tests/deploy_package_rehearsal.sh` | Migration 数改为动态取值；新增第 8–14 步运维演练 |
| `tests/security_catalog_audit.sql`（新增） | 只读的安全目录审计 |

## 6. 仍为 HOLD（不在本批授权内）

- 异地加密备份、告警外发渠道：依赖 G-4 / G-5；
- 在服务器上安装定时任务：依赖 G-8 与任务 B 的批准；
- 身份提供方、`iss`、`aud`、JWKS：由应用方提供（EV-7）；
- 网关侧的请求级日志：属于应用实现。
