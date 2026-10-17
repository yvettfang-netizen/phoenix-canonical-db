# 07 · 生产部署手册（Production Deployment Runbook）

**状态：** 生产部署 = **HOLD**。本手册是候选版本，只在本地演练过（`evidence/v1.8-deploy-rehearsal.txt`），从未在任何服务器上执行。
**部署包：** `canonical-db/deploy/tencent/`（PG16，镜像按摘要固定；不映射数据库端口；内部网络）。

## 0. 前置门禁（全部满足才可开始，缺一项即停止）

| # | 门禁 | 负责 |
|---|---|---|
| P1 | 服务器安全闸门 G-1 至 G-8 关闭：现服务器解除 NOT TRUSTED，或按 G-7 在新实例上重建 | 所有者 |
| P2 | G-4 凭据轮换完成。新口令在可信设备上生成，不经过服务器或聊天；工作站旧副本由 Jimson Liu 删除（F-16） | 所有者 / Jimson Liu |
| P3 | Founder 对本次部署的书面批准，写明目标环境、变更窗口、执行人（FD-8） | Founder |
| P4 | 任务 B 恢复的书面批准（当前 PAUSED） | Founder |
| P5 | 部署包的 SHA-256 与 Git 提交核对一致；上传方式不经过不可信主机 | 执行人 |
| P6 | 值班人员到位：Jimson Liu，升级对象 Founder（FD-7） | — |

## 1. 首次安装（全新服务器）

```bash
cd canonical-db/deploy/tencent
cp .env.example .env    # 填写 6 个 64 位十六进制口令；服务主体 ID（UUIDv7）与标签（不含空格）
chmod 600 .env && chmod 700 *.sh
./install.sh            # 预期最后一行：PASS Phoenix Canonical PostgreSQL install；并出现 INSTALLED service principal
./health.sh             # 预期：migrations=17 tables=27 policies=20
./backup.sh             # 预期：BACKUP ... 和 VERIFIED ... entries=N
./restore_drill.sh      # 预期：RESULT=PASS，LEDGER_MATCHES_MIGRATION_FILES count=17
./alert_check.sh        # 预期：alerts=0
```

- 安装可以重复执行（已应用的 Migration 会 SKIP，服务主体会 SKIP）。
- 建角色的会话不会把口令写进服务器日志（已演练验证）。

## 2. 升级现有库（例如腾讯暂停库：0006 → 0017）

1. **停止 binder 与应用**：临时上下文必须为空。
2. **预检（只读）**：与 `install.sh` 一样，先在容器内写 0600 pgpass，查完即删，口令不进命令行：
   ```bash
   set -a; . ./.env; set +a
   printf '%s\n' "*:*:*:phoenix_bootstrap:$PHOENIX_DB_BOOTSTRAP_PASSWORD" | docker compose --env-file .env exec -T postgres sh -c 'umask 077; cat > /tmp/pre.pgpass'
   docker compose --env-file .env exec -T -e PGPASSFILE=/tmp/pre.pgpass postgres psql -X -At -F' | ' -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -f - < preflight_upgrade.sql
   docker compose --env-file .env exec -T postgres rm -f /tmp/pre.pgpass
   ```
   任何一行第二列为 `t`（blocking）都必须先处理。其中"有确认人但没有确认时间的清单"需要业务决定，不得自行填写。
3. **备份：** `./backup.sh`，记下备份文件名与 VERIFIED。
4. **升级：** `./install.sh`。Migration 逐个原子执行；失败的那个整体回滚，之前已成功的保留。
5. **验证：** `./health.sh`、`./restore_drill.sh`、`./alert_check.sh`。
6. **启动** binder 与应用，按第 4 节做冒烟检查。
7. **如失败：** 按 `08_ROLLBACK_RECOVERY_RUNBOOK.md` 处理。

## 3. 定时任务（部署后安装，当前 HOLD）

| 任务 | 频率（北京时间） | 命令 |
|---|---|---|
| 备份并校验 | 每天 03:00 | `./backup.sh` |
| 保留期清理 | 每天 03:30 | `./prune_backups.sh --apply` |
| 审计提取与链校验 | 每天 00:30（UTC 日期切换之后） | `./audit_extract.sh` |
| 告警检查 | 每小时 | `./alert_check.sh`（只写本地文件；外发渠道按 G-5 登记） |
| 恢复演练 | 每月 1 日，以及每次发布前 | `./restore_drill.sh` |

## 4. 部署后冒烟检查

- 用 binder 运行账号为 SERVICE 主体签发票据，用 app 运行账号兑换，再调用 `core.create_family`（未绑定家庭的服务）。预期返回 true。
- app 运行账号直接 INSERT 业务表：预期 `permission denied`。
- `docker compose ps`：端口只在容器内（`5432/tcp`），不得出现主机端口映射。
- 服务器日志中没有任何部署口令。

## 5. 应用接入前提（FD-6，应用侧）

- 身份提供方、`iss`、`aud`、JWKS 地址、应用负责人、binder 负责人填写并经复审（EV-7）。
- 应用后端以 OIDC / JWT 认证用户，只接受非对称签名，访问令牌有效期不超过 15 分钟；数据库不接收用户令牌。
- binder：`auth.resolve_external_identity` → `auth.issue_context_ticket`（每个请求一张，请求编号为随机 UUID）；app 兑换后执行业务，归还连接前调用 `auth.clear_context()`，失败则丢弃连接；**禁止事务级连接池**。
- 外部身份映射只经 SERVICE 接口 `auth.register_external_identity` 建立。
