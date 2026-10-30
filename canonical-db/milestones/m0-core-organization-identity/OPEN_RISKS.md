# M0 Open Risks

Data-governance lens: 白虎｜守正关.

| Risk / decision | Status | Boundary |
|---|---|---|
| Real institution registration identifiers | HOLD | M0 stores digest-only values; no real record is imported. Verification authority and evidence retention need an approved operational procedure. |
| Legal entity deduplication across countries | HOLD | Exact canonical ID and controlled review are used; no fuzzy-name auto-merge is implemented. |
| Production OIDC/service-principal provisioning | HOLD | Existing FD-6 gate applies; M0 creates no production credential. |
| Public-ID consumer cutover | HOLD | `org_` is implemented, but application adoption requires a separate release plan. |
| Source attachments | EVIDENCE HOLD | Both supplied instruction text files end mid-section; execution uses only the complete requirements present and does not infer the missing tail. |
| Founder acceptance / merge | PENDING | PR remains unmerged until explicit acceptance. |

No risk is bypassed by an unconstrained UUID or a second master-data table.
