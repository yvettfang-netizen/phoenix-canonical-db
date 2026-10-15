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
