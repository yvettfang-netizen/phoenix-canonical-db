# Founder Decision Register V1.0 — 签名记录

| 项 | 值 |
|---|---|
| 文件 | `canonical-db/phase2-gate/PRODUCTION_DATABASE_FOUNDER_DECISION_REGISTER_V1.0.md` |
| 签名所依据的预填版 SHA-256 | `e6d1f2273ff534fb4f39c1ebe927b6e97bef446fad4e0a603aff32c196121247` |
| 签名版 SHA-256 | `ed1d5838ef54e45c1b99f2f18c4bf75fa88ceb10b792d003a247d7097e53d3a0` |
| 签名人 / 角色 | Founder / Founder |
| 签名时间 | 2026-10-15 14:37 +0800（Asia/Shanghai） |
| 签名方式 | 会话中的 typed approval，原话："按预填确认，签名：Founder" |
| 记录人 | Claude（只记录签名，未参与决定） |

## 生效范围

- **生效：**
  - FD-1：本期只批准空库。
  - FD-2：批准 `CANONICAL_BUSINESS_CONTRACT_V1.0_EFFECTIVE.md`（SHA-256 `f89a1bbe…`）作为新库基线，包括 6 条补充裁定。其中第 6 条批准 `F10_APPLICATION_WRITE_API_DESIGN_DRAFT.md`（SHA-256 `1eb356cb…`）作为写入接口的依据。
  - FD-3：本期不复用 Founder OS。
  - FD-4：本期不导入旧 ID。
  - FD-5：只存文件元数据。
  - FD-7：空库阶段的运维数值。
  - FD-8：只批准腾讯隔离空库，并允许更新到 0001–0008。
- **维持 HOLD：** FD-6 应用鉴权。
- **签名时空缺，不视为已决定：** FD-7 值班负责人；FD-8 固定变更窗口；FD-6 负责人、issuer 和 JWKS。

## 效力边界

本签名**不批准**以下任何一项：真实数据导入、旧 ID 对账、真实对象存储、应用生产切换、宿主机安全事件闸门（G-1 至 G-8）的关闭。签名版文件之后如有任何字节改动，须重新签名，并重新计算 SHA-256。
