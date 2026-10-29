import assert from 'node:assert/strict'
import { generateKeyPairSync, randomUUID } from 'node:crypto'
import { AddressInfo } from 'node:net'
import test from 'node:test'
import { Pool } from 'pg'
import { MockWechatAuthProvider } from '../src/auth/wechat-auth-provider'
import { CanonicalApplicationRouteBridge } from '../src/auth/canonical-application-route-bridge'
import {
  CANONICAL_APP_CREDENTIAL_REF,
  CANONICAL_BINDER_CREDENTIAL_REF,
  CANONICAL_OIDC_ALGORITHM,
  CANONICAL_OIDC_AUDIENCE,
  CANONICAL_OIDC_SIGNING_KEY_FILE,
  CANONICAL_OIDC_SIGNING_KEY_REF,
  CanonicalOidcBroker,
  type CanonicalOidcBrokerConfig
} from '../src/auth/canonical-oidc-broker'
import {
  CanonicalContextGateway,
  type CanonicalGatewayAuditEvent,
  type CanonicalGatewayAuditSink
} from '../src/auth/canonical-context-gateway'
import { OidcJwtVerifier } from '../src/auth/oidc-jwt-verifier'
import { validateSourceCatalog } from '../src/domain/source-catalog'
import { createAppServer } from '../src/http/app'
import { MockPaymentProvider } from '../src/payments/mock-payment-provider'
import { AssessmentService } from '../src/services/assessment-service'
import { AuthService } from '../src/services/auth-service'
import { OrderService, seedProducts } from '../src/services/order-service'
import { ProfileService } from '../src/services/profile-service'
import { ReportService } from '../src/services/report-service'
import { InMemoryStore } from '../src/store/memory-store'

const USER_ID = `usr_${'a'.repeat(32)}`
const FAMILY_ID = `fam_${'b'.repeat(32)}`
const STUDENT_ID = `stu_${'c'.repeat(32)}`
const OTHER_FAMILY_ID = `fam_${'d'.repeat(32)}`
const OTHER_STUDENT_ID = `stu_${'e'.repeat(32)}`
const ISSUER = 'https://api.phoenix.synthetic.test/canonical-identity'
const JWKS_URI = 'https://api.phoenix.synthetic.test/.well-known/phoenix-canonical-jwks.json'
const SESSION_SECRET = 'v1.26-synthetic-session-secret-at-least-32-bytes'

function required(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`${name} is required by the isolated E2E runner`)
  return value
}

class AuditSink implements CanonicalGatewayAuditSink {
  readonly events: CanonicalGatewayAuditEvent[] = []
  async record(event: CanonicalGatewayAuditEvent): Promise<void> { this.events.push(event) }
}

async function jsonRequest(base: string, path: string, accessToken: string): Promise<{ status: number; body: any }> {
  const response = await fetch(`${base}${path}`, {
    headers: { Authorization: `Bearer ${accessToken}` }
  })
  return { status: response.status, body: await response.json() }
}

test('synthetic HTTP to broker to split pools to RLS preserves exact application DTOs', async () => {
  const port = Number(required('CANONICAL_E2E_PORT'))
  assert.ok(Number.isInteger(port) && port > 0 && port <= 65535)
  const common = {
    host: '127.0.0.1', port, database: 'phoenix_canonical_dev', max: 2,
    connectionTimeoutMillis: 5_000, idleTimeoutMillis: 1_000
  }
  const appPool = new Pool({
    ...common, user: 'phoenix_canonical_app_runtime', password: required('CANONICAL_E2E_APP_PASSWORD')
  })
  const binderPool = new Pool({
    ...common, user: 'phoenix_canonical_binder_runtime', password: required('CANONICAL_E2E_BINDER_PASSWORD')
  })
  assert.notEqual(appPool, binderPool)

  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  const brokerConfig: CanonicalOidcBrokerConfig = {
    issuer: ISSUER,
    audience: CANONICAL_OIDC_AUDIENCE,
    jwksUri: JWKS_URI,
    algorithm: CANONICAL_OIDC_ALGORITHM,
    tokenTtlSeconds: 300,
    keyId: 'phoenix-canonical-es256-v126',
    signingKeyFile: CANONICAL_OIDC_SIGNING_KEY_FILE,
    signingKeyRef: CANONICAL_OIDC_SIGNING_KEY_REF,
    appCredentialRef: CANONICAL_APP_CREDENTIAL_REF,
    binderCredentialRef: CANONICAL_BINDER_CREDENTIAL_REF
  }
  const broker = new CanonicalOidcBroker(brokerConfig, privateKey)
  const verifier = new OidcJwtVerifier({
    issuer: ISSUER,
    audience: CANONICAL_OIDC_AUDIENCE,
    jwksUri: JWKS_URI,
    allowedAlgorithms: ['ES256'],
    tokenMaxTtlSeconds: 300,
    clockSkewSeconds: 0,
    jwksCacheSeconds: 60,
    unknownKidRefreshRateLimitSeconds: 60
  }, async () => new Response(JSON.stringify(broker.jwks()), {
    status: 200,
    headers: { 'content-type': 'application/jwk-set+json' }
  }))
  const audit = new AuditSink()
  const gateway = new CanonicalContextGateway(
    verifier,
    binderPool,
    appPool,
    audit,
    { ticketTtlSeconds: 45, nonceFactory: randomUUID }
  )

  const store = new InMemoryStore()
  await seedProducts(store, '2026-10-29T00:00:00.000Z')
  const ids = (prefix: string): string => ({
    usr: USER_ID, wxi: `wxi_${'1'.repeat(32)}`, ses: `ses_${'2'.repeat(32)}`
  }[prefix] ?? `${prefix}_${'9'.repeat(32)}`)
  const auth = new AuthService(
    store,
    new MockWechatAuthProvider(),
    SESSION_SECRET,
    () => new Date('2026-10-29T00:00:00.000Z'),
    ids
  )
  const login = await auth.createWechatSession('synthetic-v126-user')
  assert.equal(login.user.id, USER_ID)
  await store.transaction(async (tx) => {
    await tx.insert('families', {
      id: FAMILY_ID, userId: USER_ID, familyName: 'Synthetic V1.26 Family', parentName: 'Synthetic Parent',
      phone: null, location: 'Synthetic Zone', goal: 'Synthetic Goal', profileStatus: 'PROVISIONAL',
      profileSchemaVersion: 'family_profile_v0.5.0', createdAt: '2026-10-29T00:00:00.000Z',
      updatedAt: '2026-10-29T00:00:00.000Z'
    })
    await tx.insert('students', {
      id: STUDENT_ID, familyId: FAMILY_ID, name: 'Synthetic Student', age: 16, gender: null,
      school: null, educationSystem: 'DSE', grade: 'S5', interest: 'Synthetic Interest', goal: null,
      studentVersion: 'v1', profileStatus: 'COMPLETE_FOR_LEVEL_2',
      profileSchemaVersion: 'student_profile_v0.5.0', gradeStage: 'S5',
      createdAt: '2026-10-29T00:00:00.000Z', updatedAt: '2026-10-29T00:00:00.000Z'
    })
    await tx.insert('families', {
      id: OTHER_FAMILY_ID, userId: `usr_${'f'.repeat(32)}`, familyName: null, parentName: null,
      phone: null, location: null, goal: null, createdAt: '2026-10-29T00:00:00.000Z',
      updatedAt: '2026-10-29T00:00:00.000Z'
    })
    await tx.insert('students', {
      id: OTHER_STUDENT_ID, familyId: OTHER_FAMILY_ID, name: null, studentVersion: 'v1',
      createdAt: '2026-10-29T00:00:00.000Z', updatedAt: '2026-10-29T00:00:00.000Z'
    })
  })
  const catalog = validateSourceCatalog({
    version: 'SYNTHETIC-V126', dataAsOf: '2026-10-29', reviewedAt: '2026-10-29T00:00:00Z',
    reviewedBy: 'Synthetic test',
    entries: [{ sourceId: 'SYNTHETIC-1', title: 'Synthetic source', applicableYear: '2026',
      verifiedAt: '2026-10-29T00:00:00Z' }]
  })
  const profiles = new ProfileService(store)
  const server = createAppServer({
    auth,
    profiles,
    assessments: new AssessmentService(store, catalog),
    orders: new OrderService(store, new MockPaymentProvider(SESSION_SECRET), catalog, true),
    reports: new ReportService(store),
    canonicalOidcBroker: broker,
    canonicalApplicationRouteBridge: new CanonicalApplicationRouteBridge(store, broker, gateway)
  })
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  try {
    const family = await jsonRequest(base, '/v1/me/family', login.accessToken)
    assert.equal(family.status, 200)
    assert.deepEqual(Object.keys(family.body.family), [
      'id', 'userId', 'familyName', 'parentName', 'phone', 'location', 'goal',
      'profileStatus', 'profileSchemaVersion', 'createdAt', 'updatedAt'
    ])
    assert.equal(family.body.family.id, FAMILY_ID)
    assert.equal('family_id' in family.body.family, false)

    const students = await jsonRequest(base, '/v1/me/students', login.accessToken)
    assert.equal(students.status, 200)
    assert.equal(students.body.students.length, 1)
    assert.equal(students.body.students[0].id, STUDENT_ID)
    assert.equal('person_id' in students.body.students[0], false)

    const student = await jsonRequest(base, `/v1/me/students/${STUDENT_ID}`, login.accessToken)
    assert.equal(student.status, 200)
    assert.deepEqual(student.body.student, students.body.students[0])

    const crossFamily = await jsonRequest(base, `/v1/me/students/${OTHER_STUDENT_ID}`, login.accessToken)
    assert.equal(crossFamily.status, 403)
    assert.equal(crossFamily.body.error.code, 'CANONICAL_APPLICATION_FAMILY_FORBIDDEN')

    assert.equal(audit.events.filter((event) => event.decision === 'ALLOW').length, 3)
    assert.equal(audit.events.filter((event) => event.reasonCode === 'CONTEXT_TRANSACTION_READY').length, 3)
    const unbound = await appPool.query('SELECT count(*)::integer AS count FROM core.families')
    assert.equal(unbound.rows[0]?.count, 0)
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()))
    await Promise.all([appPool.end(), binderPool.end()])
  }
})
