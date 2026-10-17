# 04 · 安全与隔离审计（Security & Isolation Audit）

**对象：** Migration 0001–0017（当前 HEAD 见 `10_FINAL_ENGINEERING_HANDOVER_REPORT.md`）。
**方式：**
1. 目录审计：用 `tests/security_catalog_audit.sql`，在两个已升级到 0017 的本地开发库上运行（PG16 / PG17，结果一致）；
2. 行为测试：F10 完整回归，使用分离 LOGIN、一次性票据、合成数据、一次性容器；
3. 代码审读：0012–0017。

**环境：** PG 16.15 / 17.11，Docker 29.8.2，本机 Windows（git-bash）。
**证据：**
- `evidence/v1.8-security-catalog-pg16.txt`、`-pg17.txt`；
- `evidence/v1.8-f10-sh-pg16.txt`、`-pg17.txt`；
- `evidence/claude-v1.6-closeout-pg16.txt`、`-pg17.txt`。

## 1. 登录角色分离与最小权限（目录事实）

| 检查 | 结果 | 结论 |
|---|---|---|
| 能力角色（`phoenix_canonical_app` / `reader` / `context_binder` / `migrator`） | 都是 NOLOGIN，非超级用户，没有 BYPASSRLS / CREATEROLE / CREATEDB | PASS |
| 登录账号（`*_local`，部署时为 `*_runtime`） | 各自只继承一个能力角色：`inherit=true`、`set=false`、`admin=false`，不能 `SET ROLE` | PASS |
| backup 登录 | 继承 `pg_read_all_data` + BYPASSRLS，只读；不能写表，不能建对象 | PASS（设计如此，用于整库导出） |
| app 对 27 张业务表的写权限 | INSERT / UPDATE / DELETE / TRUNCATE / TRIGGER / REFERENCES 全为 0；只对 19 张带 RLS 的表有 SELECT | PASS：写入只能经受控函数 |
| reader | 对 20 张表有 SELECT：19 张带 RLS 的业务表，加迁移账本；没有任何写权限 | PASS |
| binder / migrator 对表 | 没有任何权限 | PASS |
| 建对象权限 | app / reader / binder / PUBLIC 在所有业务 schema 上都没有 CREATE | PASS |
| 没开 RLS 的 5 张表（`auth.principals`、`auth.session_contexts`、`auth.context_exchange_tickets`、`integration.public_ids`、`integration.legacy_id_mappings`） | 任何非属主角色都没有任何权限，只能经 SECURITY DEFINER 函数访问 | PASS |
| SECURITY DEFINER 函数 | 94 个，全部固定 `search_path`；没有动态 SQL（`EXECUTE` / `format`）；PUBLIC 可执行的为 0 | PASS |
| 可执行函数数 | app 55 个，reader 15 个（只读判定辅助），binder 6 个，migrator 3 个（安装器服务主体的创建 / 停用等） | PASS |
| pg_hba | local / host 全部为 `scram-sha-256`；没有 trust | PASS |
| 默认权限 | 0 条 `pg_default_acl` | PASS：新对象不会被自动授权 |

## 2. 行为测试（PG16 / PG17 均 PASS）

| 领域 | 已验证的行为 | 测试 |
|---|---|---|
| 跨家庭隔离 | 家庭 B 不能写家庭 A 的数据；绑定家庭 B 时，看不到家庭 A 的人；服务跨家庭管理被拒 | F10 回归、C2、T1 跨家庭、v18 连接池 |
| 越权 | app 直接写表被拒（C1）；FAMILY 账号调用全部管理 API 被拒；app 不能安装 SERVICE 主体；app 不能解析外部身份；binder 读不到映射表 | F10、v15 安装器、v18 |
| 主体与渠道 | 12 种不匹配的主体类型 / 渠道组合全部被拒（R-20） | `f10_v15_channel_kind.sh` |
| 一次性票据 | 重复使用、已过期、用另一主体兑换、主体已停用，均被拒；兑换时重新校验 | v18、trusted_context_probe |
| 连接池 | 同一后端：清除上下文后读到 0 行、写被拒；换绑另一家庭后只看到该家庭。事务级连接池的隐患已演示并写入规则（禁止使用） | v18 |
| 权限撤销 | 撤销或过期顾问分配后，读文件和提交被拒（T2）；**关闭个案后，对其资源的读写被拒（0016）**；成员关系结束后，FAMILY 票据被拒（T1）；停用登录主体后，旧票据和身份解析都失效 | v16、v17、v18 |
| 业务规则 | 民事能力、Consent、官方事实、确认与提交分离、文档撤回、身份案件提前结案 | D6、G1–G5、T1–T4 |
| 审计 | 每一次写入判定都同时写表和 `PHOENIX_AUDIT`；客户端回滚后，日志仍可追溯（对账：仅存在于日志 1 条 = 预期的回滚尝试）；日志中没有名称；请求编号同时进入审计行和日志行 | D-9 对账、T1、v18 |
| 不可修改 | 民事能力历史、官方事实、已确认清单条目、已提交清单、文档撤回时间、文档版本，都不可修改 | D6 不可改写、v16 文档触发器、docs_probe |
| 认证 | 不带口令的本地 socket 被拒 | F10 |

## 3. 本次审计中发现并已修复的缺陷

| 编号 | 等级 | 问题 | 修复 |
|---|---|---|---|
| V16-F1 | P0（授权） | 个案关闭后，顾问对其资源的读写权限仍在 | 0016 |
| V16-F2 | P0（授权 / 完整性） | 个案可以引用另一主体的资源 | 0016 |
| V16-F3 | P1（审计完整性） | 重复授权时抛出唯一键异常，不写审计 | 0016 |
| R-L1 | P1（凭据） | 建角色 SQL 出错时，口令原文会随错误上下文进入服务器日志 | `install.sh` / `restore.sh` 在建角色会话中设置 `log_min_messages` 与 `log_min_error_statement` 为 `panic`；部署演练第 14 步对照验证（加固会话 0 处泄露，对照会话有泄露） |

## 4. 仍存在的风险与建议（未自行更改）

| 编号 | 等级 | 事实 | 建议 | 状态 |
|---|---|---|---|---|
| S-1 | P2（纵深防御） | 全部 100 个函数和全部表的属主都是超级用户 `phoenix_bootstrap`，因此 94 个 SECURITY DEFINER 函数以超级用户身份执行。目前没有动态 SQL，也都固定了 `search_path`，没有已知的可利用路径 | 把对象属主改为一个非超级用户的 NOLOGIN 属主角色（例如 `phoenix_canonical_migrator`）。属主仍然绕过自己表的 RLS，行为不变，但去掉了超级用户执行身份。这改变的是执行身份模型，需要你批准，并在 PG16 / PG17 上全量回归 | **待 Founder 决定** |
| S-2 | P2 | binder 仍能执行 0007 的 `auth.bind_context`（直接绑定上下文的旧入口）。它只能绑定 binder 自己的后端，而 binder 没有任何数据权限 | 用新 Migration 撤销 binder 对它的执行权，只保留票据流程 | 待办（工程范围内，低风险） |
| S-3 | P2 | backup 登录带 BYPASSRLS 和 `pg_read_all_data`，可读全部数据 | 运行凭据按 F-16 放在服务器上 root 专用文件；备份按 FD-7 加密后再异地存放（G-4 之后） | HOLD（G-4） |
| S-4 | 信息 | 腾讯暂停库仍是 0001–0006，且当时为 local trust | 任务 B 恢复前，先执行 G-1 至 G-8；升级按 `07` 手册进行 | HOLD |

## 5. 结论

在本地隔离环境与合成数据下：
- 权限分离、最小权限、跨家庭隔离、越权拒绝、票据失效、权限撤销、审计的防回滚，均**验证通过**（PG16 / PG17）；
- 本轮发现的 P0 / P1 缺陷已全部修复，并纳入永久回归；
- S-1 需要你决定；S-2 是低风险的待办清理项。
