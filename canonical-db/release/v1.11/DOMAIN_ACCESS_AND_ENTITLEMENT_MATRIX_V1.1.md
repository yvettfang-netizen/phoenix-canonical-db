# Domain access matrix V1.1 — Education 0019/0020

| Object | Student | Verified guardian | Other family member | Assigned advisor | Partner | SERVICE | Other family |
|---|---|---|---|---|---|---|---|
| Active institution/program master | Read | Read | Read | Read | Read | Read | Denied without a live context |
| Draft institution/program master | Hidden | Hidden | Hidden | Hidden | Hidden | Created by unbound controlled function; direct read hidden | Hidden |
| Academic/score/language records | Own records | EDUCATION scope | Denied unless subject | Active open/paused assignment + EDUCATION_CASE Consent | Denied | RLS read denied; controlled same-family write allowed | Denied |
| Education plan and targets | Own plan | EDUCATION scope | Denied unless subject | Active open/paused assignment + EDUCATION_CASE Consent | Denied | RLS read denied; controlled same-family write allowed | Denied |
| Application master target | Existing application authority | Existing application authority | Existing application authority | Active application assignment + Consent | Denied | Existing controlled application authority | Denied |

All writes use SECURITY DEFINER functions with fixed `search_path`, audit decisions and no PUBLIC execution. Direct table DML by the app role is denied.

Operations entitlement checks remain absent and do not grant any of these rights.

