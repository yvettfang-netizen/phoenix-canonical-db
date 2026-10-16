# Phoenix Canonical PostgreSQL — V1.2 任务 B 执行报告

> **状态更新（2026-10-15 15:10 +0800，Founder 决定；Claude 于 16:50 补记）：任务 B = PAUSED。**
> 依据 Notion 任务页边界"不得部署到 A4 OPEN / NOT TRUSTED 服务器"，同见 `phase2-gate/CODEX_INSTRUCTION_R6_TENCENT_F10_V1.0.md` 文首。
> - 14:49 之后无任何远端操作；不重试 `install.sh`，不再连接腾讯服务器。
> - 服务器上已上传的文件、`…-deploy.bak-20261015T064812Z` 副本、B1 备份和 B0–B3 证据均原样保留。
> - 腾讯隔离库仍为 0001–0006，0 业务行，无发布端口。
> - 恢复任务 B 需 Founder 重新书面批准。届时须先修正 `deploy/tencent/*.sh` 的 CRLF 换行（见文末），并重做 B3–B7。

**结论：任务 B = PAUSED。** 已完成腾讯隔离空库更新前采集、更新前备份、部署目录完整副本、从本地旧 HEAD 上传 0001–0008 的已跟踪文件。执行新 `install.sh` 时，上传文件的 shebang 实际为 `bash\r\n`，远端报 `/usr/bin/env: ‘bash\r’: No such file or directory`，退出码 127。按 B3 停止条件立即停止，没有执行 0007/0008、HBA 切换、恢复演练或 B7 验收。

## 已执行步骤和原始证据

| 步骤 | 实际结果 | 原始命令及未删节输出 |
|---|---|---|
| B0 连接、主机、范围 | 经已知 ED25519 指纹核验连接到 `ubuntu@1.12.77.180`。仅有 `tencent-postgres-1` Canonical 容器，健康；无发布端口，私有网络和数据卷为指定资源。宿主机监听与旧目录仅只读列示。 | `evidence/tencent-v1.2-B0-hostkey.txt`、`tencent-v1.2-B0-connection.txt`、`tencent-v1.2-B0-host-readonly.sh`、`tencent-v1.2-B0-host.txt` |
| B0 数据库 | `phoenix_canonical_dev` 为 PG16.15；账本 0001–0006；24 张业务表、0 业务行、0 会话行；本地 socket 仍为 `trust`，主机连接为 SCRAM。 | `evidence/tencent-v1.2-B0-db-readonly.sql`、`tencent-v1.2-B0-db.txt` |
| B0 文件与旧备份 | 远端 0001–0006 哈希与本地 HEAD 一致；旧备份 manifest 摘要匹配。未读取或输出 `.env` 内容。上传来源为当时的本地 HEAD `725661f8d752242136019af9636c1ed26f69e112`。 | `evidence/tencent-v1.2-B0-files-readonly.sh`、`tencent-v1.2-B0-files.txt`、`tencent-v1.2-B0-local-head-compare.txt` |
| B1 更新前备份 | 现有 `backup.sh` 生成 `phoenix_canonical_20261015T064743Z.dump`，模式 600，SHA-256 `40792174c2f4d9e675ab63a1a50ad0c0ffa5564c075cd3679901fb38ed0ec758`，`pg_restore -l` 为 284 条，manifest 匹配。 | `evidence/tencent-v1.2-B1-backup.txt` |
| B2 完整副本 | 服务器目录复制为 `/home/ubuntu/phoenix-canonical-db-deploy.bak-20261015T064812Z`；副本非密钥文件哈希逐项记录，`.env` 只记录模式 600 和大小。 | `evidence/tencent-v1.2-B2-server-copy.txt` |
| B2 已跟踪文件上传 | `git archive HEAD` 的 0001–0008 与 `deploy/tencent/` 上传到精确部署目录，SHA-256 与本地归档相符；原有 `.env` 保留，并以 CSPRNG 追加 backup 角色口令，模式仍为 600。口令未回显。 | `evidence/tencent-v1.2-B2-upload.txt` |
| B3 安装尝试 | `timeout 300s ./install.sh` 在 shell 启动前失败，退出码 127。安装脚本内没有任何迁移语句执行。二进制核查证实本地归档和远端脚本首行均含 `0d0a`。 | `evidence/tencent-v1.2-B3-install.txt`、`tencent-v1.2-B3-line-endings.txt` |
| B3 停止后只读确认 | 容器仍健康、无发布端口、账本仍是 0001–0006，业务行估计 0。未开始 B4–B7。 | `evidence/tencent-v1.2-B3-stop-readonly.txt` |

## 重要运行状态

- **运行中的数据库仍为 0001–0006，未升级到 0007/0008；0009 从未上传或部署。** 已上传的新 shell 脚本带 CRLF，在修复前可能无法执行；这包含 `health.sh` 和 `backup.sh`。旧目录副本和 B1 备份均保留。
- B3 已触发指令规定的停止条件。本轮没有恢复旧脚本，也没有继续修改远端。后续须在新的受控执行中先修正导出/换行和核对哈希，再决定是恢复 B2 副本还是继续 0007/0008 安装；必须重新执行 B3–B7 并保留完整原始证据。
- **进程终止核验（仅依据暂停前证据）：** `evidence/tencent-v1.2-B3-install.txt` 记录远端 `timeout 300s ./install.sh` 以 127 退出；错误发生于 shebang 解释器启动阶段，脚本体未执行。随后 `evidence/tencent-v1.2-B3-stop-readonly.txt` 的只读检查成功，账本仍为 0001–0006。由此可确认这次远端安装命令已经终止；在“不再连接腾讯服务器”的边界下，无法实时核验服务器其他进程。原有数据库容器当时健康运行，未被当作临时安装进程停止。
- 没有触碰宿主机原生 PostgreSQL、MySQL、nginx、pm2、sshd、防火墙、crontab 或其他数据卷；没有导入数据，也没有发布端口。没有对全机状态作 B7 后置核查，故不声称其他服务已完成后置比对。
- 新追加的部署凭据仍位于服务器 `.env`，本机部署凭据存放方案 F-16 及应用鉴权 FD-6 继续 HOLD。B1 manifest 仅为未签名的摘要校验。

**本地实施与证据提交：** `b6c5304c076fee4b970de319108610784a5c46b7`。远端上传来源 HEAD 为 `725661f8d752242136019af9636c1ed26f69e112`，但远端**运行版本无对应的 0007/0008 实施提交**。未 push、merge 或创建 PR。
