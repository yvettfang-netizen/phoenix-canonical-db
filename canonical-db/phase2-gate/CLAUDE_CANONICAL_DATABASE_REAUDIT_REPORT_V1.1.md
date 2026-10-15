# Phoenix Canonical PostgreSQL — Claude 修复复审报告 V1.1

| 项 | 值 |
|---|---|
| 审计执行 | Claude（独立于 Codex 实施方） |
| 复审时间 | 2026-10-15 11:41–11:58（Asia/Shanghai, +08:00） |
| 复审对象 | `FIX_EXECUTION_REPORT_V1.0.md`（Codex 自报 `PHASE 3 AUDIT FIXES = CONDITIONAL PASS`）与 `migrations/canonical/0007_security_boundary_fixes.sql` |
| 基线 | 原审计报告 `CLAUDE_CANONICAL_DATABASE_AUDIT_REPORT_V1.0.md`（FINAL = HOLD），保持原样未改 |
| 规则 | 沿用 `CLAUDE_CANONICAL_DATABASE_AUDIT_INSTRUCTION_V1.0.md`：只读；不连接腾讯云；不使用生产密钥；不修改代码、Migration、Compose、脚本或合同；只新增本报告 |
| 分支 / HEAD | `codex/canonical-postgresql-phase1` / `038be489fc28dbeb794e0f5089b661677ba7b334`（领先 `origin/main` 15 个提交） |
| 本轮新增提交 | `eea5ac6` fix(canonical-db): close audit findings with 0007；`038be48` docs(canonical-db): record audit fix evidence |
| 工作树 | 干净（`git status` 无改动） |

## 0. 一页结论

```text
CODE_AUDIT               = CONDITIONAL   （V1.0：CONDITIONAL，4 项高危 → 现 0 项高危未关闭）
LOCAL_RUNTIME            = CONDITIONAL   （V1.0：9 类独立测试失败 → 现剩 2 类残留）
TENCENT_ISOLATED_RUNTIME = EVIDENCE_MISSING（未变；且腾讯运行的仍是修复前版本）
PRODUCTION_READY         = NO
```

**V1.0 的高危缺陷已在本地实测修复**，PG16.15 与 PG17.11 结果一致：

- 重启后新连接继承旧会话（F-01）
- 跨家庭泄露顾问分配记录（F-03）
- binder 与 app 分离账号后上下文无法传递（F-02，数据库侧机制）

另外，审计伪造（F-05）、提交清单挂错目标（F-07）、监护范围映射错误（F-09）、新集群灾备恢复（F-11）、本地 socket 免口令（F-12，仅对新建集群）也已修复。

**仍未达到 PASS 的原因：**

1. 本轮发现 **2 项中危残留**：
   - 已撤销的分配或监护授权，只要清空 `revoked_at` 就能恢复为 ACTIVE；
   - 自然过期但状态未更新的记录，会挡住新的授权或分配。
2. 应用写入通道仍为 0（F-10，HOLD）。
3. 本地开发库账本与当前 0007 文件不一致。
4. 生产门禁全部未关闭。

> **隔离空库通过不等于真实生产切换通过。** 本轮修复只证明本地合成环境中的访问控制机制可用。它不代表业务合同已签署，不代表应用鉴权已接入、腾讯运行时已更新，也不代表获准导入真实数据或切换生产。

## 1. 复审方法

- **VERIFIED-FILE**：逐行审阅 0007（486 行）、`deploy/tencent/` 的 diff 与新增的 `restore.sh`、本地 `compose.yaml`，以及 4 份设计或方案草案；抽查 `evidence/` 中的原始输出。
- **VERIFIED-RUN**：用一次性隔离容器（`--network none`、仓库只读挂载、纯合成数据、一次性口令）完成以下测试，结束后删除容器：
  - 镜像与修复后 compose 相同：PG16 `sha256:ca0bd484…`、PG17 `sha256:2d2b8998…`，`--auth-local=scram-sha-256 --auth-host=scram-sha-256`；
  - 0001–0007 全新执行与重复执行、漂移拒绝、原子回滚；
  - Codex 原有 6 套验收；
  - V1.0 附录 A 的 T1–T13 更新版；
  - 新增残留探针 T6c–T6f；
  - 用分离 LOGIN 账号测试票据交换；
  - 4 轮重启加 PID 复用；
  - 只建角色的新集群灾备恢复。
- **只读查询 Codex 本地开发库**：设置 `default_transaction_read_only=on`，只查账本和目录。未启动、未重启、未修改。审计期间这两个容器由 Codex 启动并处于运行状态。
- **未重跑** Codex 的 `phase3_defect_regression.ps1`、`phase3_fresh_cluster_restore.ps1` 和 `db.ps1 -Action test`，因为它们会重置白名单测试库，审计边界禁止。只做了代码审阅，并抽查其证据文件。

## 2. 事实：文件与哈希（VERIFIED-FILE）

| Migration | SHA-256 前缀 | 结论 |
|---|---|---|
| 0001–0006 | `eea8d1de…` `bef7d9a9…` `7dc0c506…` `aec2be38…` `7bd581d1…` `2a3d6cd1…` | 与 V1.0 完全一致，未改字节。**PASS** |
| `0007_security_boundary_fixes.sql` | `49ec737393a4a4bc5f1e287add369db4f04fbde1c021521e8b4cf781f966ff93` | 与 FIX 报告一致；只在 `eea5ac6` 中出现过一次。**PASS** |

- 部署包修改已提交（F-14 的本地部分关闭）。
- 本地 compose 的 PG16 与 PG17 都锁定了 sha256 摘要（F-15 关闭）。
- 证据文件中未发现口令值（关键字检索只命中 `PASSWORD '$PHOENIX_…` 这类变量名）。

## 3. 修复逐项核实

| F | Codex 自报 | 本审计核实（PG16 / PG17） | 复审结论 |
|---|---|---|---|
| F-01 重启串号 | PASS | 4 轮"残留记录→重启→第一个新连接"中，第 4 轮 PID 相同（46=46），结果 `family=NULL families=0`。V1.0 同样场景是继承了家庭 A。断开连接后的新连接为 NULL | **PASS** |
| F-02 分离账号 | PASS | binder 签发票据，app 用独立 LOGIN 兑换后看到 `family=A families=1 people=2`。重复使用、伪造、目标 principal 错误都返回 `CONTEXT_TICKET_INVALID_OR_ALREADY_USED`。有效期超过 60 秒的票据返回 `CONTEXT_TICKET_EXPIRY_INVALID`。app 不能读票据表，也不能签发票据或执行 bind；binder 为非成员家庭签发会被 `CONTEXT_FAMILY_MEMBERSHIP_INVALID` 拒绝 | **PASS（数据库侧）**；Web 鉴权与网关仍 HOLD（EV-7）；见 R-5 |
| F-03 跨家庭分配 | PASS | T1：家庭 A 成员可见分配记录 0，家庭 B 记录 0 | **PASS** |
| F-04 渠道越界 | PASS / HOLD | T2：渠道方只看到 B2，memberships 1、families 0。T3：顾问只看到 B2，families 0；无 Consent 时 applications 为 0 | **PASS（机制）**；"是否还需要 Consent"仍 HOLD |
| F-05 审计伪造 | PASS | T7：app 直接写入报 `permission denied for function record_access_event`；受控路径 `authorize_document_read` 正常写入；伪造记录 0 | **PASS** |
| F-06 撤回后无法重授 | PASS | T6：撤回后可以新授 Consent；已撤回的不能重新激活。**但** T6c–T6f 失败（见 R-1、R-2） | **CONDITIONAL** |
| F-07 清单目标 | PASS | T8 被 `SUBMISSION_TARGET_FAMILY_OR_SUBJECT_MISMATCH` 拒绝；T8b 被 `SUBMISSION_TARGET_NOT_FOUND` 拒绝 | **PASS** |
| F-08 物理清除 | HOLD | T12 仍是 `can_purge_document=true` 但删除被阻止；只交了设计草案 | **HOLD**（与自报一致） |
| F-09 监护范围 | PASS / HOLD | T13：EDUCATION 监护范围加对应 Consent 可见 1 份文档；改为精确匹配，GENERAL 不再覆盖 IDENTITY | **PASS（默认拒绝）**；语义仍 HOLD |
| F-10 写入通道 | HOLD | `app_write_grants=0`；只交了设计草案 | **HOLD**（与自报一致） |
| F-11 灾备恢复 | PASS | 按 `restore.sh` 方式只预建角色后恢复：`pg_restore --exit-on-error` 0 错误，ledger 7、tables 25、policies 20、app_select 19；恢复后的库上 `foundation.sql` 与 `phase3_acceptance.sql` 都 PASS | **PASS（本地）**；腾讯实际备份的恢复仍为 EVIDENCE_MISSING |
| F-12 socket 免口令 | PASS | 新集群 `pg_hba` 全部为 `scram-sha-256`；不带口令连 socket 报 `fe_sendauth: no password supplied`。**已初始化的旧数据卷不受影响**：Codex 本地开发库实测仍是 `local trust`，腾讯数据卷只有切换方案 | **PASS（新集群）/ HOLD（现有数据卷）** |
| F-13 备份 | PASS / HOLD | `restore.sh` 恢复前会比对 manifest 摘要；manifest 仍未签名；定时、异地副本、保留期依赖 FD-7 | **CONDITIONAL / HOLD** |
| F-14 Git 一致 | PASS / HOLD | 部署包已提交；腾讯运行版本与提交的对应关系无证据 | **PASS（本地）/ EVIDENCE_MISSING（腾讯）** |
| F-15 镜像锁定 | PASS | compose 已核对 | **PASS** |
| F-16 本机凭据 | HOLD | 只交了存放方案 | **HOLD** |
| F-17 / F-18 合同与 ID 前缀 | HOLD | 合同未改状态，前缀未选 | **HOLD** |
| F-19 健康检查权限 | PASS | `health.sh` 改用 reader，并通过 0600 pgpass 认证；0007 只给 reader 加了账本 SELECT | **PASS** |
| F-20 嵌套事务 | PASS | `install.sh` 已加检查 | **PASS** |

## 4. 本轮新发现的残留问题

| ID | 严重度 | 发现 | 证据（PG16 / PG17 相同） | 影响 | 关闭条件 |
|---|---|---|---|---|---|
| **R-1** | 中 | 自然过期但未清理的记录会挡住新记录：`lifecycle_status` 只在 UPDATE 触发器中计算，INSERT 时默认 `ACTIVE`，过期后也不会自动更新；Consent 的状态同样要人工改为 EXPIRED，而且没有清理任务 | T6d：插入时已过期的分配，`lifecycle_status=ACTIVE`，之后新建分配被 `unique_violation` 阻止。T6c：已过期但仍为 ACTIVE 的 Consent 阻止新授予 | 授权到期后无法续期，F-06 的业务死锁换了一种形式回来 | 让部分唯一索引只覆盖"当前有效"的记录（例如在 INSERT 时也计算状态，并配一个过期清理任务，或改用其他不依赖人工更新的判定），并把 T6c、T6d 纳入回归测试 |
| **R-2** | 中 | "不可重新激活"可以被绕过：对已 REVOKED 的分配或监护授权执行 `UPDATE … SET revoked_at = NULL`，触发器会重新算出 `ACTIVE`。原因是检查用的 `NEW.lifecycle_status` 还是旧值 | T6e：分配 `REVOKED → ACTIVE`，`revoked_at=NULL`。T6f：监护授权 `REVOKED → ACTIVE` | 与 FIX 报告中"历史行不可改回 ACTIVE"的说法不符。目前只有 owner 能写，一旦开放写入 API 就会变成真实漏洞 | 触发器里禁止 `revoked_at` 从非空改为空，以及对 EXPIRED 记录延长 `valid_until`，并加入回归测试 |
| R-3 | 低 | 0007 新增的 4 个函数没有撤销 PUBLIC 执行权（V1.0 时为 0）：`core.can_read_subject_basics`（SECURITY DEFINER）、`casework.protect_advisor_assignment`、`core.protect_guardian_authority`、`docs.validate_submission_target` | 目录查询 `public_execute_functions=4` | 后 3 个是触发器函数，无法直接调用；`can_read_subject_basics` 可以被任何角色调用。属于权限卫生回退 | 先 `REVOKE … FROM PUBLIC`，再只授予 app 与 reader |
| R-4 | 低 | 断开连接留下的会话记录和未兑换的票据，只在下次 bind 或兑换时清理会话；票据表没有任何清理 | T4：残留会话 1 行、未兑换票据 1 张 | 不影响隔离（有 `backend_start` 校验），但两张表会持续增长 | 加入定期清理，并清理过期票据 |
| R-5 | 信息 | 兑换后的上下文有效期等于票据有效期，不超过 60 秒（实测 TTL 59 秒） | T4 | 应用必须每个请求或每个短周期重新兑换票据。这是 EV-7 / FD-6 连接池设计的硬约束 | 在应用鉴权合同中写明 |
| R-6 | 中（流程） | 本地开发库账本与当前文件不一致：两个开发库的 0007 记录为 `5fcff42cce9df982…`，当前文件是 `49ec737393a4…`，说明 Codex 在 0007 应用到开发库之后又改了它。旧版 0007 的字节不在 Git 中，开发库的实际结构**无法核实**。两个开发库的 `pg_hba` 仍是 `local trust` | 只读查询两个开发库：账本 7 行、25 张表、0 行数据、`hba_local=trust`。Codex 在 FIX 报告 §5 中已披露 | 违反"已应用的 Migration 不可修改"的规则；开发库已不能作为证据 | 经 Founder 批准后重建本地开发数据卷（涉及 DROP），重建前不得把开发库当作验收依据 |

## 5. TENCENT_ISOLATED_RUNTIME

- 本轮未连接腾讯云。Codex 也声明本轮未连接、未部署、未更新。
- 按此前报告，腾讯运行的是 **0001–0006 的修复前版本**，数据卷是 `local trust` 初始化的旧卷。V1.0 指出的 F-01 至 F-07 在腾讯库中**仍然存在**。目前是空库、没有应用连接，实际风险低，但不得在其上导入任何数据。
- 若要把 0007 更新到腾讯，需要你批准。还需按 `PG_HBA_SWITCH_PLAN_V1.0.md` 切换旧数据卷的认证方式，并在 `.env` 中补充 `PHOENIX_DB_BACKUP_PASSWORD`：新的 `backup.sh` 和 `restore.sh` 依赖它，而腾讯上的 backup 角色目前无口令。
- **结论仍为 EVIDENCE_MISSING。** 所需原始输出与 V1.0 §9 第 4 项相同。

## 6. 生产门禁（相对 V1.0 的变化）

| 门禁 | V1.0 | V1.1 |
|---|---|---|
| Greenfield Schema 与 Migration 机制 | PASS | **PASS** |
| 访问控制与隔离 | HOLD | **CONDITIONAL**（关闭 R-1、R-2、R-3 后可评为 PASS） |
| Web 鉴权、JWKS、可信上下文、连接池 | HOLD（含技术阻断） | **HOLD**（技术阻断已解除，EV-7 与 FD-6 仍缺） |
| RPO/RTO、灾备 | EVIDENCE_MISSING | **EVIDENCE_MISSING**（本地新集群恢复已 PASS，但 FD-7、EV-8、腾讯恢复演练仍缺） |
| Family Context、Founder OS Freeze、Legacy ID | EVIDENCE_MISSING | **EVIDENCE_MISSING**（未变） |
| Docs & Submission、对象存储、Education/Identity 规则、FD-3/FD-4/FD-5 | HOLD | **HOLD**（未变） |
| 应用写入通道（F-10） | HOLD | **HOLD**（只有草案） |
| 真实数据导入与生产切换（FD-8） | HOLD | **HOLD** |
| 腾讯云隔离运行时 | EVIDENCE_MISSING | **EVIDENCE_MISSING**，且运行修复前版本 |
| 宿主机可信状态（事件闸门 G-1 至 G-8） | HOLD | **HOLD** |

Founder 决策登记 FD-1 至 FD-8 仍全部空白；`evidence/incoming/` 与 `approved/` 仍只有 `.gitkeep`。

## 7. 只读、可逆的下一步建议

1. **Codex（新开 0008，不改 0001–0007）：** 修复 R-1、R-2、R-3，可选修复 R-4；把 T6c–T6f 加入 `phase3_defect_regression`，PG16/17 用分离账号回归。
2. **Founder：** 批准重建本地开发数据卷（R-6），之后用当前文件重新初始化并留存证据。
3. **Founder：** 在 FD-2、FD-6 中处理 F-04 的 Consent 语义、F-09 的 GENERAL 范围、F-18 的 ID 前缀，并把 R-5"每个请求重新兑换票据"写入应用鉴权要求。
4. **腾讯（需你批准）：** 更新之前，先由授权管理员只读采集 V1.0 §9 第 4 项列出的原始输出；更新时按 HBA 切换方案执行，保留证据。

## 附录：复审原始输出摘录（PG16.15；PG17.11 除 pid 外相同）

```text
H  socket, no password: psql: error: connection to server on socket ... failed: fe_sendauth: no password supplied
A1 APPLIED 0001..0007 (0007 sha256=49ec737393a4a4bc…) ; A2 SKIP 0001..0007 checksum verified
A3 REFUSED 0002_education_identity_skeleton.sql checksum changed (registered bef7d9a902e8… vs file 888558f39b36…)
A4 FAILED 9000_atomicity_probe.sql: ERROR:  SYNTHETIC FORCED MIGRATION FAILURE ; residue: schema=f ledger_row=0 ledger_total=7
A5 PASS foundation | rls_probe | docs_probe | contract_neutral_probe | trusted_context_probe | phase3_acceptance
C  tables=25 rls_enabled=20 ; policies=20 ; secdef_functions=28 without_search_path=0 ; public_execute_functions=4 ; app_write_grants=0
C  ticket_table_access app=false binder=false reader=false ; pg_hba: all rules scram-sha-256
T1 family-A member: advisor_assignments visible=0; family-B rows=0
T2 partner: people visible=SYN B2 student; memberships=1; families=0; student_profiles=1
T3 advisor: people visible=SYN B2 student; memberships=1; families=0; applications (needs consent)=0
T7 app direct audit write: REFUSED (permission denied for function record_access_event) ; forged=0 controlled=1
T13 EDUCATION-scope guardian + DOCUMENT_READ/EDUCATION consent: EDUCATION doc rows visible=1
T6  new Consent after withdrawal: ACCEPTED ; T6b reactivating withdrawn Consent: BLOCKED (CONSENT_TRANSITION_INVALID)
T6c new Consent while an expired-but-unswept grant exists: BLOCKED (unique_violation; no expiry sweeper exists)
T6d expired-at-insert assignment lifecycle_status=ACTIVE ; new assignment after natural expiry: BLOCKED (unique_violation)
T6e assignment REVOKED -> clearing revoked_at: ACCEPTED -> lifecycle_status=ACTIVE revoked_at=NULL
T6f guardian authority REVOKED -> clearing revoked_at: ACCEPTED -> lifecycle_status=ACTIVE
T8  REJECTED (SUBMISSION_TARGET_FAMILY_OR_SUBJECT_MISMATCH) ; T8b REJECTED (SUBMISSION_TARGET_NOT_FOUND)
T12 can_purge_document=true ; physical purge: BLOCKED (DOCUMENT_VERSION_IMMUTABLE)
T4  app redeem + read: family=<family A> families=1 people=2 ; context ttl(s)=59
T4  reuse / wrong principal / forged: ERROR:  CONTEXT_TICKET_INVALID_OR_ALREADY_USED ; >60s: CONTEXT_TICKET_EXPIRY_INVALID
T4  app reads ticket table / issues / binds: permission denied ; binder for non-member family: CONTEXT_FAMILY_MEMBERSHIP_INVALID
T4  app new connection after redeem-and-disconnect: family=NULL families=0 ; leftover session_contexts=1 unredeemed_tickets=1
T5  round 4: stale row pid=46 -> first app connection after restart: pid=46 family=NULL families=0 people=0
R   pg_restore --no-owner --exit-on-error rc=0 errors=0 ; restored ledger=7 tables=25 policies=20 app_select_tables=19
R   restored-db PASS foundation.sql ; restored-db PASS phase3_acceptance.sql
DEV (read-only) pg16/pg17 phoenix_canonical_dev: 0007 ledger sha 5fcff42cce9df982 (file 49ec737393a4a4bc) ; tables=25 ; domain_rows=0 ; hba_local=trust
```

---

**审计声明：** 本复审未修改任何代码、Migration、Compose、脚本或合同文件；未连接腾讯云，未使用生产密钥，未读取任何口令值或真实数据；未部署、Push、Merge、DROP、TRUNCATE，也未重置任何既有数据库。一次性容器已全部删除。原审计报告 V1.0 保持原样。**隔离空库通过不等于真实生产切换通过。**

FINAL AUDIT VERDICT = HOLD
