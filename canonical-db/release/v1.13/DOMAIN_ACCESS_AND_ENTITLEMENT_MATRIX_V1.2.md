# Domain Access and Entitlement Matrix V1.2

| Capability | Family / student | Verified guardian | Assigned advisor | Partner | General application SERVICE | Operations SERVICE | Reader / health |
|---|---|---|---|---|---|---|---|
| Read raw entitlement rows or source IDs | Denied | Denied | Denied | Denied | Denied | Denied | Denied |
| Check current subject entitlement | Current subject and family context only | Authorized subject and family context only | Denied | Denied | Current bound subject/family only | Current bound subject/family only | Denied |
| Register source entitlement | Denied | Denied | Denied | Denied | Denied | Controlled function only with exact service label | Denied |
| Revoke source entitlement | Denied | Denied | Denied | Denied | Denied | Controlled function only with exact service label | Denied |
| Expire naturally ended references | Denied | Denied | Denied | Denied | Denied | Controlled function only with exact service label | Denied |
| Direct table DML | Denied | Denied | Denied | Denied | Denied | Denied | Denied |

Entitlement checks return a boolean decision and reason code. They do not disclose external identifiers and do not grant document, learning-sensitive-data, Consent, guardian, advisor, or partner access.

The application integration that maps authenticated runtime calls to the approved Operations service principal remains HOLD. No production principal UUID or credential is committed.

