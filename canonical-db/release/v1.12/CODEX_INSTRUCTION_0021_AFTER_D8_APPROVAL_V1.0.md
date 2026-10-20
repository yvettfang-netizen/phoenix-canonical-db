# Codex Instruction — Migration 0021 after D-8 Approval V1.0

**Status:** READY BUT BLOCKED  
**Start condition:** A completed Founder Decision D-8 and exact approved SHA-256 for the Operations entitlement contract.  
**Current gate:** HOLD

## 1. Boundaries

1. Work only in `codex/canonical-postgresql-phase1`.
2. Do not modify Migration 0001–0020.
3. Create exactly one forward migration beginning with `0021_` for the approved scope.
4. Use synthetic identifiers and synthetic people/families only.
5. Do not read Operations data, credentials or assets.
6. Do not connect to Tencent, deploy, push, merge or change a PR.
7. If the signed decision leaves an owner, source system, interface identity, identifier rule or revocation target blank, stop and report HOLD.

## 2. Required implementation

Subject to the exact signed contract:

1. Create schema `operations_ref` owned under the established schema-owner model.
2. Create an entitlement reference table with source-qualified identity, subject, family, product kind, course scope, validity, lifecycle and source-event metadata.
3. Enforce subject/family integrity and product/course consistency.
4. Enable and force RLS. Runtime roles receive no direct DML.
5. Add controlled register, revoke and boolean check functions with fixed `search_path`, PUBLIC revoked and minimal grants.
6. Record allowed and denied operations through the established audit mechanism.
7. Keep raw external reference identifiers hidden from family, advisor and partner roles in the initial implementation unless the signed decision says otherwise.
8. Update initialization, restore and expected-count assertions for 21 migrations.

## 3. Required regression tests

Run on PG16 and PG17 with separate LOGIN accounts and one-time context tickets:

- valid Education service entitlement allows only its approved check;
- missing, future, expired and revoked entitlements deny;
- course entitlement requires the matching course and does not allow ASKWISE;
- ASKWISE entitlement does not allow course or Education service;
- entitlement creation never creates Consent;
- cross-family subject/reference registration is denied;
- direct table DML by app, binder, advisor, partner and family roles is denied;
- duplicate source event is idempotent;
- conflicting duplicate and out-of-order event are denied;
- revoke is visible on the next authorization check;
- revoked or expired reference cannot be reactivated;
- PUBLIC cannot execute helper or trigger functions;
- prior F10, defect and contract regressions remain green.

## 4. Recovery acceptance

1. Run the full F10 path on fresh PG16 and PG17 clusters and confirm `APPLIED 0021`.
2. Produce a backup using the least-privilege backup role.
3. Verify manifest integrity before restore.
4. Restore into fresh PG16 and PG17 clusters and rerun the complete acceptance suite.
5. Confirm the restored ledger has 21 rows and the exact expected table/policy counts calculated from the implemented migration.
6. Leave no synthetic business rows or temporary schemas after testing.

## 5. Deliverables

- Migration 0021 and SHA-256;
- permanent regression tests;
- raw PG16 and PG17 F10 and restore outputs;
- updated inventory, access matrix and risk register;
- `FIX_EXECUTION_REPORT_V1.13.md` mapping each contract rule to SQL and evidence;
- local commit hash.

