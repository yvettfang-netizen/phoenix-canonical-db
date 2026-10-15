# Founder 决策补充 V1.2：批准记录

| 项 | 值 |
|---|---|
| 文件 | `canonical-db/phase2-gate/FOUNDER_DECISION_ADDENDUM_V1.2_R9_R10_R11.md` |
| 批准版 SHA-256 | `925c83f4d079ec6a1fd9d211786a961d988eaf0d0f033547f1e5ba485552616e` |
| 批准人 / 角色 | Founder / Founder |
| 时间 | 2026-10-15 17:06 +0800（Asia/Shanghai） |
| 方式 | 会话中的 typed approval，原话："R-9、R-10、R-11 也按推荐方案处理" |
| 记录人 | Claude（只记录，不代为决定） |

## 生效范围

- **D-9：** 写入判定同时写入 `audit.access_events` 和服务器日志（`RAISE LOG`，前缀 `PHOENIX_AUDIT`，只写 ID 和代码）；提供对账方案。日志采集目的地依赖 FD-7，网关审计依赖 FD-6，均保持 HOLD。
- **D-10：** INTERNAL 服务上下文可以不绑定家庭（只用于创建家庭和管理操作）；服务主体只在安装时创建；管理接口只允许 SERVICE 主体调用，覆盖案件、顾问分配、监护授权、渠道授权、登录主体；日常操作不再使用超级用户。
- **D-11：** SERVICE 主体不对应自然人（`person_id` 为空，由约束强制），其他主体必须对应一个自然人；INTERNAL 上下文不设 `actor_person_id`，操作人记录为 principal。

## 效力边界

本批准是 FD-2 的补充裁定，不修改已签名登记表（`ed1d5838…`）和补充 V1.1（`1b6a58f5…`），也不批准真实数据导入、生产切换或恢复任务 B。文件之后如有任何字节改动，须重新批准。
