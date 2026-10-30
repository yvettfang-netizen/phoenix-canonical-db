# M5 Security Review

Reviewer lens: 玄武｜玄机渊. Engineering result: PASS subject to raw evidence.

- New template and delivery-event tables use FORCE RLS and grant no direct App/Reader/Binder table access.
- Every command requires the exact `canonical_service_v2` SERVICE principal and current Project Family context.
- Task transfer requires the target Principal to hold a live assignment on that Project.
- New deliverables require a current Project subject and exact document/version pair in the same Family and subject.
- Legacy unversioned create/transition entry points are revoked from the App role.
- Review requires a live Project assignment and cannot be performed by the last submitter; acceptance cannot be performed by the reviewer.
- Delivery events, terminal deliverables and retired templates are immutable.
- Cross-Family, closed-Project, mismatched-document and unassigned-Principal attempts fail closed and are audited.
- Service tables contain no body, content, payload or blob columns.
