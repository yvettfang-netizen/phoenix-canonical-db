# M0 Security Review

Reviewer lens: 玄武｜玄机渊. Result: engineering controls implemented; production authorization is not granted by this document.

| Surface | App | Reader | Binder | Enterprise SERVICE |
|---|---:|---:|---:|---:|
| Direct new-table SELECT/DML | denied | denied | denied | denied; uses API |
| Controlled organization API | exact functions only | denied | denied | allowed only through bound app connection |
| Legacy two-argument status API | denied | denied | denied | denied |
| PUBLIC function execution | denied | denied | denied | denied |

Controls:

- New tables have `ENABLE` and `FORCE ROW LEVEL SECURITY`.
- All writes use fixed-`search_path`, `SECURITY DEFINER` functions and the existing one-use context-ticket path.
- SERVICE name, principal, channel and absence of a family scope are checked before organization-master mutation.
- Identifier plaintext is not stored; only a SHA-256 digest is retained.
- History/event rows cannot be deleted or silently rewritten. Revocation/termination is explicit and audited.
- Synthetic negative tests cover wrong SERVICE, direct table DML, PUBLIC execution, legacy entry point and event mutation.

Residual boundary: application OIDC provisioning and production SERVICE-principal registration remain governed by the existing FD-6 deployment gate and are outside M0.
