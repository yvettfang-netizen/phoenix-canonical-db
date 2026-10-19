# Founder Approval — Migration 0018 N-2 / D-2

**Date:** 2026-10-19
**Status:** APPROVED FOR LOCAL ISOLATED DEVELOPMENT AND ACCEPTANCE

## Approval record

The Founder replied **“批准，继续下一步”** to the gate that explicitly listed:

- **N-2:** approve the verified E-R6 fix for formal Migration 0018;
- **D-2:** revoke the context binder capability role's `EXECUTE` privilege on the legacy `auth.bind_context` entry point.

This approval satisfies C-3 and C-4 in `MIGRATION_0018_READINESS_DECISION_R1.md`.

## Authorized scope

1. Create a new 0018 migration without modifying 0001–0017.
2. Promote the already tested E-R6 candidate definitions into 0018.
3. Revoke only the binder capability role's legacy direct bind privilege.
4. Run local PG16/PG17 synthetic acceptance and fresh-cluster restore tests.
5. Create local commits and execution evidence.

## Excluded scope

- No Tencent connection, update, deployment or installation.
- No push, merge or pull request change.
- No real or legacy data.
- No deletion of historical Docker volumes.
- No N-3 case-close lifecycle change.
- No D-1/D-1b ownership or restore-model change.
