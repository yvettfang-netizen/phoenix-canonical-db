# M3 Architecture — Consultation & Deal Management

M3 extends the existing CRM authority. Consultation captures structured scheduling, outcome and next-action codes; it deliberately has no raw Health questionnaire or diagnosis payload.

- Consultation lifecycle: SCHEDULED → IN_PROGRESS → COMPLETED, with CANCELLED/NO_SHOW terminal paths.
- Deal lifecycle: OPEN → QUALIFIED → PROPOSAL → NEGOTIATION → WON/LOST, with controlled cancellation.
- Amount, status, owner, scope and project-candidate changes append immutable events.
- A Deal keeps one active primary sales assignment; a disabled old Principal does not block controlled transfer to an active Principal.
- Deal items and candidates support the approved domains and four Compass kinds.
- Follow-ups are controlled commands; no direct table DML is granted.

Payment and contract authority remains outside CRM. Existing Person, Family, Client and Principal masters are reused.
