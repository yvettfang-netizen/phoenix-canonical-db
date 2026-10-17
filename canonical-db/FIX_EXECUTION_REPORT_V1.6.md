# Phoenix Canonical PostgreSQL — V1.6 最终执行报告（第四批：合同缺口 T1–T4 / Migration 0015）

**结论：V1.6（0015，T1–T4）= PASS。** PG16、PG17 均通过同等级完整 F10，以及全新集群恢复。

- **复核内容：** Claude 独立复跑并审读代码，同时复核了 V1.5（0012–0014）；
- **复跑中的新发现：** 3 项缺陷，其中 2 项 P1、1 项 P2，都在 V1.5 / 0004 的既有代码中，不在 0015；移交第四阶段，用新 Migration 修复，见第 5 节；
- **边界：** 未连接腾讯，未推送远程，未使用真实数据或生产凭据。

**执行：**
- 实现与 PG16 / PG17 首轮验收：Codex（2026-10-17 13:32–13:36，因额度用尽未写报告、未提交）；
- 收尾、独立复跑、本报告与本地提交：Claude Code（2026-10-17 13:43–13:55，依据 `PHOENIX-DB-FINAL-CLOSEOUT-20261017` 授权）。

## 1. 依据

- **指令：** `phase2-gate/CODEX_INSTRUCTION_V1.6_CONTRACT_GAPS.md`；批准记录 `phase2-gate/evidence/approved/EV1_EV3_EV4_CONTRACTS_V1.0_APPROVAL.md` 第 2 节（E1-2、E1-4 / E3-6、E3-1、E4-3）。
- **合同哈希：** 三份合同（EV-1 `3f73f167…`、EV-3 `0d9fb898…`、EV-4 `6e6c970d…`）已复核，与仓库中文件一致，自批准后未改动。

## 2. 环境

| 项 | 值 |
|---|---|
| 主机 | Windows 11（MINGW64 10.0-26200），Docker 29.8.2；本机没有 pwsh，Claude 复跑用 bash 等价脚本 |
| PG16 镜像 | `postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d`（16.15） |
| PG17 镜像 | `postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3`（17.11） |
| 测试容器 | 一次性容器，`--network none`，没有端口映射，合成凭据，结束即清理 |
| 复跑前的分支 HEAD | `05fca5b`（V1.5 报告）；V1.6 文件当时未提交 |

## 3. Migration 0015

| 文件 | SHA-256 |
|---|---|
| `migrations/canonical/0015_contract_gap_controls.sql` | `a639f9f10c5130c7…`（完整值见 `evidence/claude-v1.6-closeout-pg16.txt` 开头的 MIGRATION_SHA256 段，以及本提交） |

**0001–0014 未被改写：** 逐个比对文件 SHA-256 与历次登记值，全部一致；每个文件在 Git 历史中都只被提交过一次。

**代码审读：**

| 项 | 实现 | 结论 |
|---|---|---|
| T1 | `core.end_family_membership`：只能提前，不早于当前时间和起始时间，已结束的不可再改。`core.rename_person` / `core.rename_family`：只允许绑定该家庭的 INTERNAL SERVICE 调用；审计和日志不写名称 | 符合 |
| T2 | `docs.can_read_document` 的 ADVISOR 分支增加条件：本家庭存在主体相同、状态为 OPEN / PAUSED 的个案，且当前顾问在该个案上有 ACTIVE、未撤销、在有效期内的分配 | 符合 |
| T3 | `docs.withdraw_document`：本人（不论民事能力）、范围匹配的监护人、绑定该家庭的 SERVICE 可以撤回；只能撤回一次。触发器 `protect_document_withdrawal` 禁止清空或修改 `withdrawn_at` | 符合 |
| T4 | `identity.advance_case` 增加 DRAFT→CLOSED 与 EVIDENCE_PENDING→CLOSED；RESOLVED 仍须有 DECISION 事实 | 符合 |
| 权限 | 新函数均为 `SECURITY DEFINER` 并固定 `search_path`，撤销 PUBLIC 后只授予 app；恢复后的目录回归结果为 `app_write=0`、`public_execute=0`、`secdef_without_path=0` | 符合 |

## 4. 测试结果

| 项 | PG16 | PG17 | 证据 |
|---|---|---|---|
| Codex 首轮完整 F10（pwsh） | PASS（13:36:23） | PASS（13:36:55） | `evidence/v1.6-f10-pg16.txt`、`-pg17.txt`；invocation 文件 |
| Claude 独立复跑（bash 等价流程） | PASS，退出码 0 | PASS，退出码 0 | `evidence/claude-v1.6-closeout-pg16.txt`、`-pg17.txt`；脚本 `claude-v1.6-closeout-run_f10.sh` |
| 迁移顺序与守卫 | 先只放 0001–0010，得到账本 10；再加 0011–0015，得到账本 15、表 26、策略 20；重复执行逐个校验摘要；多一个 0016、缺 0015、多一个未编号文件，三种情况都被拒绝 | 同 PG16 | 同上 |
| 基线套件（6 个）、API 播种、F10 回归、C1–C10、R-20（12 种组合）、G1–G5、T1–T4、T3 触发器 | 全部 PASS | 全部 PASS | 同上 |
| D-9 对账 | 日志 225 条，与数据库对上 224 条，仅存在于日志的 1 条，正是被回滚的跨家庭拒绝；日志中没有名称 | 同 PG16 | 同上 |
| 不可修改（D6）与 D-11 安装器 | PASS | PASS | 同上 |
| 安全检查 | 无口令的本地 socket 被拒；pg_hba 全部为 `scram-sha-256`；0009 漂移被拒；强制失败后原子回滚，不留残余 schema | 同 PG16 | 同上 |
| 全新集群恢复 | backup LOGIN 导出（473 个条目）→ 新集群恢复，得到账本 15、表 26、策略 20、合成人员 7；9 个恢复后套件（含目录回归、D6 不可改写、T3 触发器）全部 PASS | 同 PG16 | 同上 |
| 网络 | 源容器、恢复容器均为 `network=none`，没有端口映射 | 同 PG16 | 同上 |

**对旧测试改动的复核：**
- Codex 对 4 个已有测试文件的改动，均为 Migration 数和账本数守卫的同步（14→15），以及验收脚本的文件名和步骤更新；
- 唯一一处断言反转是身份案件 DRAFT→CLOSED，从"应拒绝"改为"应允许"，这正是已批准的 E4-3 / T4；教育申请不许跳级的断言保留；
- **没有降低任何断言。**

## 5. 复跑中的新发现（不属于 0015，移交第四阶段修复）

用于发现问题的探针：`evidence/claude-v1.6-closeout-probes.sh`。PG16 与 PG17 结果一致。

| 编号 | 等级 | 现象（实测） | 违反的已批准规则 | 位置 |
|---|---|---|---|---|
| V16-F1 | P1 | 服务关闭个案 4011 后，同一顾问仍能为该个案关联的申请 4001 录入官方事实。对照组：关闭前允许，证明顾问原本有权限。原因：`casework.has_active_advisor_assignment` 不检查个案状态（也不检查分配的 `lifecycle_status`），顾问只要在同一家庭还有其他未关闭个案，就能继续写。0015 中 T2 的读文件判断已排除关闭的个案，读写规则因此不一致 | EV-1 第 8.1 条、BC：须有**有效**个案分配 | 0004 中的函数，经 0009 / 0011 的写入判断调用 |
| V16-F2 | P1 | 服务能创建"主体为监护人、却引用学生申请 4001"的个案；分配检查又不看主体，顾问因此可能凭这样的个案取得对该学生申请的写权限（仍需该学生授予的 Consent） | EV-4 第 1 节第 2 条（个案引用申请或案件时，二者应属同一主体） | 0013 `casework.create_case`；0004 的分配检查 |
| V16-F3 | P2 | 对已有有效分配的组合再次创建分配，直接抛出唯一键异常，而不是返回留审计的拒绝。结果仍是拒绝，但这次判定不会写审计 | 补充 V1.2 D-10："默认拒绝，并写审计" | 0013 `casework.create_advisor_assignment` |

## 6. 运维提示（写入上线手册，不是缺陷）

0012 给 `auth.session_contexts` 与 `auth.context_exchange_tickets` 增加了 CHECK 约束。如果升级时库中残留旧式 INTERNAL 临时上下文（带操作人），0012 会整体回滚，阻断升级。升级前必须停止 binder 与应用，确保临时上下文为空。临时上下文本身是可丢弃数据。

## 7. 提交

- **本提交包含：**
  - Codex 的 V1.6 实现（0015、2 个新测试、4 个测试改动）与其原始证据（12 个 `v1.6-*` 文件）；
  - Claude 的复跑脚本、探针与输出（4 个 `claude-v1.6-closeout-*` 文件）；
  - 本报告。
- **提交前扫描：** 23 个文件中没有私钥、令牌或口令值；长十六进制串与本地凭据文件没有重合；没有非回环 IP。
- **未推送远程：** 按 `PHOENIX-DB-FINAL-CLOSEOUT-20261017`，本阶段不推送。
