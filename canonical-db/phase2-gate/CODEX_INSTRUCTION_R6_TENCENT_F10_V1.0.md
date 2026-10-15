# Codex 执行指令：本地开发库重建、腾讯隔离库更新、应用写入接口

**签发：** Founder 于 2026-10-15 在会话中批准（"都做"）。指令由 Claude 起草。
**依据：** `CLAUDE_CANONICAL_DATABASE_REAUDIT_REPORT_V1.2.md` 第 5、7 节；`PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md`（Claude 预填版，**尚未签名**）。
**执行顺序：** 任务 A 与任务 B 可立即执行，彼此独立。任务 C 必须等决策登记表签名后才能开始。

> **⚠️ 变更（2026-10-15 15:10 +0800，Founder 决定）：任务 B 暂停。任务 C 继续。**
> 依据是 Notion 任务页的边界："不得部署到 A4 OPEN / NOT TRUSTED 服务器"。
> - 不要重试 `install.sh`，不要再连接腾讯服务器。如有远端进程，确认其已终止。
> - 服务器上已上传的文件与 `…-deploy.bak-*` 副本保持现状，不删除、不回滚。B0–B3 的证据原样保留，并在报告中写明 `任务 B = PAUSED（B3 未执行：install.sh 换行符错误，数据库仍为 0001–0006）`。
> - 恢复任务 B 需要 Founder 重新书面批准。
> - 决策登记表已于 2026-10-15 14:37 签名，任务 C 的开工条件已满足，按下文继续在本地执行，0009 不部署到腾讯。

## 共同边界（三个任务都适用）

1. 只在现有工作树 `codex/canonical-postgresql-phase1` 内工作。允许本地 commit，禁止 push、merge、PR。
2. 不修改 `0001`–`0008` 的任何字节；新的结构变更只用新编号的 Migration。
3. 不导入真实数据、旧库数据、Founder OS / D1 / 飞书数据。只用合成数据。
4. 口令和密钥：
   - 不得出现在命令行参数、sudo 命令、日志、聊天或报告中；
   - 新口令用 CSPRNG 生成，不得回显；
   - 不读取、不输出任何现有 `.env` 的内容。
5. 每一步都保存未删节的原始命令和原始输出，放在 `canonical-db/evidence/`，文件名带 `v1.2` 和任务编号。只写文字总结不算证据。
6. **Founder 要求暂停时，立即停止。** 如果有正在远端运行的进程，必须确认其已终止，并记录终止证据（吸取 2026-10-14 那次"暂停后安装仍跑完"的教训）。
7. 遇到下面任一情况，停止该任务并标 HOLD，在报告中说明，然后继续其他任务：
   - 状态与预期不符；
   - 需要修改 0001–0008；
   - 需要动到任务范围以外的服务；
   - 需要自行决定业务语义。

## 任务 A：重建本地开发数据卷（R-6）

**已批准：** 删除并重建本地两个开发数据卷。它们只含空表，已与当前 Migration 不一致（0007 账本为 `5fcff42c…`，文件为 `49ec7373…`），本地认证仍为 `trust`。

**范围：** 只限本地 compose 项目 `phoenix-canonical-foundation` 的 `pg16`、`pg17` 服务，以及数据卷 `phoenix-canonical-foundation_pg16_data`、`phoenix-canonical-foundation_pg17_data`。不得动其他容器或数据卷。

**A1 重建前（只读留证）**
1. 执行 `docker volume ls` 和 `docker compose ps`。卷名与上面不完全一致时，停止。
2. 对两个 `phoenix_canonical_dev` 只读查询：账本名称与 SHA-256、表数量、业务表行数、`pg_hba_file_rules`。**业务表行数不为 0 时，停止。**
3. 对两个开发库各做一次 `pg_dump -Fc` 归档，作为重建前证据，记录 SHA-256。放在已被 gitignore 忽略的 `backups/`，不提交。

**A2 重建**
1. 停止两个服务，只删除上面两个精确命名的数据卷。不要用会波及其他资源的通配命令。
2. 用当前 `compose.yaml` 重新初始化（`--auth-local=scram-sha-256 --auth-host=scram-sha-256`，镜像摘要锁定）。
3. 执行 0001–0008，配置本地登录角色。本地口令按现有 `.local-roles.env` 机制管理，不输出。

**A3 验收（PG16 与 PG17 都做）**
1. 开发库账本为 8 行，哈希与当前文件一致。
2. 不带口令连接本地 socket 被拒绝。
3. 全部测试通过：`db.ps1` 的 test / probe / audit-migration / audit-backup / restore-test，`phase3_defect_regression.ps1`，`phase3_fresh_cluster_restore.ps1`，`phase3_pg_hba_auth_regression.ps1`。
4. 测试后开发库业务表行数为 0。

## 任务 B：把腾讯隔离空库更新到 0001–0008

> **已暂停（2026-10-15 15:10，Founder 决定）。** 以下步骤在 Founder 重新书面批准前不得执行，见文首变更说明。

**已批准：** 只更新腾讯云上的隔离空库。依据是决策登记 FD-8 选项 1（预填，待签名；Founder 已在会话中口头批准本任务）。

**范围：**
- 只限 `/home/ubuntu/phoenix-canonical-db-deploy`、容器 `tencent-postgres-1`、数据卷 `phoenix_canonical_pg16_data`。
- **禁止**触碰：宿主机原生 PostgreSQL、MySQL、nginx、pm2 应用、sshd、防火墙或安全组、crontab、其他目录。
- **禁止**发布任何主机端口。
- **禁止**删除或重置该数据卷，**禁止**执行 `docker compose down -v`。
- 旧目录 `/home/ubuntu/phoenix-canonical-db` 只看不删。

**B0 更新前只读采集**（保存为 `evidence/tencent-v1.2-B0-*.txt`）
1. 主机名、时间；`docker ps -a`；`docker port tencent-postgres-1`（必须为空）；`docker inspect` 中的网络、端口、挂载和镜像摘要；宿主机 `ss -lnt`。
2. 账本名称与 SHA-256；`pg_roles` 属性；`pg_hba_file_rules`；业务表行数；`auth.session_contexts` 行数。
3. 部署目录中各文件的 SHA-256，并与本地 HEAD 对比；`backups/` 列表，以及备份文件 SHA-256 与 manifest 的对照。
4. 旧目录 `/home/ubuntu/phoenix-canonical-db` 的现状（只列出，不删除）。
5. **停止条件：** 业务表行数不为 0；或发布了主机端口；或存在预期之外的 canonical 容器或数据卷。

**B1 更新前备份**
- 用服务器上现有的 `backup.sh` 做一次备份，记录文件名、SHA-256，以及 `pg_restore -l` 的条目数。这就是登记表中的"更新前备份 ID"。

**B2 上传**
1. 先把服务器上现有部署目录完整复制一份，命名为 `…-deploy.bak-<UTC时间戳>`，并记录各文件 SHA-256。
2. 从本地 HEAD 用 `git archive` 导出 `canonical-db/migrations/canonical/` 与 `canonical-db/deploy/tencent/` 的**已跟踪文件**，覆盖到部署目录中。保留服务器上已有的 `.env`。
3. 用 CSPRNG 生成 `PHOENIX_DB_BACKUP_PASSWORD`，不回显，追加到 `.env`；权限保持 600。凭据存放方式仍待 F-16 决定，本次沿用现有做法，并在报告中注明。
4. 核对上传后各文件 SHA-256 与本地 HEAD 一致。

**B3 执行 Migration**
- 运行新的 `install.sh`。预期结果：0001–0006 跳过（哈希核对通过），0007、0008 新执行，各运行角色（含 backup）设置口令。
- 失败时，依靠原子回滚保持 0006 状态，然后停止。

**B4 切换本地认证（按 `PG_HBA_SWITCH_PLAN_V1.0.md`）**
1. 备份容器内的 `pg_hba.conf`，记录 SHA-256。
2. 把 `local … trust` 改为 `scram-sha-256`，执行 `pg_reload_conf()`。
3. 验证：不带口令连接 socket 被拒绝；reader 和 backup 用 0600 pgpass 可以连接。
4. 失败时恢复备份的 `pg_hba.conf` 并重新加载，然后停止。

**B5 健康检查与备份**
- 运行新的 `health.sh` 和 `backup.sh`。确认备份文件和 manifest 权限为 600、SHA-256 一致。

**B6 服务器上的恢复演练**
1. 在服务器上用**同一镜像摘要**启动一个一次性容器：不加入私有网络以外的网络，不发布端口，使用独立的临时数据卷。
2. 先建角色，再恢复 B5 的备份。验收：ledger 8、tables 25、policies 20、0 错误。
3. 演练结束后删除这个一次性容器及其临时卷。**不得**动 `tencent-postgres-1` 或它的数据卷。

**B7 更新后只读采集**
- 重复 B0 的全部项目，保存为 `evidence/tencent-v1.2-B7-*.txt`，并与 B0 对比：
  - 账本 8 行；
  - `pg_hba` 全部为 scram；
  - 无主机端口；
  - 业务表行数 0；
  - 宿主机其他服务状态与 B0 相同。

## 任务 C：应用写入接口（F-10），并修复 R-7

**开工条件（缺一不可）：**
1. `PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md` 的 Approval record 已由 Founder 填写姓名、角色、日期和签名（或 typed approval）。
2. FD-2 选中选项 1，且第 6 条"F-10 写入依据"没有被删除或改动。

条件不满足时，不得开始，报告 `F-10 = HOLD（登记表未签名）`。签名中有任何改动，以签名版为准；与本指令冲突的部分，先停下来问我。

**范围：** 只在本地新增 `0009`（如有需要，再加 `0010`），不部署到腾讯。

**要求：**
1. 应用角色仍然**不得**获得任何表的 INSERT / UPDATE / DELETE 权限。所有写入都通过 `SECURITY DEFINER` 函数完成，固定 `search_path`，撤销 PUBLIC 执行权后，只授予 `phoenix_canonical_app`。
2. 每个函数都要校验：可信上下文（`auth.current_*`）、渠道、家庭归属或顾问分配或渠道授权、合同要求的 Consent、状态流转是否合法、操作者。所有允许和拒绝都通过受控路径写审计，采用默认拒绝。
3. 写入边界以登记表 FD-2 第 6 条和 `F10_APPLICATION_WRITE_API_DESIGN_DRAFT.md`（SHA-256 `1eb356cb…`）为准：

   | 对象 | 规则 |
   |---|---|
   | Family / Person / 家庭成员 / 学生档案 | 只允许 INTERNAL 渠道的 SERVICE 主体创建；字段只限合同已列出的核心字段 |
   | Consent | 授予方必须是主体本人，或有对应范围、证据等级 VERIFIED 的监护人；支持新授与撤回；撤回立即生效 |
   | Education Application | 状态 `DRAFT→READY→SUBMITTED→DECIDED`；`WITHDRAWN` 只能从未决定的状态进入；不能跳过状态或倒退 |
   | Identity Case | 状态 `DRAFT→EVIDENCE_PENDING→UNDER_REVIEW→RESOLVED/CLOSED` |
   | 文件版本 | 只能追加；只写元数据（不透明的 storage_key 和 SHA-256）；只对接 Mock 存储 |
   | 提交清单 | 先建为 PREPARING，再添加条目，最后提交；`confirmed_by` 与 `submitted_by` 取自可信上下文；提交后不可修改 |

4. **R-7：** `evidence_level` 改为不可原地修改。证据升级必须新建授权记录，旧记录终止并留审计。
5. 不实现：文件物理清除（F-08）、真实对象存储、旧 ID 导入。

**验收（PG16 与 PG17 都做）：**
1. 0001–0009 全新执行、重复执行、漂移拒绝、原子回滚；原有全部测试继续通过。
2. 每个写入函数都要有正向测试和反向测试：跨家庭、缺 Consent、跳过状态、伪造上下文、上下文过期、无关渠道、重复提交。
3. 必须用分离 LOGIN 账号走票据流程测试，不得用超级用户 `SET ROLE` 代替。
4. 确认 app 的表写入授权仍为 0，PUBLIC 可执行函数仍为 0。
5. 补跑全新集群灾备恢复演练。

## 交付与回报

- 任务 A、B、C 各自提交执行报告：`FIX_EXECUTION_REPORT_V1.2_A.md`、`…_B.md`、`…_C.md`（或合并为一份，按任务分节）。
- 每份报告写明：逐步命令、原始输出文件路径、PASS / HOLD、本地提交哈希、Migration SHA-256。
- 完成后回报，由 Claude 复审。**0009 在复审通过并获 Founder 批准前，不得部署到腾讯。**
