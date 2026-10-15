# Phoenix Canonical PostgreSQL — V1.2 任务 C 执行报告

**结论：0009 本地实现与本轮独立验收 = PASS；发布门禁 = HOLD。** 只在本地新增 `0009_application_write_api.sql`，SHA-256 `2a48d016c0b2dd952d56a15853c8092895df057e6a0d69f5ab391803ca0747c2`。0001–0008 字节未改。0009 未部署到腾讯，须先取得 Claude 复审通过与 Founder 后续批准。

## 开工依据和实现

- 签名版决策登记 SHA-256 `ed1d5838ef54e45c1b99f2f18c4bf75fa88ceb10b792d003a247d7097e53d3a0` 与签名记录相符；FD-2 选项 1 和第 6 条 F-10 依据完整。F-10 设计 SHA-256 `1eb356cb7547ca6ad095a9e7cb999dd74d3661f4c02a340e318114fde5d97d79`；业务合同 SHA-256 `f89a1bbe3cff78ed96e8e6620fce7d41837ae4d30de0b9fd91929f2f6bcf4c93`。原始核验见 `evidence/r6-v1.2-C0-gate.txt`。
- 0009 提供 INTERNAL/SERVICE 的 Family、Person、Membership、Student Profile 和 Mock 文档元数据/版本创建；家庭/有分配且有 Consent 的顾问可以创建和推进 Education Application、Identity Case，并按 PREPARING→添加版本→SUBMITTED 操作 Manifest。Consent 由本人或 VERIFIED 对应范围的监护人授予/撤回。状态跳跃、跨家庭、跨渠道和无授权操作返回拒绝并写审计。
- 所有应用写入函数均为固定 `search_path` 的 `SECURITY DEFINER`，撤销 PUBLIC 后仅授予 app 执行；app 对业务表的 INSERT/UPDATE/DELETE 授权为 0。长事务中也用 `clock_timestamp()` 检查写入上下文实际有效期。
- R-7：`evidence_level` 原地更改被触发器拒绝；旧监护授权撤销、新授权创建和到期变更写入审计。文件只接受 `mock/` 不透明键与 SHA-256 元数据，没有真实对象字节或物理清除。

## 实际验收

| 验收 | PG16 | PG17 | 原始命令与输出 |
|---|---|---|---|
| `--network none` 全新集群、0001–0009 正向迁移与重复跳过 | PASS；ledger 9、tables 25、policies 20 | PASS；同左 | `evidence/r6-v1.2-C-final-pg16.txt`、`r6-v1.2-C-final-pg17.txt` |
| 既有六套 SQL 验收 | 6/6 PASS | 6/6 PASS | 同上，`PASS baseline` 各行 |
| 分离 LOGIN 的 binder→一次性票据→app 写入；各 API 正反例 | PASS；ALLOW 36、DENY 43 | PASS；ALLOW 36、DENY 43 | 同上，`SESSION`、`PASS F10 separated-login` 各行；测试源文件 `tests/f10_*.sql` 与 `f10_ephemeral_regression.sh` |
| 跨家庭、缺 Consent、渠道方越权、伪造 GUC、已过期上下文、状态跳跃、重复提交、文档 Consent 缺失 | PASS | PASS | 同上 |
| R-7 证据不可原地修改；旧记录撤销、新记录替代并留下三条审计 | PASS | PASS | 同上，`PASS R-7` |
| app 直接表写权限、PUBLIC 函数执行权限、未固定 search_path 的 SECURITY DEFINER 函数 | 0 / 0 / 0 | 0 / 0 / 0 | 同上，`PASS catalog` |
| 无口令本地 socket 拒绝，HBA local/host 均 SCRAM | PASS | PASS | 同上，`PASS socket` 与 HBA 输出 |
| 0009 漂移拒绝与强制失败原子回滚 | PASS；测试 Schema 不存在、ledger 9 | PASS；同左 | 同上，`DRIFT_REFUSED`、`atomic_schema_exists=false` |
| 专用备份 LOGIN 导出、摘要校验、独立新集群恢复并重跑七项验收 | PASS；372 个归档条目，恢复 ledger 9 / tables 25 / policies 20 | PASS；同左 | 同上，`DUMP_SHA`、`PASS fresh-cluster` |
| 临时资源清理 | 0 F10 容器、0 F10 备份卷、0 临时口令文件 | 同左 | `evidence/r6-v1.2-C-final-cleanup-and-hashes.txt` 及两份完整输出末尾 |

本轮新增的测试入口为 `pwsh -File canonical-db/tests/f10_local_acceptance.ps1 -Version 16` 与 `-Version 17`。所有被测记录均为合成数据；测试后一次性容器与卷已清理。备份摘要未签名，不是远端保全或异地备份方案。

## 尚未关闭

- A 任务的正式开发库重建失败，因此旧的依赖本地 Compose 与既有 `.env` 的 PowerShell 回归脚本（`phase3_defect_regression.ps1`、`phase3_fresh_cluster_restore.ps1`）本轮**未重跑**。本轮以隔离容器中的六套原有 SQL 验收、独立 F-10 回归和全新集群恢复替代；不把未执行的旧脚本写成 PASS。旧恢复脚本的迁移计数已改为按目录动态计算，但该脚本仍待 A 恢复后实测。
- FD-6 的 Web 鉴权、issuer/JWKS、连接池清理、应用所有者继续 HOLD；未接任何真实应用或真实数据。F-08 物理清除与真实对象存储继续 HOLD。
- 数据库内审计与业务事务同生共退；客户端回滚的事务不会留下持久审计。生产级拒绝事件外部留存需在 FD-6 应用鉴权/网关设计中明确，不能由本迁移擅定。
- 0009 的本地测试通过不构成腾讯部署批准。Claude 独立复审与 Founder 后续批准前不得上传或执行 0009。

**本地实施与原始证据提交：** `b6c5304c076fee4b970de319108610784a5c46b7`。未 push、merge 或创建 PR。
