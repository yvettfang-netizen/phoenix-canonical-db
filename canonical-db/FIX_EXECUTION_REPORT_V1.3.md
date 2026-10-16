# Phoenix Canonical PostgreSQL — V1.3 本地执行报告（第一批）

**本批结论：D1–D3 = PASS；D4 机制项 C1/C6/C7 = PASS，其余 D4 与 D5–D7 = NOT_STARTED。任务 B = PAUSED。生产就绪 = NO。** 本批只在本机运行，使用合成数据；未连接腾讯服务器、未部署、未推送、未合并。后续迁移不得以本批结果代替验收。

## 依据与边界

- `phase2-gate/CODEX_INSTRUCTION_V1.3_NEXT.md` 要求新增 0010，修复归档换行并在 PG16/17 用 pwsh 交叉验收。三份 Founder 补充件的 SHA-256 均与指令所列值完全相符；本批未实施其业务语义迁移。
- 0001–0009 字节未改；0010 `migrations/canonical/0010_reader_ledger_usage.sql` 的 SHA-256 为 `eb05a55b813695ef7c6252ffc00569a0d97920008773fc07b6d0f6109959825a`。
- 数据库仅在本地 Compose 网络，`docker ps` 显示 PG16/17 healthy，只有容器内 `5432/tcp`，没有发布宿主机端口。原始输出：`evidence/v1.3-D1-D4-final-state.txt`。
- 任务 B 暂停和安装进程退出的依据在 `FIX_EXECUTION_REPORT_V1.2_B.md`，B0–B3 原始证据保持原样。

## 分项执行

| 项 | 修改与实际测试 | 原始命令、输出 | 状态 |
|---|---|---|---|
| D1 / R-8 | 0010 仅授 reader `canonical_migrations` schema USAGE；同步更新本地角色校验。PG16/17 均已应用并重复校验。真实 reader LOGIN 查询账本得到 10；reader INSERT/CREATE 及 app、binder 读账本均返回 `permission denied`。 | `evidence/v1.3-D1-provision-pg16.txt`、`v1.3-D1-provision-pg17.txt`、`v1.3-D1-reader-pg16.txt`、`v1.3-D1-reader-pg17.txt`；测试源 `tests/reader_ledger_regression.ps1` | PASS |
| D2 / R-15 | 新增 `deploy/tencent/.gitattributes`，并扩充 `tests/.gitattributes`。本机 `git archive HEAD` 解包后的 9 个 shell 脚本首行均为 LF；逐个记录 SHA-256。没有上传归档。 | `evidence/v1.3-D2-archive-check.ps1` 与 `.txt`；首轮脚本参数错误及修正后通过的输出均保留 | PASS |
| D3 / R-16 | PG16/17 的 `provision-local-roles`、test、probe、audit-migration、audit-backup、backup、restore-test、既有缺陷回归、全新集群恢复、F10 验收、HBA 认证回归全部通过。既有 48 位本地 bootstrap 凭据成功连接；合成缺失键和错误长度均被真实 `db.ps1` 守卫拒绝。备份首次在 PG16 因 `Start-Database` 覆写 pgpass 而失败，修正后 PG16 复测通过；PG17 首次即通过。失败记录未删。 | `evidence/v1.3-D3-summary.txt`、`v1.3-D3-pg16-*-retest.txt`、`v1.3-D3-pg17-*.txt`、`v1.3-D3-bootstrap-guard.txt`；完整 F10 输出在 `v1.3-D3-pg16-f10-full.txt` 与 `v1.3-D3-pg17-f10-full.txt` | PASS（修正并复测后） |
| D4 机制项 | F10 永久回归新增真实 app LOGIN 直接写表拒绝、跨家庭服务写入拒绝、非 Mock 存储键与版本跳号拒绝。PG16/17 的一次性隔离集群均 PASS；原 V1.2 证据文件未改。 | `evidence/v1.3-D4-pg16-full.txt`、`v1.3-D4-pg17-full.txt`，其中 `PASS C1`、`PASS C6/C7`；源文件 `tests/f10_ephemeral_regression.sh` 与 `tests/f10_service_regression.sql` | PASS（C1/C6/C7） |
| D4 业务探针 C2/C3/C4/C5/C8 | 需在已批准的 D5/D6 迁移落地后按新期望编写永久断言。现有 F10 一次性测试仅加载 0001–0009，不构成对 0010 或后续迁移的集成验收。 | V1.3 指令 D4–D6；未生成通过证据 | NOT_STARTED |
| D5 / D6 / D7 | 0011 及后续业务语义、引导管理、审计双写、身份映射和本地运维脚本尚未实施。批准文件摘要已核对，实际能力仍以未实施计。 | `phase2-gate/CODEX_INSTRUCTION_V1.3_NEXT.md` | NOT_STARTED |

## 留存与提交

- 归档、恢复演练及所有新增业务测试数据均为合成数据。正式开发库备份动作要求业务行数为 0，PG16/17 均通过。测试用一次性容器及卷已清理；Compose 开发容器继续在本机运行。
- B0–B3 证据、已上传远端文件及服务器备份副本原样保留；本批未访问远端。
- 本批代码与原始证据的本地提交：`8ecc77c57413bcbee1614946b22e3b7ac3760525`、`a93ce1aa413d8f3e36ef7abe09b07491024ae7b4`。未 push、merge 或创建 PR。
