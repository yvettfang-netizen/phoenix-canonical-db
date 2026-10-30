# M4 Security Review

Reviewer lens: 玄武｜玄机渊. Engineering result: PASS subject to raw evidence.

- The new authorization table uses FORCE RLS and grants no direct App/Reader/Binder table access.
- Commands require the exact Service Management SERVICE label and current Family context.
- PUBLIC execution and the legacy unauthorised Health-subject entry point are revoked.
- Health subject creation requires matching active, unexpired, project-specific authorization.
- Authorization withdrawal ends the linked Health subject; project closure revokes remaining authorizations and ends all active parties/subjects/assignments.
- Ended/revoked history cannot be deleted or reactivated.
- Cross-Family, closed-Project and invalid Principal/Organization operations fail closed.
- No contract FK or implicit Casework/Learning/clinical access is introduced.
