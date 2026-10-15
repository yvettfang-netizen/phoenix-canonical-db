# Phoenix Canonical PostgreSQL — V1.2 任务 A 执行报告

**结论：A = HOLD。** 已按 Founder 授权完成本地两个旧开发库的只读核查、空表核验和归档，随后仅重建了指定的两个开发数据卷。新 PG16 容器首次引导时 bootstrap 认证失败，立即停止 A；未继续迁移、角色配置或 A3 验收。PG17 没有重建。所有归档和测试数据均为合成数据。

## 已执行步骤和原始证据

| 步骤 | 实际命令与结果 | 原始命令及未删节输出 |
|---|---|---|
| A1 卷和容器 | `docker volume ls`、`docker compose ps`；卷名与授权的两个精确名称一致，两个服务运行。 | `evidence/r6-v1.2-A1-inventory.txt`、`r6-v1.2-A1-volume-mounts.txt` |
| A1 只读数据库核查 | 两库均为 25 张业务表、所有业务表 0 行；账本均为 0001–0007，旧 0007 哈希 `5fcff42c…`，本地 HBA 为 `trust`。 | `evidence/r6-v1.2-A1-readonly.sql`、`r6-v1.2-A1-pg16.txt`、`r6-v1.2-A1-pg17.txt` |
| A1 归档 | 用 `pg_dump -Fc` 各取一次归档并验证 `pg_restore -l`。PG16：152001 字节，SHA-256 `40abfe76e8e4319f37e1d03e745b78deccd7aea255f00b06fb96ab4ad1b60d09`；PG17：153571 字节，SHA-256 `28cf2b5e6bb73fa12c8258fe9dfdd9045a185ed28843577fc61549794f65852b`。归档留在被 Git 忽略的 `canonical-db/backups/`。 | `evidence/r6-v1.2-A1-dump-pg16.txt`、`r6-v1.2-A1-dump-pg17.txt` |
| A2 精确范围重建 | 仅停止两个 Canonical 开发服务，并移除 `phoenix-canonical-foundation_pg16_data`、`phoenix-canonical-foundation_pg17_data` 两卷；没有使用 `down -v`。 | `evidence/r6-v1.2-A2-rebuild.txt` |
| A2 首次初始化 | `pwsh -File canonical-db/scripts/db.ps1 -Action provision-local-roles -Version 16` 创建新 PG16 卷和容器，但首次连接报 `FATAL: password authentication failed for user "phoenix_bootstrap"`，退出码 1。未读取、输出或在命令行传递 `.env` 口令。 | `evidence/r6-v1.2-A2-init-pg16.txt` |
| A3 停止后只读状态 | PG16 容器健康、仅挂载新的精确 PG16 开发卷；PG17 开发卷不存在。没有进一步执行迁移或 A3 验收。 | `evidence/r6-v1.2-A3-hold-state-readonly.txt` |

## 当前边界与恢复条件

- PG16 新开发库的迁移账本**未验证**；不能把容器健康等同于建库成功。PG17 开发库当前不存在。A3 所列测试均未在开发库上执行。
- 认证失败符合指令的“状态与预期不符则停止该任务”条件。本轮未通过尝试旧口令、读取 `.env` 或再次重建来绕开停止条件。
- 下一轮须先用不回显口令的方式定位本地 bootstrap 凭据与新数据卷初始化凭据的不一致，再经新的执行指令恢复 A2/A3。先前的两个归档仍可核对，不应提交到 Git。
- 0001–0008 工作树字节未改；当前 0009 文件 SHA-256 为 `2a48d016c0b2dd952d56a15853c8092895df057e6a0d69f5ab391803ca0747c2`，**未应用到 A 的开发库**。

**本地实施与证据提交：** `b6c5304c076fee4b970de319108610784a5c46b7`。未 push、merge 或创建 PR。

## 续做：A2/A3 完成（Claude，2026-10-15 16:43–16:45 +0800）

Codex 因额度上限中断后，由 Claude 按 Founder 指示接续。

### 根因

两个缺陷叠加：

1. **口令长度不一致。** 本地 `.env` 的 bootstrap 口令是 2026-10-11 由旧版 `db.ps1` 生成的 48 位十六进制（`byte[] 24`），但 0007 轮修改后的 `db.ps1` 只接受 64 位。
2. **守卫失效。** 匹配不到时，PowerShell 管道返回空集合；`-notmatch` 对空集合返回空集合，`if` 判为假，第 32 行的守卫因此**没有抛错**。脚本带着空口令写入容器 pgpass，于是认证失败。

新 PG16 数据卷本身是用 `.env` 的 48 位口令正确初始化的，所以无需再次重建。

### 修复（`scripts/db.ps1`）

- 新建 `.env` 改为 32 字节（64 位）；
- 解析同时接受既有的 48 位与新的 64 位；
- 结果强制转为 `[string]`，使守卫在缺失或格式错误时真正抛错。

已用 Windows PowerShell 5.1 以合成输入验证：48 位与 64 位均接受，50 位与缺失键均抛错，真实 `.env` 解析长度为 48（只输出长度，未输出值）。

### 执行与证据

本机未安装 pwsh，所以用 bash 等价执行 `db.ps1` 的 init / provision-local-roles / probe 流程。口令只经管道传入容器 pgpass，不出现在命令行或输出中。原始输出：`evidence/r6-v1.2-A4-pg16-claude.txt`、`evidence/r6-v1.2-A4-pg17-claude.txt`。

| 项 | PG16.15 | PG17.11 |
|---|---|---|
| 精确数据卷 | 复用 A2 新建的 `…_pg16_data` | 新建 `…_pg17_data` |
| bootstrap 经 host SCRAM 登录 | PASS | PASS |
| 不带口令的本地 socket | 拒绝（`fe_sendauth: no password supplied`） | 同左 |
| `pg_hba` | local/host 全部 `scram-sha-256` | 同左 |
| 0001–0009 首次执行、重复跳过 | PASS；账本 9 行，哈希与文件逐一一致 | PASS |
| 本地登录角色配置与最小权限检查 | migrator / app / binder / backup PASS；**reader FAIL（R-8）** | 同左 |
| 六套原有验收（开发库，事务回滚） | 6/6 PASS | 6/6 PASS |
| 目录读回 | tables 25、policies 20、app 写授权 0、PUBLIC 可执行函数 0、业务行 0 | 同左 |

### 新发现 R-8

0007 给 `phoenix_canonical_reader` 授了 `canonical_migrations.applied` 表的 SELECT，但没有授 schema `canonical_migrations` 的 USAGE。因此 reader 查询账本时报 `permission denied for schema canonical_migrations`，而部署包的 `health.sh` 正是用 reader 查账本，实际运行会失败。需在新 Migration（0010）中补授 USAGE，并加回归测试。

### 结论

**A = PASS（R-8 除外）。** 开发库已与当前 0001–0009 一致，可作为本地证据环境使用。

以下仍为 **NOT_RUN**，待有 pwsh 的环境执行：`db.ps1` 自带的 test / audit-migration / audit-backup / restore-test，以及 `phase3_defect_regression.ps1`、`phase3_fresh_cluster_restore.ps1`。
