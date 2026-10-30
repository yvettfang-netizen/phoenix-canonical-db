# M1 Security Review

Reviewer lens: 玄武｜玄机渊. Engineering result: PASS subject to recorded test evidence.

| Capability | App | Reader | Binder | Exact SERVICE context |
|---|---:|---:|---:|---:|
| Direct M1 table SELECT/DML | denied | denied | denied | denied; API only |
| New controlled API | exact functions | denied | denied | Enterprise/CRM label + scope required |
| Legacy no-event Client APIs | denied | denied | denied | denied to app role |
| PUBLIC execute | denied | denied | denied | denied |

Forced RLS is enabled on all four new tables. Client-party writes require the exact Client Family context and a current Family membership for Person parties. Partner writes require unbound CRM SERVICE context; Referral/Channel relations require an active Lead Source. History/event deletion and rewrite are rejected. Negative tests cover cross-Family calls, overlapping relationships, direct table DML, PUBLIC execution, legacy entry points and event mutation.
