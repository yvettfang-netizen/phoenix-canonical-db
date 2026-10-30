# M5 Architecture — Service Delivery

M5 governs work execution and delivery metadata under the existing Service Project authority.

- Tasks remain Project-scoped and may transfer only to a current Project assignee; each transfer records immutable old/new assignee history and a reason code.
- Milestone templates are versioned, domain-scoped and retire-only. Project milestones reference the exact template version used.
- Deliverables reference an immutable `docs.document_versions` row; Service stores no document body or object payload.
- Submission, changes request, resubmission, review approval, acceptance and withdrawal are separate controlled commands.
- A submitter cannot review their own submission, and the reviewer cannot accept the same reviewed deliverable.
- Delivery events are append-only and retain the exact document version and submission round.
- The historical pre-0035 delivery model remains distinguishable as governance version 1; new writes use version 2 only.

No Person, Family, Student, Principal, Client, document or object-storage master is duplicated.
