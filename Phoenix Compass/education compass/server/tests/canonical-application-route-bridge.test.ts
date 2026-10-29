import assert from 'node:assert/strict'
import test from 'node:test'
import type { QueryResultRow } from 'pg'
import {
  CanonicalApplicationRouteBridge,
  canonicalFamilyReadRoute,
  type CanonicalApplicationGateway
} from '../src/auth/canonical-application-route-bridge'
import type {
  CanonicalApplicationFamilyContextRequest,
  CanonicalContextExecutor
} from '../src/auth/canonical-context-gateway'
import { AppError } from '../src/domain/errors'
import { InMemoryStore } from '../src/store/memory-store'

const USER_ID = `usr_${'1'.repeat(32)}`
const OTHER_USER_ID = `usr_${'2'.repeat(32)}`
const FAMILY_ID = `fam_${'3'.repeat(32)}`
const OTHER_FAMILY_ID = `fam_${'4'.repeat(32)}`
const STUDENT_ID = `stu_${'5'.repeat(32)}`
const OTHER_STUDENT_ID = `stu_${'6'.repeat(32)}`
class Gateway implements CanonicalApplicationGateway {
  readonly requests: CanonicalApplicationFamilyContextRequest[] = []
  error: Error | null = null

  async withApplicationFamilyContext<T>(
    request: CanonicalApplicationFamilyContextRequest,
    work: (client: CanonicalContextExecutor) => Promise<T>
  ): Promise<T> {
    this.requests.push(request)
    if (this.error) throw this.error
    return work({
      query: async <R extends QueryResultRow = QueryResultRow>() => ({ rows: [] as R[], rowCount: 0 })
    })
  }
}

async function fixture(): Promise<{
  store: InMemoryStore
  gateway: Gateway
  bridge: CanonicalApplicationRouteBridge
  issuedSubjects: string[]
}> {
  const store = new InMemoryStore()
  await store.transaction(async (tx) => {
    await tx.insert('users', { id: USER_ID, role: 'family_user', createdAt: '2026-10-28T00:00:00.000Z' })
    await tx.insert('users', { id: OTHER_USER_ID, role: 'family_user', createdAt: '2026-10-28T00:00:00.000Z' })
    await tx.insert('families', {
      id: FAMILY_ID, userId: USER_ID, familyName: null, parentName: null, phone: null,
      location: null, goal: null, createdAt: '2026-10-28T00:00:00.000Z', updatedAt: '2026-10-28T00:00:00.000Z'
    })
    await tx.insert('families', {
      id: OTHER_FAMILY_ID, userId: OTHER_USER_ID, familyName: null, parentName: null, phone: null,
      location: null, goal: null, createdAt: '2026-10-28T00:00:00.000Z', updatedAt: '2026-10-28T00:00:00.000Z'
    })
    await tx.insert('students', {
      id: STUDENT_ID, familyId: FAMILY_ID, name: null, studentVersion: 'v1',
      createdAt: '2026-10-28T00:00:00.000Z', updatedAt: '2026-10-28T00:00:00.000Z'
    })
    await tx.insert('students', {
      id: OTHER_STUDENT_ID, familyId: OTHER_FAMILY_ID, name: null, studentVersion: 'v1',
      createdAt: '2026-10-28T00:00:00.000Z', updatedAt: '2026-10-28T00:00:00.000Z'
    })
  })
  const gateway = new Gateway()
  const issuedSubjects: string[] = []
  const bridge = new CanonicalApplicationRouteBridge(store, {
    issueForApplicationUser: (subject) => {
      issuedSubjects.push(subject)
      return { accessToken: 'server-internal-synthetic-token' }
    }
  }, gateway)
  return { store, gateway, bridge, issuedSubjects }
}

function isCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof AppError && error.code === code
}

test('route policy allowlists only three family-owned GET reads', () => {
  assert.equal(canonicalFamilyReadRoute('GET', '/v1/me/family').operation, 'FAMILY_PROFILE_READ')
  assert.equal(canonicalFamilyReadRoute('GET', '/v1/me/students').operation, 'STUDENT_LIST_READ')
  assert.deepEqual(canonicalFamilyReadRoute('GET', `/v1/me/students/${STUDENT_ID}`), {
    operation: 'STUDENT_PROFILE_READ', familySource: 'OWNED_STUDENT', applicationStudentId: STUDENT_ID
  })
  assert.throws(() => canonicalFamilyReadRoute('PUT', '/v1/me/family'), isCode('CANONICAL_ROUTE_NOT_APPROVED'))
  assert.throws(() => canonicalFamilyReadRoute('GET', '/v1/me/reports'), isCode('CANONICAL_ROUTE_NOT_APPROVED'))
  assert.throws(() => canonicalFamilyReadRoute('GET', '/v1/me/students/not-approved'),
    isCode('CANONICAL_ROUTE_NOT_APPROVED'))
})

test('owned family route derives subject and application family server-side for atomic binder resolution', async () => {
  const context = await fixture()
  const result = await context.bridge.withApprovedFamilyRead({
    method: 'GET', pathname: '/v1/me/family', user: { id: USER_ID, role: 'family_user' }
  }, async (_client, operation) => operation)
  assert.equal(result, 'FAMILY_PROFILE_READ')
  assert.deepEqual(context.issuedSubjects, [USER_ID])
  assert.deepEqual(context.gateway.requests, [{
    accessToken: 'server-internal-synthetic-token',
    applicationFamilyId: FAMILY_ID
  }])
})

test('owned student route derives family through the stored student relationship', async () => {
  const context = await fixture()
  const operation = await context.bridge.withApprovedFamilyRead({
    method: 'GET', pathname: `/v1/me/students/${STUDENT_ID}`,
    user: { id: USER_ID, role: 'family_user' }
  }, async (_client, value) => value)
  assert.equal(operation, 'STUDENT_PROFILE_READ')
  assert.equal(context.gateway.requests[0]?.applicationFamilyId, FAMILY_ID)
})

test('cross-family student is rejected before broker or atomic gateway', async () => {
  const context = await fixture()
  await assert.rejects(context.bridge.withApprovedFamilyRead({
    method: 'GET', pathname: `/v1/me/students/${OTHER_STUDENT_ID}`,
    user: { id: USER_ID, role: 'family_user' }
  }, async () => undefined), isCode('CANONICAL_APPLICATION_FAMILY_FORBIDDEN'))
  assert.equal(context.issuedSubjects.length, 0)
  assert.equal(context.gateway.requests.length, 0)
})

test('admin or malformed application user cannot enter the family bridge', async () => {
  for (const user of [
    { id: USER_ID, role: 'admin' as const },
    { id: 'openid-sensitive-value', role: 'family_user' as const }
  ]) {
    const context = await fixture()
    await assert.rejects(context.bridge.withApprovedFamilyRead({
      method: 'GET', pathname: '/v1/me/family', user
    }, async () => undefined), isCode('CANONICAL_FAMILY_ACTOR_REQUIRED'))
    assert.equal(context.gateway.requests.length, 0)
  }
})

test('atomic gateway mapping denial propagates without exposing a client-supplied canonical identifier', async () => {
  const context = await fixture()
  context.gateway.error = new AppError(403, 'CANONICAL_APPLICATION_MAPPING_REQUIRED', 'synthetic denial')
  await assert.rejects(context.bridge.withApprovedFamilyRead({
    method: 'GET', pathname: '/v1/me/family', user: { id: USER_ID, role: 'family_user' }
  }, async () => undefined), isCode('CANONICAL_APPLICATION_MAPPING_REQUIRED'))
  assert.deepEqual(context.gateway.requests, [{
    accessToken: 'server-internal-synthetic-token',
    applicationFamilyId: FAMILY_ID
  }])
})
