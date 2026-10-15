# Phoenix Canonical PostgreSQL — Claude 第三轮复审报告 V1.2

| 项 | 值 |
|---|---|
| 审计执行 | Claude（独立于 Codex 实施方） |
| 复审时间 | 2026-10-15 12:27–12:40（Asia/Shanghai, +08:00） |
| 复审对象 | `FIX_EXECUTION_REPORT_V1.1.md`（Codex 自报 `R-1–R-4 LOCAL FIX = PASS`）与 `migrations/canonical/0008_expiry_and_ephemeral_cleanup.sql` |
| 前序报告 | `CLAUDE_CANONICAL_DATABASE_AUDIT_REPORT_V1.0.md`（HOLD）、`CLAUDE_CANONICAL_DATABASE_REAUDIT_REPORT_V1.1.md`（HOLD），均保持原样 |
| 规则 | 沿用 `CLAUDE_CANONICAL_DATABASE_AUDIT_INSTRUCTION_V1.0.md`：只读；不连接腾讯云；不使用生产密钥；不修改代码、Migration、Compose、脚本或合同；只新增本报告 |
| 分支 / HEAD | `codex/canonical-postgresql-phase1` / `725661f8d752242136019af9636c1ed26f69e112`（领先 `origin/main` 18 个提交） |
| 本轮新增提交 | `77a757e` fix: close reaudit expiry and cleanup findings；`53c668c` docs: record 0008 evidence；`725661f` chore: pin migration line endings |
| 工作树 | 干净 |

## 0. 一页结论

```text
CODE_AUDIT               = PASS            （已实现的 Schema、RLS、可信上下文与生命周期规则；F-08/F-10 功能缺口另列 HOLD）
LOCAL_RUNTIME            = PASS            （全新 PG16.15 / PG17.11 测试集群；本地开发库另列 HOLD，见 R-6）
TENCENT_ISOLATED_RUNTIME = EVIDENCE_MISSING（未连接；按记录仍运行修复前的 0001–0006）
PRODUCTION_READY         = NO
```

| 轮次 | 本审计实测的未关闭缺陷 |
|---|---|
| V1.0 | 高危 4、中危 6、低危若干 |
| V1.1 | 中危 2（R-1、R-2）、低危 2（R-3、R-4）、流程 1（R-6） |
| **V1.2** | **代码缺陷 0**。新增信息项 1（R-7）；流程项 R-6 仍 HOLD |

**0008 对 R-1 至 R-4 的修复已独立复现通过。** 我另外补测了 7 个生命周期边界情况，除 R-7 外均符合预期。本审计也补跑了 Codex 本轮没有重跑的两项：带 0008 的全新集群灾备恢复，以及新集群的本地认证检查。两项都通过。

**最终仍为 HOLD，原因全部在代码之外：**

- Founder 决策 FD-1 至 FD-8 仍空白，证据 EV-1 至 EV-8 仍缺失；
- 应用写入通道（F-10）与文件清除（F-08）只有草案；
- 腾讯运行时未更新、未核实；
- 宿主机安全事件闸门未关闭。

> **隔离空库通过不等于真实生产切换通过。** 本轮 PASS 只覆盖全新合成测试集群中的 Schema、权限和生命周期机制。它不代表业务合同已签署，不代表应用可以写入、腾讯运行时已更新，也不代表获准导入真实数据或切换生产。

## 1. 复审方法

- **VERIFIED-FILE：**
  - 逐行审阅 0008（252 行）；
  - 核对 0001–0008 的工作树哈希与 HEAD 中的 Git blob 哈希；
  - 核对 `.gitattributes`（`*.sql text eol=lf`），`git ls-files --eol` 显示 0001–0008 均为 `i/lf w/lf`；
  - 抽查 Codex 证据 `phase3-defect-regression-v1.1-pg16/17.txt`：两版各 30 条 PASS、0 条 FAIL；`migration-audit-v1.1-*` 中原子回滚与漂移拒绝均为 PASS。
- **VERIFIED-RUN：** 一次性隔离容器（`--network none`、只读挂载、纯合成数据、一次性口令、`--auth-local=scram-sha-256`），镜像与 compose 锁定的摘要相同（PG16 `ca0bd484…`、PG17 `2d2b8998…`）。执行内容：
  - 0001–0008 全新执行、重复执行、漂移拒绝、原子回滚；
  - Codex 原有 6 套验收；
  - V1.0 与 V1.1 的全部独立探针（T1–T13、T6c–T6f）；
  - 本轮新增的生命周期边界探针 X1–X7；
  - 分离 LOGIN 账号的票据交换测试与 R-4 清理测试；
  - 4 轮重启加 PID 复用；
  - 只建角色的全新集群灾备恢复，并在恢复后的库上运行验收。

  测试结束后已删除全部容器。
- **只读查询** Codex 的本地开发库账本（`default_transaction_read_only=on`）。
- **未重跑** Codex 自己的 `.ps1` 测试，因为它们会重置白名单测试库。

## 2. 事实：文件与哈希（VERIFIED-FILE）

| Migration | 工作树 SHA-256 前缀 | HEAD blob 前缀 | 结论 |
|---|---|---|---|
| 0001–0006 | `eea8d1de` `bef7d9a9` `7dc0c506` `aec2be38` `7bd581d1` `2a3d6cd1` | 相同 | 未改。**PASS** |
| 0007 | `49ec737393a4a4bc` | 相同 | 未改。**PASS** |
| 0008 | `51215c0b4d76e242` | 相同 | 与 FIX V1.1 一致（`51215c0b4d76e242c28197187bf1e017362700128ddd562e2da5d64980a8588d`）。**PASS** |

换行符固定为 LF 后，所有哈希都与历史登记一致，没有因换行转换产生漂移。**PASS**

## 3. R-1 至 R-4 核实（PG16 / PG17 结果相同）

| 项 | Codex 自报 | 本审计实测 | 结论 |
|---|---|---|---|
| R-1 自然过期挡住新授权 | PASS | T6c：Consent 已过期但仍为 ACTIVE 时，新授予被接受。T6d / X1：插入时已过期的顾问分配直接记为 `EXPIRED`，同一 key 的新分配被接受。X6：监护授权自然过期后可新建（`EXPIRED,ACTIVE`） | **PASS** |
| R-2 已撤销或已过期记录被恢复 | PASS | T6e、T6f：清空 `revoked_at` 被 `…_HISTORY_IMMUTABLE` 拒绝，状态保持 `REVOKED`。X2：延长已过期分配被拒绝。X3：强行改为 ACTIVE 被 `REACTIVATION_DENIED` 拒绝。X4：不填 `revoked_at` 直接改为 REVOKED 被 `STATUS_INVALID` 拒绝。X5：撤销后可以重新分配（`REVOKED,ACTIVE`） | **PASS** |
| R-3 函数公共执行权 | PASS | 目录查询 `public_execute_functions=0`。app 可执行的写入类函数只有 `redeem_context_ticket`、`clear_context` 和 3 个 `authorize_*`。app 调用 `sweep_expired_authorizations` 或 `cleanup_ephemeral_state` 都报 `permission denied` | **PASS** |
| R-4 残留记录清理 | PASS | 签发和兑换票据时会自动清理已断开后端的会话。2 秒票据过期后，binder 调用 `cleanup_ephemeral_state()` 返回 `0\|1`，过期票据清零。断开后的残留会话在下一次签发时已被清除（`session_contexts=0`） | **PASS** |

## 4. 回归复测（确认此前修复没有被 0008 破坏）

| 检查 | 结果 |
|---|---|
| T1 跨家庭顾问分配 | 0 / 0。**PASS** |
| T2 渠道方 / T3 顾问 | 只看到 B2，families 0；无 Consent 时 applications 0。**PASS** |
| T5 重启加 PID 复用 | 4 轮中 3 轮 PID 相同（46=46），新连接均为 `family=NULL`。**PASS** |
| T4 / F-02 票据交换 | 分离账号兑换成功；重复使用、伪造、目标错误、超过 60 秒均被拒绝；app 不能读票据表、不能签发、不能 bind；binder 为非成员家庭签发被拒绝。**PASS** |
| T7 审计伪造 | 拒绝；伪造 0 条，受控写入 1 条。**PASS** |
| T8 / T8b 清单目标 | 被拒绝。**PASS** |
| T13 EDUCATION 监护范围 | 可见 1 份文档。**PASS** |
| T12 物理清除 | 仍被阻止。**HOLD**（F-08，与预期一致） |
| 新集群 `pg_hba` 与 socket 认证 | 全部为 `scram-sha-256`；不带口令连接被拒绝。**PASS** |
| 全新集群灾备（只预建角色，按 `restore.sh` 方式） | `pg_restore --exit-on-error` 0 错误；ledger 8、tables 25、policies 20、app_select 19；恢复后的库上 `foundation.sql` 与 `phase3_acceptance.sql` 都 PASS。**PASS** |
| 目录统计 | tables 25、启用 RLS 20、policies 20、SECURITY DEFINER 33 且全部固定 `search_path`、app 写入授权 0 |

## 5. 未关闭事项

| ID | 状态 | 说明 | 关闭条件 |
|---|---|---|---|
| **R-6** 本地开发库账本不一致 | **HOLD** | 只读复查：两个开发库的 0007 仍记录为 `5fcff42c`（当前文件是 `49ec7373`），没有 0008，本地认证仍是 `trust`。Codex 未执行重建，符合等待批准的要求 | Founder 批准后重建本地开发数据卷（涉及 DROP），重建后留存证据 |
| **R-7** 监护证据等级可原地修改（新发现，低 / 信息） | **OPEN（低）** | X7：处于 ACTIVE 的监护授权，可以直接改 `evidence_level`（如 VERIFIED 与 SELF_DECLARED_LEGACY 互改），且不留历史。若把 SELF_DECLARED_LEGACY 原地升为 VERIFIED，就会获得身份文件的访问资格。目前只有 owner 能写，没有应用写入路径 | 与 FC-5（证据审核与取代流程）一起决定：证据升级应新建记录或写审计；可在后续 Migration 中把 `evidence_level` 纳入不可变字段 |
| F-08 文件清除 / F-10 应用写入 | **HOLD** | 只有设计草案；app 写入授权为 0 | EV-3、EV-4、EV-6、FD-5，以及写入 API 的批准 |
| F-04 / F-09 / F-18 语义决定 | **HOLD** | Consent 是否必需、GENERAL 范围是否覆盖身份数据、公开 ID 前缀 | FD-2 / FD-6 |
| R-5 上下文有效期不超过 60 秒 | 设计约束 | 应用每个请求都要重新兑换票据 | 写入 EV-7 / FD-6 |
| F-13 / F-16 运维与凭据 | **HOLD** | 定时与异地备份、凭据存放方式 | FD-7、EV-8，以及 Founder 对凭据方案的确认 |
| 腾讯运行时 | **EVIDENCE_MISSING** | 未连接；按记录运行修复前的 0001–0006，旧数据卷为 `local trust`。V1.0 指出的 F-01 至 F-07 在腾讯库中仍然存在（空库、无应用连接） | 你批准更新后，按 `PG_HBA_SWITCH_PLAN_V1.0.md` 切换认证并补充 `PHOENIX_DB_BACKUP_PASSWORD`；更新前后各采集一次只读原始输出（项目同 V1.0 §9 第 4 项） |
| 生产门禁 | **HOLD / EVIDENCE_MISSING** | 与 V1.1 §6 相同，未变化 | — |

## 6. 生产门禁状态

| 门禁 | V1.1 | V1.2 |
|---|---|---|
| Greenfield Schema 与 Migration 机制 | PASS | **PASS** |
| 访问控制与隔离 | CONDITIONAL | **PASS**（R-7 低危待合同决定） |
| 可信上下文的数据库侧机制 | PASS | **PASS** |
| Web 鉴权、JWKS、连接池 | HOLD | **HOLD**（EV-7、FD-6） |
| 灾备：本地全新集群 | PASS | **PASS**（含 0008） |
| 灾备：RPO/RTO、腾讯恢复演练 | EVIDENCE_MISSING | **EVIDENCE_MISSING** |
| Family Context、Founder OS Freeze、Legacy ID | EVIDENCE_MISSING | **EVIDENCE_MISSING** |
| Docs/Submission、对象存储、Education/Identity 规则 | HOLD | **HOLD** |
| 应用写入通道 | HOLD | **HOLD** |
| 真实数据与生产切换（FD-8） | HOLD | **HOLD** |
| 腾讯隔离运行时 | EVIDENCE_MISSING | **EVIDENCE_MISSING**（修复前版本） |
| 宿主机可信状态 | HOLD | **HOLD** |

## 7. 只读、可逆的下一步建议

1. **Founder 决定：** 是否批准重建本地开发数据卷（R-6）。
2. **Founder 决定：** 是否批准把 0007 和 0008 更新到腾讯隔离空库。批准后由 Codex 先只读采集更新前状态，再按 HBA 切换方案执行，最后采集更新后的原始输出供复审。
3. **Founder：** 签署 `PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md`。其中 FD-2 一并处理 R-7 的证据升级规则，FD-6 写入 R-5 的约束。
4. **后续工程（获批后）：** 在合同批准的范围内起草 F-10 写入 API 的 Migration。届时把 R-7 一并处理。

## 附录：本轮原始输出摘录（PG16.15；PG17.11 除 pid 与时间戳外相同）

```text
A1 APPLIED 0001..0008 ; A2 SKIP 0001..0008 checksum verified
A3 REFUSED 0002_education_identity_skeleton.sql checksum changed (registered bef7d9a902e8… vs file 888558f39b36…)
A4 FAILED 9000_atomicity_probe.sql: ERROR:  SYNTHETIC FORCED MIGRATION FAILURE ; residue: schema=f ledger_row=0 ledger_total=8
A5 PASS foundation | rls_probe | docs_probe | contract_neutral_probe | trusted_context_probe | phase3_acceptance
C  tables=25 rls_enabled=20 policies=20 secdef_functions=33 without_search_path=0 public_execute_functions=0 app_write_grants=0
C  app_exec(volatile)=auth.clear_context,docs.authorize_document_read,education.authorize_application_read,identity.authorize_case_read,auth.redeem_context_ticket
C  pg_hba: all rules scram-sha-256 ; socket without password: fe_sendauth: no password supplied
T6c new Consent while an expired-but-unswept grant exists: ACCEPTED
T6d expired-at-insert assignment lifecycle_status=EXPIRED ; new assignment after natural expiry: ACCEPTED
T6e clearing revoked_at on REVOKED assignment: BLOCKED (ADVISOR_ASSIGNMENT_HISTORY_IMMUTABLE) ; status stays REVOKED
T6f clearing revoked_at on REVOKED guardian authority: BLOCKED (GUARDIAN_AUTHORITY_HISTORY_IMMUTABLE) ; status stays REVOKED
X2 extending valid_until of EXPIRED assignment: BLOCKED (ADVISOR_ASSIGNMENT_HISTORY_IMMUTABLE)
X3 forcing lifecycle_status=ACTIVE on EXPIRED assignment: BLOCKED (ADVISOR_ASSIGNMENT_REACTIVATION_DENIED)
X4 setting REVOKED without revoked_at on ACTIVE assignment: BLOCKED (ADVISOR_ASSIGNMENT_STATUS_INVALID)
X5 new assignment after revocation: ACCEPTED ; lifecycles REVOKED,ACTIVE
X6 new guardian authority after natural expiry: ACCEPTED ; lifecycles EXPIRED,ACTIVE
X7 in-place change of evidence_level on ACTIVE guardian authority: ACCEPTED   <- R-7
R-4 binder cleanup_ephemeral_state(): 0|1 ; after: session_contexts=0 tickets=1 expired_tickets=0
R-4 app cleanup / sweep: permission denied ; PUBLIC-executable list: none
T1 0/0 ; T2,T3 subject-only (B2), families=0 ; T7 REFUSED, forged=0 ; T8/T8b REJECTED ; T13 visible=1 ; T12 BLOCKED
T4 redeem ok (family A, families=1, people=2) ; reuse/forged/wrong principal: CONTEXT_TICKET_INVALID_OR_ALREADY_USED ; >60s: CONTEXT_TICKET_EXPIRY_INVALID
T5 rounds 2-4: stale pid=46 -> first app connection pid=46 family=NULL families=0 people=0
R  pg_restore --no-owner --exit-on-error rc=0 errors=0 ; restored ledger=8 tables=25 policies=20 ; restored-db PASS foundation, phase3_acceptance
DEV (read-only) pg16/pg17 phoenix_canonical_dev: 0007 ledger 5fcff42c (file 49ec7373), no 0008  <- R-6
```

---

**审计声明：** 本复审未修改任何代码、Migration、Compose、脚本或合同文件；未连接腾讯云，未使用生产密钥，未读取口令值或真实数据；未部署、Push、Merge、DROP、TRUNCATE，也未重置任何既有数据库。一次性容器已全部删除，前两轮报告保持原样。**隔离空库通过不等于真实生产切换通过。**

FINAL AUDIT VERDICT = HOLD
