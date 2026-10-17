# Phoenix Canonical PostgreSQL — V1.7 执行报告（0016 缺陷修复、升级路径、部署包演练）

**结论：PASS。**
- 0016 修复了 V1.6 复跑中发现的 V16-F1、V16-F2、V16-F3，三项均已纳入永久回归；
- PG16 / PG17 完整 F10 与全新集群恢复均通过；
- 0006→0016 带数据升级（含失败回滚与恢复）在两个版本上通过；
- 部署包本地端到端演练通过；
- 本地开发库已升级到 0016。

**执行：** Claude Code，2026-10-17 13:50–14:15 +0800，依据 `PHOENIX-DB-FINAL-CLOSEOUT-20261017` 授权。
**边界：** 未连接腾讯，未拉取镜像（使用本地已缓存的同一摘要），未推送远程，只用合成数据。

## 1. Migration 0016 `0016_assignment_scope_integrity.sql`

**SHA-256：** `7b10af1992e548e065c68d947b47bb073cdc88c52e4312b9aa9ccbe1bfa962e4`

| 缺陷 | 依据 | 修复 |
|---|---|---|
| V16-F1：个案关闭后，顾问仍对其关联申请或案件有读写权限 | EV-1 第 8.1 条、BC："有效个案分配" | `casework.has_active_advisor_assignment` 增加三个条件：个案状态为 OPEN / PAUSED、分配状态为 ACTIVE、资源与个案的家庭和主体一致。该函数同时支撑写入判断（0009 / 0011）、读取 RLS（0004）与访问判定 API（0006） |
| V16-F2：个案可以引用另一主体的申请或案件 | EV-4 第 1 节第 2 条 | `casework.create_case` 在资源已存在时校验家庭和主体，不一致则拒绝并写审计 `RESOURCE_FAMILY_OR_SUBJECT_MISMATCH`。资源后建的情况（E4-6）由 `education.applications` / `identity.cases` 上的插入前触发器校验（`CASE_RESOURCE_FAMILY_OR_SUBJECT_MISMATCH`） |
| V16-F3：重复创建有效分配或监护授权时直接抛出唯一键异常，不写审计 | D-10 "默认拒绝并写审计" | 先检查是否已有"状态 ACTIVE、未撤销、在有效期内"的记录，有则返回审计拒绝 `ALREADY_ACTIVE`。已过期但仍标为 ACTIVE 的旧记录，继续交给 0008 的插入触发器处理 |

**0001–0015 未改动，**哈希见 `evidence/v1.7-f10-sh-pg16.txt` 开头的 MIGRATION_SHA256 段。

## 2. 测试结果（PG16 16.15 / PG17 17.11，Docker 29.8.2）

| 项 | PG16 | PG17 | 证据 |
|---|---|---|---|
| 完整 F10（新增 bash 版 `tests/f10_local_acceptance.sh`，与 pwsh 版步骤相同，另加"未编号文件"守卫） | PASS，退出码 0，PASS 194 项，无意外 FAIL | 同左 | `evidence/v1.7-f10-sh-pg16.txt`、`-pg17.txt` |
| 新永久回归 `tests/f10_v17_assignment_scope.sh`（19 项断言） | PASS | PASS | 同上 |
| D-9 对账 | 日志 238 条，与数据库对上 237 条，仅存在于日志的 1 条为被回滚的拒绝 | 同左 | 同上 |
| 全新集群恢复 | 账本 16，表 26，策略 20，9 个恢复后套件 PASS | 同左 | 同上 |
| 升级路径 0006→0016（`tests/upgrade_path_acceptance.sh`） | PASS | PASS | `evidence/v1.7-upgrade-path-pg16.txt`、`-pg17.txt` |
| 开发库升级 0011→0016（先跑预检） | PASS | PASS | `evidence/v1.7-dev-db-upgrade.txt` |
| 部署包演练（`tests/deploy_package_rehearsal.sh`，PG16 部署镜像） | PASS | 不适用（部署包只用 PG16） | `evidence/v1.7-deploy-rehearsal.txt` |

**升级路径的具体步骤：**
1. 在 0006 结构下灌入 15 张业务表的合成数据，并放入一行会阻断 0012 的数据（SERVICE 主体对应了自然人）；
2. 预检恰好报出这 1 项阻断；
3. 升级停在 0012：0007–0011 已应用，0012 没有留下任何痕迹，数据不变；
4. 移除阻断项后，预检通过，升级到 0016；
5. 各表行数不变；分配和监护的生命周期状态、主体类型约束、清单确认约束、个案与资源主体一致性都成立；目录回归 PASS。

**部署包演练的具体步骤：**
1. 安装：16 个 Migration 全部应用，安装器服务主体已安装；
2. 再次安装：没有应用任何 Migration，服务主体跳过；
3. 健康检查（reader 运行账号）：`migrations=16`；
4. binder 运行账号签发票据，app 运行账号据此创建家庭：成功；app 运行账号直接写表：被拒；
5. 备份，生成清单；
6. 在全新卷上恢复：通过；篡改过清单的备份：被拒；
7. 恢复后健康检查与数据核对正确；
8. 容器端口只在容器内部（`5432/tcp`），没有映射到主机；演练资源全部清理，无残留。

## 3. 部署包改动

| 文件 | 改动 | 原因 |
|---|---|---|
| `deploy/tencent/install.sh` | 新增安装器服务主体步骤：读取 `PHOENIX_DB_SERVICE_PRINCIPAL_ID`（UUIDv7）和 `_LABEL`（不含空格）；幂等，已存在就跳过，ID 被其他主体占用则失败 | D-10 规定服务主体只能由安装流程创建；没有它，新库无法经 API 创建任何家庭 |
| `deploy/tencent/.env.example` | 增加上述两项（不是机密），并写明格式 | 同上；`.env` 会被 bash 执行，值中不能有空格 |
| `deploy/tencent/restore.sh` | 去掉对主机 python3 的依赖，改为严格匹配 `backup.sh` 写出的单行清单格式 | 主机不一定有 python3；校验的严格程度不降低（篡改测试已验证） |
| `deploy/tencent/preflight_upgrade.sql`（新增） | 只读的升级前检查：账本状态、0012 的主体与自然人约束、临时上下文和票据、0011 的清单确认约束 | 0011 / 0012 新增的约束遇到旧数据会阻断升级 |

## 4. 其他测试改动

- `tests/f10_ephemeral_init.sh` 的默认 Migration 数改为 16；
- `tests/f10_ephemeral_restore.sh` 的恢复账本断言改为 16；
- `tests/f10_local_acceptance.ps1`：暂存 0011–0016，用 0017 测"多一个文件"，用 0016 测"缺一个文件"，加入 v17 测试，证据文件名改为 v1.7；
- **说明：** pwsh 版本机无法运行；bash 版步骤相同，并已实际运行。

## 5. 上线手册必须写入的约束

- **升级前必须执行 `preflight_upgrade.sql`**，存在阻断项时不得升级。
- **0011 之前已有确认人的清单：** 补确认时间需要业务决定，不得自行填写。
- **升级前停止 binder 与应用。**
