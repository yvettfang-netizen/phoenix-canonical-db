# F-10 应用写入 API 设计草案

**状态：Codex 起草，Founder 未签署；本文件不创建写入 Migration。**

## 写入原则

- 应用角色不直接取得业务表 INSERT/UPDATE/DELETE 权限。
- 每个写入动作由 `SECURITY DEFINER` 函数或受控服务边界执行，并校验 trusted context、家庭、主体、Consent、状态转换和操作者。
- 所有写入产生审计事件；拒绝采用 fail-closed。
- 文档版本和已提交 Manifest 只允许追加新版本，禁止原地覆盖。

## 计划的写入边界

| 实体 | 创建者 | 可修改字段 | 状态流转 | 必须校验 |
|---|---|---|---|---|
| Family / Person profile | 受信身份服务 | 明确允许的展示字段 | 草稿到确认 | 身份权威、家庭归属、审计 |
| Consent | 主体/授权人或批准服务 | 只允许新增、撤回、到期 | ACTIVE→WITHDRAWN/EXPIRED | 主体、目的、数据分类、期限 |
| Education Application | 家庭成员或获授权顾问 | 合同批准字段 | DRAFT→READY→SUBMITTED→DECIDED/WITHDRAWN | 家庭、学生、Consent、状态事件 |
| Identity Case | 家庭成员或获授权顾问 | 合同批准字段 | DRAFT→EVIDENCE_PENDING→UNDER_REVIEW→RESOLVED/CLOSED | 家庭、主体、Consent、状态事件 |
| Document Version | 授权上传服务 | 只新增 | 版本追加 | 对象摘要、存储键、Legal Hold |
| Submission Manifest | 授权提交服务 | PREPARING→SUBMITTED | 提交后不可修改 | 目标存在、家庭/主体一致、版本摘要一致 |

## 待 Founder 决定

- 每个实体的正式创建者、状态机和字段白名单（EV-4）。
- Advisor/Partner 是否需要 Consent 才能读取主体基本信息（F-04）。
- 应用鉴权、JWKS、服务账号和连接池清理责任（EV-7 / FD-6）。

在这些决定完成前，不创建写入 Migration；现有数据库保持默认拒绝写入。
