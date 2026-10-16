# Phoenix Canonical PostgreSQL — V1.4 第二批本地执行报告

**结论：E1、E2、E3、D6 = PASS（本地合成验收）；Claude 复审 = PENDING。任务 B = PAUSED。D5、D7 尚未开工。** 没有连接腾讯云，没有部署、推送、合并或创建 PR；没有导入真实或历史数据。

## 依据与边界

- 按 `phase2-gate/CODEX_INSTRUCTION_V1.4_NEXT.md` 执行；V1.1 Founder 补充件的完整 SHA-256 已核对为 `1b6a58f56e9d7132e67788d0028f308959a7bb3f57727626691bed85adb0bcfe`，与指令相同。原始哈希输出和本地凭据泄露检查：`evidence/v1.4-approval-and-secret-check.txt`。
- 只新增 `migrations/canonical/0011_verified_capacity_official_facts_manifest_confirmation.sql`；0011 的 SHA-256 为 `acc638a3d308b9a9c601238843b1f5dea75a4f376cfb4e77a48cd3afb8f1caa8`。`git diff --name-only f41a18397b9834d48f5ad38a26d997c1f3070d3f HEAD -- canonical-db/migrations/canonical` 只列出 0011；0001–0010 未改。
- 本地代码提交：`85df24f243e2ac2da6d0956136d10918f5a807e4`。原始状态、分支、迁移差异、容器与数据行数：`evidence/v1.4-final-state.txt`。

## 分项结果

| 项 | 实施与验收事实 | 原始命令及原始输出 | 状态 |
|---|---|---|---|
| E1 / R-19 | F10 按四位编号加载 Migration；逐次断言处理文件数、目录文件数、账本行数相等。PG16/17 均先应用 0001–0010，输出 `APPLIED 0010_reader_ledger_usage.sql` 与 `ledger=10`；再应用 0011，输出 `ledger=11`；重复运行逐个校验摘要。一次性容器中额外放入空 0012 文件、临时移走 0011 文件，两项均在迁移前被数量守卫拒绝。漂移和原子回滚探针仍通过。 | `pwsh -NoProfile -File canonical-db/tests/f10_local_acceptance.ps1 -Version 16` / `17`；`evidence/v1.4-E1-D6-f10-pg16.txt`、`v1.4-E1-D6-f10-pg17.txt` | PASS |
| E2 / R-18 | 选用方案 1：`Start-Database` 从仅含本地合成凭据的 `.local-roles.env` 读取并校验全部五种 64 位本地角色口令，写入容器内 0600 pgpass；`health` 现在先执行该步骤。PG16/17 上先运行 health，再单独运行 reader 回归。reader 查询账本为 11；reader 写账本、建表及 app/binder 读账本均被权限拒绝。口令未进入输出。 | `pwsh -NoProfile -File canonical-db/scripts/db.ps1 -Action health -Version 16` / `17`，随后分别运行 `pwsh -NoProfile -File canonical-db/tests/reader_ledger_regression.ps1 -Version 16` / `17`；`evidence/v1.4-E2-pg16.txt`、`v1.4-E2-pg17.txt` | PASS |
| E3 / R-17 | `tests/.gitattributes` 添加 `*.sql text eol=lf`；对提交 `85df24f` 运行 `git archive HEAD`，解包后逐个扫描 `.sh`、`.sql`、`.yaml` 的全部字节，49 个文件合计 `CR=0`，每个文件的 SHA-256 均在原始输出中。`core.autocrlf=true` 保持原值。 | `pwsh -NoProfile -File canonical-db/evidence/v1.4-E3-archive-check.ps1`；`evidence/v1.4-E3-archive-check.txt` | PASS |
| D6 / D-12 | 0011 增加不可原地改写的民事能力历史；默认 `UNVERIFIED`。只有绑定同家庭的 INTERNAL SERVICE 可追加有证据引用的状态。本人成年核验前或未成年时不能自行授权；`ADULT_VERIFIED` 可自行授权；回到 `UNVERIFIED` 后仍可撤回已给的授权。VERIFIED 监护人的既有代授权继续通过。 | 上述 F10 两版输出的 `STUDENT_*`、`SERVICE_VERIFY_*` 分离 LOGIN 会话，及恢复后 `f10_d6_immutability_regression.sql` 原始结果 | PASS |
| D6 / D-13 | 0011 增加只可追加的 Education/Identity 官方事实 API；未来观测时间拒绝。DECIDED / RESOLVED 必须有 DECISION 事实且由有效分配并取得 Consent 的顾问或 SERVICE 推进；家庭直接推进被拒绝。 | 上述 F10 两版输出的 `ADVISOR_OFFICIAL_FACT_AND_SUBMIT`、`FAMILY_A_FINISH`、C5 及恢复后不可改写探针 | PASS |
| D6 / D-14 | 0011 增加本人经成年核验或 VERIFIED 监护人确认清单的步骤；确认后条目不可修改。顾问或 SERVICE 才可提交，提交者不得与确认者相同；未确认及家庭直接提交被拒绝。C4/C5/C8 断言已纳入永久 F10 回归。 | 上述 F10 两版输出的 C4/C5/C8、两份已确认清单提交及恢复后不可改写探针 | PASS |

## 数据库与恢复状态

- 本地 PG16、PG17 Compose 容器均为 healthy，仅显示容器内 `5432/tcp`，没有宿主机端口发布。两库 Canonical 账本均为 11；`core.people`、`core.families`、`docs.documents` 均为 0 行。原始输出：`evidence/v1.4-final-state.txt`。
- V1.4 两版完整 F10 均在 `--network none` 一次性源容器完成迁移、分离 LOGIN 合成回归、漂移拒绝与回滚；使用专用 backup LOGIN 导出，校验摘要后在全新一次性容器恢复。恢复结果均为 11 条账本、26 张业务表、20 条策略；基线套件与 D6 不可改写探针通过。两版测试容器和卷已在脚本结束时清理。原始输出同 `evidence/v1.4-E1-D6-f10-pg16.txt`、`v1.4-E1-D6-f10-pg17.txt`。
- 0011 的早期 V1.3 测试输出仅保留为过程记录，本报告的 PASS 依据均来自 E1 数量守卫完成后的 V1.4 原始输出。

## 未完成与下一闸门

- D5（D-9/D-10/D-11，0012 起）与 D7（FD-6/FD-7 本地部分）按 V1.4 指令在本批 Claude 复审通过后再开始；不得把本地通过等同于生产可用。
- 任务 B 继续 PAUSED；腾讯云已上传文件、备份副本及 B0–B3 证据保持原样。本批没有远端操作。
