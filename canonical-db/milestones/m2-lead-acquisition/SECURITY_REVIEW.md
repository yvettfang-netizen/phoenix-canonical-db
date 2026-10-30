# M2 Security Review

Reviewer lens: 玄武｜玄机渊. Engineering result: PASS subject to raw evidence.

- New tables use FORCE RLS and have no direct App/Reader/Binder table privileges.
- Exact fixed-search-path SECURITY DEFINER APIs require the CRM SERVICE label and current Lead Family scope (or explicit unbound scope before identification).
- PUBLIC execution and legacy no-attribution Lead creation/manual merge entry points are revoked.
- First/Conversion attribution and referral events are immutable. Candidate and merge records allow only their one terminal transition.
- Tests reject cross-Family creation, direct reads/writes, same-reviewer candidate approval, terminal-state reopening, duplicate conversion touch and history mutation.
- No name, phone, WeChat/OpenID or similar value is used as an automatic identity/dedup key.

Application dashboards remain fail-closed because this milestone grants no general CRM table read API.
