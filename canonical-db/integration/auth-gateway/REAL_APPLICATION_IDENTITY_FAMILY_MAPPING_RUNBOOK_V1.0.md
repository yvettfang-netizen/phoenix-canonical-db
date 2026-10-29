# Real Application Identity + Family Mapping Registration Runbook V1.0

- **Status:** REVIEW CANDIDATE / REAL EXECUTION HOLD
- **Scope:** first per-record Phoenix Family OS `usr_*` identity plus `fam_*` to Canonical family mapping
- **Source system:** `PHOENIX_FAMILY_OS`
- **Issuer:** `https://api.phoenixnova.com.cn/canonical-identity`
- **Database baseline:** Migrations `0001`–`0023`

This runbook prepares an evidence packet and fail-closed execution sequence. It
does not approve or create a real record. A completed packet, validator PASS or
Founder signature is not permission to bypass a missing database management API.

## 1. Current executable boundary

| Capability | Current mechanism | State |
|---|---|---|
| Register external identity | `auth.register_external_identity(...)` under a valid INTERNAL SERVICE context | AVAILABLE, but each real record still needs evidence and authorization |
| Disable external identity | `auth.disable_external_identity(...)` | AVAILABLE; access-reducing rollback |
| Resolve identity/family and issue one-use ticket | `auth.issue_application_family_context_ticket(...)` | AVAILABLE to binder only |
| Create/verify family legacy mapping | No controlled function; runtime roles have no direct table write | **HOLD** |
| Revoke/supersede family legacy mapping | No controlled function | **HOLD** |

Direct `INSERT` or `UPDATE` against `integration.legacy_id_mappings` by
`phoenix_bootstrap`, a migration owner or an ad-hoc privileged session is
forbidden for a real record. The absence of a write API is a deliberate
fail-closed stop, not an instruction to escalate privileges.

## 2. Required input packet

Start from `REAL_APPLICATION_MAPPING_REQUEST_TEMPLATE_V1.0.json`. The filled
real packet must be stored in the approved private evidence system and must not
be committed to Git. It contains only stable IDs, evidence references and
digests; do not copy names, phone numbers, email addresses, OpenID/UnionID,
tokens, credentials or identity-document contents into it.

Required facts:

1. exact target environment and bounded change window;
2. exact issuer, application `usr_*` subject and application `fam_*` ID;
3. pre-existing ACTIVE Canonical FAMILY principal/person and Canonical family;
4. current family membership joining that person to that family;
5. fresh UUIDv7 IDs for the external identity and family mapping records;
6. application ownership evidence reference + SHA-256;
7. Canonical principal/family/membership evidence reference + SHA-256;
8. per-record Founder approval reference + SHA-256;
9. operator, reviewer and rollback-owner Canonical references;
10. explicit acknowledgements that automatic/name/phone/ID-shape matching and
    direct table writes are forbidden.

Run the offline structural gate:

```powershell
pwsh -NoProfile -File ./validate_application_mapping_request.ps1 -Path <private-request.json>
```

`PASS` means only that the packet has the expected shape and contains no known
forbidden fields. It does not validate the truth of evidence or authorize a
database change.

## 3. Read-only preflight

All preflight output must be boolean/count/digest evidence; do not print the
real subject, family ID, token, credential or customer data.

1. Pin and record the private repository commit and verify Migrations
   `0001`–`0023` against the ledger.
2. Verify the application server owns the exact `usr_*` → `fam_*` relationship
   using an approved internal read path. Do not query by name, phone, OpenID or
   apparent identifier similarity.
3. Verify the Canonical principal is ACTIVE and kind `FAMILY`, has the expected
   actor person, and the expected membership is current for the expected family.
4. Verify no ACTIVE external identity already exists for the exact issuer +
   subject and no conflicting VERIFIED mapping exists for the exact source +
   kind + application family ID.
5. Verify app and binder use distinct protected credential files and distinct
   LOGIN pools; no credential may appear in command history or evidence.
6. Take and verify the required non-production backup before the change window.

**Current stop:** steps 3 and 4 do not have a least-privilege, per-record
preflight interface for all mapping facts. Do not replace them with a privileged
interactive query. Continue only after the forward management API described in
section 7 is approved, implemented and independently tested.

## 4. Intended registration sequence after the HOLD closes

The following sequence is a future execution contract, not a command list for
the current database:

1. Open one correlated change request and bind its evidence digests.
2. Under an INTERNAL SERVICE context, call the controlled external-identity
   registration function. Record only allow/deny, reason code, request nonce and
   resource ID in the audit evidence.
3. Through the future controlled family-mapping API, create a PENDING proposal,
   verify its evidence, then promote exactly one mapping to `VERIFIED`.
4. Use the binder resolver with the exact issuer, `usr_*` subject and `fam_*`
   ID. It must return exactly one principal/actor/family/ticket tuple.
5. Redeem once with the separate app LOGIN, call one approved read route, clear
   context and verify no session/ticket residue.
6. Run negative probes for wrong subject, wrong family, duplicate request,
   disabled identity and revoked mapping. All must deny.
7. Close the change only after audit correlation, backup reference and rollback
   owner are recorded.

## 5. Abort conditions

Abort without partial continuation if any of the following occurs:

- a packet field or evidence digest differs from the approved record;
- any match depends on a name, phone, OpenID/UnionID, document number or ID shape;
- more than one candidate principal, family, membership or mapping is found;
- the principal, family or membership is missing/inactive/expired;
- app and binder credentials or pools are not separate;
- a direct table write or bootstrap session would be required;
- audit correlation, context clearing or `DISCARD ALL` cannot be proven;
- the requested environment is not the approved isolated non-production target.

## 6. Rollback

1. Disable the external identity through `auth.disable_external_identity(...)`;
   do not delete it or clear its audit history.
2. Revoke the family mapping through the future controlled revoke API.
3. Verify the atomic resolver returns zero rows and the three HTTP routes fail
   closed for that subject/family pair.
4. Verify session contexts and unredeemed tickets are zero.
5. Preserve the request, approval, audit correlation and rollback evidence.

Because the controlled family-mapping revoke API does not yet exist, complete
rollback is currently impossible without prohibited privileged DML. Therefore
real registration remains HOLD even though identity disablement is available.

## 7. Forward Migration decision gate

A new Migration (`0024` or later) must be separately approved before real
registration. At minimum it must provide:

- least-privilege proposal, verification and revoke/supersede functions for
  `PHOENIX_FAMILY_OS` + `FAMILY` mappings;
- exact input validation, one active VERIFIED mapping per application family ID,
  and collision refusal for a Canonical family already mapped to another active
  application family unless an explicit supersession decision exists;
- evidence reference/digest and operator/reviewer attribution;
- append-only allow/deny audit with request nonce;
- safe retry/idempotency and transaction locking;
- no PUBLIC, reader, app direct-table or binder write privilege;
- PG16/PG17 positive, duplicate, collision, wrong-source, wrong-kind, rollback,
  RLS and fresh-restore regression.

Whether proposal and verification must be performed by two distinct people is a
Founder decision for this new mapping workflow. Existing V1.4 dual-control rules
do not explicitly name family legacy mappings, so this runbook does not invent
that policy.

## 8. Security and governance result

- **Critical / High:** none established in the current fail-closed state.
- **Medium:** no controlled family-mapping create/revoke interface; real
  registration and rollback cannot safely execute.
- **Low / operational:** a filled request contains pseudonymous identity links
  and must remain outside Git and ordinary logs.
- **HANDOFF_REQUIRED: 白虎:** privacy, retention and operator/reviewer governance
  for filled real-record evidence must be reviewed before use.

**Gate result:** `RUNBOOK READY / REAL REGISTRATION HOLD`.
