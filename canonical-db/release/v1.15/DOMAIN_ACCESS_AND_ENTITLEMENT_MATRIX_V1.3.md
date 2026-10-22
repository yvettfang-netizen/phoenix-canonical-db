# Domain Access and Entitlement Matrix V1.3

| Capability | Family / guardian | Teacher | Supervisor | General SERVICE | Learning SERVICE | Partner / advisor | Reader / health |
|---|---|---|---|---|---|---|---|
| Read published course catalog | Controlled function | Controlled function | Controlled function | Controlled function | Controlled function | Controlled function | Controlled function only |
| Read subject Learning card/report | Current family and authorized subject | Current family, effective assignment and current Consent | Current family and current Consent | Denied | Controlled function in bound family | Denied | Denied |
| Create enrollment | Denied | Denied | Denied | Denied | Controlled function plus current Operations entitlement | Denied | Denied |
| Assign teacher / create class or schedule | Denied | Denied | Controlled function | Denied | Controlled function | Denied | Denied |
| Record attendance / draft card or report | Denied | Effective assigned teacher only | Controlled function | Denied | Controlled function | Denied | Denied |
| Publish or retract card | Denied | Denied | Controlled function only | Denied | Controlled function | Denied | Denied |
| Grant Learning Consent | Authorized subject / guardian path | Denied | Denied | Denied | Denied | Denied | Denied |
| Direct Learning table SELECT or DML | Denied | Denied | Denied | Denied | Denied | Denied | Denied |
| Read raw Operations entitlement rows or source IDs | Denied | Denied | Denied | Denied | Denied | Denied | Denied |

Runtime access is through signature-specific functions with fixed `search_path`; PUBLIC execution is revoked. Staff database LOGIN accounts are separate from the context binder and redeem one-use tickets. Application authentication, environment-specific principal provisioning and real Operations synchronization remain HOLD.

