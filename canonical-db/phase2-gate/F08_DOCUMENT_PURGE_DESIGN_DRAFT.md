# F-08 文档物理清除设计草案

**状态：Codex 起草，Founder 未签署；不产生清除权限，不改变现有合同状态。**

## 设计

1. PostgreSQL 只负责判定：`retention_until` 已到期、无 `legal_hold`、没有已提交 Submission Manifest、文档已撤回或满足最终 DS-5 条件。
2. 新增专用 `phoenix_canonical_purge_runtime` `NOLOGIN` 能力角色；默认不授予任何运行时账号。
3. 由受控 `docs.purge_document_metadata(p_document_id, p_reason)` 函数执行元数据清除，函数必须再次检查 Legal Hold、提交状态、撤回状态和审计上下文。
4. 对象存储字节由独立清除 worker 按 `storage_key` 删除，删除前必须校验数据库返回的 SHA-256 和对象版本。
5. 每次清除写入不可修改的审计事件；失败时不删除数据库元数据。

## 待 Founder 决定

- DS-5 的保留期、撤回定义和 Legal Hold 优先级。
- 清除权限持有人、审批人、双人复核和撤销方式。
- 对象存储 provider、区域、跨境限制和备份清除顺序（EV-6）。

在 FD-5、EV-3、EV-6 完成前，不创建 Migration，不授予清除权限，不删除任何对象。
