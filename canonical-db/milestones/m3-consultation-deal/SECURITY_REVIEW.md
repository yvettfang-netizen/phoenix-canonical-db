# M3 Security Review

Reviewer lens: 玄武｜玄机渊. Engineering result: PASS subject to raw evidence.

- New tables use FORCE RLS and grant no direct App/Reader/Binder table access.
- All App commands are fixed-search-path SECURITY DEFINER functions gated by the exact CRM SERVICE label and current Family context.
- PUBLIC execution and legacy eventless Deal/Deal Item entry points are revoked.
- Consultation and Deal event streams are immutable.
- Cross-Family access, terminal mutation, direct reads, inactive replacement owners and invalid state transitions fail closed.
- Old-owner disablement does not strand a Deal: only the replacement owner must be active during a controlled transfer.
- Health Consultation storage is limited to controlled type/result/next-action codes; raw questionnaire fields are absent.

General dashboards and Founder OS summaries remain closed pending an approved read DTO.
