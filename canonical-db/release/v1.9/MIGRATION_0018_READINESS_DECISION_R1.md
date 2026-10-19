# 迁移 0018 就绪决定 R1（V1.9-R1 P5）

## 0. 2026-10-19 执行结果

Founder 已明确批准 N-2 与 D-2，原 C-3、C-4 门禁关闭。正式 0018 已创建并在隔离的 PG16/PG17 上通过 PowerShell、Git Bash、全新集群恢复及本地开发库验收。当前 SHA-256 为 `063f8ba5b57de24208579369ce75424526737953319544d0174c5a31e3f5d74b`，实现与原始证据提交为 `3bb16a3075ca10cb38aeb2f8e091a98369d70752`。详见 `../../FIX_EXECUTION_REPORT_V1.10.md`。

**当前决定：0018 本地实现与验收 = PASS；腾讯部署 = HOLD。**

以下内容保留为 R1 开工前的历史门禁记录。

**历史决定：** **0018 未就绪，不得开工。** 当时开工前提中有两项未满足（Founder 批准 0018 范围；D-2 撤销 binder 执行权的批准）。
**历史状态：** 当轮没有创建 0018 文件，冻结的 0001–0017 未修改。

## 1. 开工条件逐项核对

| # | 条件 | 状态 | 依据 |
|---|---|---|---|
| C-1 | E-R6 先写失败测试，再修复 | **已满足** | `tests/f10_v19_e_r6_repro.sh` 的 T-D2 至 T-D6；现行代码上 5 个 FINDING（PG16、PG17）|
| C-2 | 候选修复在一次性容器中验证 | **已满足（PG16 与 PG17）** | 复现：5 个 FINDING → 0；完整 F10：候选与基线的 PASS/FAIL 序列相同（PG16 与 PG17 均为 191 PASS、5 项预期拒绝、审计 249/248/1）|
| C-3 | Founder 批准 0018 的范围（含 E-R6 修复）| **未满足** | 决定项 N-2（`FOUNDER_DECISION_SUMMARY_R1.md`）|
| C-4 | D-2：撤销 binder 对 `auth.bind_context` 的执行权 | **未满足** | 尚未批准；**尚未在容器中验证**（NOT RUN）|
| C-5 | 属主模型（D-1）| **不纳入 0018** | 见 C-7 |
| C-6 | 恢复方式（D-1b）| **不纳入 0018** | 去掉 `--no-owner` 的验证本轮 NOT RUN（见 `LEAST_PRIVILEGE_OWNER_RESTORE_OPTIONS_R1.md` 第 4 节）|
| C-7 | 冻结的历史迁移不得修改 | **已满足** | git 核对为空 |
| C-8 | 候选文件不在 `migrations/` 目录 | **已满足** | `tests/candidates/e_r6_0018_candidate.sql` |
| C-9 | pwsh 版本的 F10 脚本 | **PASS（2026-10-19）** | PG16 / PG17 的 F10、缺陷回归、SCRAM 与全新集群恢复全部通过；不是 0018 开工条件，现已关闭 N-5 |
| C-10 | 学习域与 ASKWISE 的设计来源 | **BLOCKED** | Notion 五页本轮 ACCESS BLOCKED。不影响 0018（0018 只涉及现有实体），但影响 0019 及之后的批次 |

**结论：** C-3、C-4 未满足，所以 0018 不能开工。C-1、C-2、C-7、C-8 已满足。

## 2. 0018 建议范围（PROPOSED）

| 项 | 内容 | 是否进入 0018 | 依据 |
|---|---|---|---|
| E-R6 状态检查 | `core.can_read_subject_basics`、`casework.is_current_advisor_for_case`、`assignments_read` 的顾问分支增加 `c.status IN ('OPEN','PAUSED')` | **是**（候选已验证）| E-R6 文件第 6 节 |
| 撤销 binder 的 `auth.bind_context` 执行权 | 撤销旧入口 | **是，但需要 C-4 批准**，且需要先在容器中验证（NOT RUN）| `DATABASE_OWNER_SECURITY_DECISION_V1.0.md` R-6 |
| `close_case` 结束分配 | 改变生命周期模型 | **否**：需要先决定 N-3（产品规则）| E-R6 文件第 6 节 |
| 属主转移（D-1）| 改变属主 | **否**：需要 D-1 批准与 R-1 接受 | 属主文件 |
| 恢复方式（D-1b）| 去掉 `--no-owner` | **否**：验证未完成 | 属主文件第 4 节 |
| 身份映射约束（一对一唯一）| 新增 CHECK 或唯一约束 | **否**：需要先核对 Education Compass 历史数据是否一对多 | 映射契约第 2 节 |
| 学习域表 | 新增 learning schema | **否**：属于 0019 及之后（见 `learning-v2.0/LEARNING_MIGRATION_PLAN_V2.0.md`）| — |

## 3. 0018 的验收门槛（进入开工后）

1. 0018 作为新迁移文件，经由 `install.sh` 的 wrapper 应用，账本写入 sha256。
2. F10 完整套件（PG16 与 PG17）通过；E-R6 的 T-D2 至 T-D6 从 FINDING 变为 PASS，并接入 F10 门禁。
3. 迁移后与候选的函数体逐字一致（diff 为空），否则需要重新验证。
4. 0001–0017 的 sha256 与账本一致（漂移检查通过）。
5. 数据库目录回归（`security_catalog_audit.sql`）与 SECURITY DEFINER 清单更新。
6. 对 binder 撤销执行权后，`f10_v18_identity_pool.sh` 与绑定相关用例通过。

## 4. 对"是否可以开工"的直接回答

- **现在不能开工。** 原因：没有 Founder 对 0018 范围的批准。
- **Founder 批准后可以开工的部分：** E-R6 状态检查（候选已在隔离容器中验证）。
- **仍需单独决定的部分：** D-2（binder 执行权）、N-3（关闭个案是否结束分配）、D-1 与 D-1b（属主与恢复）。它们不得夹带在 0018 中。
- **不因测试通过而推断生产安全。** 上述结果只代表隔离的开发容器，不代表腾讯环境或任何生产数据。

## 5. 本决定的范围

- 不涉及腾讯环境、生产数据、`phoenix_core`、Founder OS D1 数据。
- 不合并 main，不推送任何远程，不删除任何卷。
