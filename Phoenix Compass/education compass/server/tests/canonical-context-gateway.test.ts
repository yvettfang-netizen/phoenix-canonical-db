import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { isAbsolute, join, resolve } from 'node:path'
import test from 'node:test'
import type { PoolConfig, QueryResultRow } from 'pg'
import {
  CanonicalContextGateway,
  type CanonicalConnectionPool,
  type CanonicalGatewayAuditEvent,
  type CanonicalGatewayAuditSink,
  type CanonicalPoolClient,
  type CanonicalTokenVerifier
} from '../src/auth/canonical-context-gateway'
import {
  CANONICAL_APP_CREDENTIAL_REF,
  CANONICAL_BINDER_CREDENTIAL_REF
} from '../src/auth/canonical-oidc-broker'
import {
  createCanonicalContextRuntime,
  loadCanonicalContextRuntimeConfig,
  ProtectedJsonLineAuditSink
} from '../src/auth/canonical-context-runtime'
import type { VerifiedOidcIdentity } from '../src/auth/oidc-jwt-verifier'
import { AppError } from '../src/domain/errors'

const ISSUER = 'https://api.phoenix.synthetic.test/canonical-identity'
const PRINCIPAL_ID = '01940000-0000-7000-8000-000000000201'
const ACTOR_ID = '01940000-0000-7000-8000-000000000101'
const FAMILY_ID = '01940000-0000-7000-8000-000000000001'
const REQUEST_NONCE = '00000000-0000-4000-8000-000000000001'
const TICKET_ID = '00000000-0000-4000-8000-000000000101'
const NOW_MS = 1_800_000_000_000

type QueryResult = { rows: QueryResultRow[]; rowCount: number | null }
type QueryHandler = (text: string, values?: readonly unknown[]) => Promise<QueryResult> | QueryResult

class FakeClient implements CanonicalPoolClient {
  readonly calls: Array<{ text: string; values?: readonly unknown[] }> = []
  readonly releases: boolean[] = []

  constructor(private readonly handler: QueryHandler) {}

  async query<R extends QueryResultRow = QueryResultRow>(text: string, values?: readonly unknown[]): Promise<{
    rows: R[]
    rowCount: number | null
  }> {
    this.calls.push(values === undefined ? { text } : { text, values })
    return await this.handler(text, values) as { rows: R[]; rowCount: number | null }
  }

  release(destroy = false): void {
    this.releases.push(destroy)
  }
}

class FakePool implements CanonicalConnectionPool {
  connectCount = 0
  endCount = 0

  constructor(readonly client: FakeClient) {}

  async connect(): Promise<CanonicalPoolClient> {
    this.connectCount += 1
    return this.client
  }

  async end(): Promise<void> {
    this.endCount += 1
  }
}

class MemoryAudit implements CanonicalGatewayAuditSink {
  readonly events: CanonicalGatewayAuditEvent[] = []
  closed = false
  fail = false

  async record(event: CanonicalGatewayAuditEvent): Promise<void> {
    if (this.fail) throw new Error('synthetic audit failure')
    this.events.push(event)
  }

  async close(): Promise<void> {
    this.closed = true
  }
}

function identity(subject = 'usr_synthetic_001'): VerifiedOidcIdentity {
  return {
    issuer: ISSUER,
    subject,
    audience: 'phoenix-canonical-postgresql',
    expiresAt: Math.floor(NOW_MS / 1000) + 300,
    notBefore: Math.floor(NOW_MS / 1000),
    keyId: 'phoenix-canonical-es256-v1',
    algorithm: 'ES256'
  }
}

function verifier(result = identity()): CanonicalTokenVerifier {
  return { verify: async () => result }
}

function binderClient(principalId: string | null = PRINCIPAL_ID): FakeClient {
  return new FakeClient((sql) => {
    if (sql.includes('resolve_external_identity')) return { rows: [{ principal_id: principalId }], rowCount: 1 }
    if (sql.includes('issue_context_ticket')) return { rows: [{ ticket_id: TICKET_ID }], rowCount: 1 }
    throw new Error(`unexpected binder query: ${sql}`)
  })
}

function appClient(options: { clearFails?: boolean; discardFails?: boolean } = {}): FakeClient {
  return new FakeClient((sql) => {
    if (sql.includes('auth.clear_context') && options.clearFails) throw new Error('synthetic clear failure')
    if (sql === 'DISCARD ALL' && options.discardFails) throw new Error('synthetic discard failure')
    if (sql.includes('auth.current_principal_id')) return { rows: [{ principal_id: null }], rowCount: 1 }
    if (sql.includes('SELECT 42')) return { rows: [{ answer: 42 }], rowCount: 1 }
    return { rows: [], rowCount: 0 }
  })
}

function request(): { accessToken: string; actorPersonId: string; familyId: string; channel: 'FAMILY' } {
  return {
    accessToken: 'synthetic-signed-jwt',
    actorPersonId: ACTOR_ID,
    familyId: FAMILY_ID,
    channel: 'FAMILY'
  }
}

function gateway(
  binder: FakePool,
  app: FakePool,
  audit: CanonicalGatewayAuditSink,
  tokenVerifier: CanonicalTokenVerifier = verifier()
): CanonicalContextGateway {
  return new CanonicalContextGateway(tokenVerifier, binder, app, audit, {
    ticketTtlSeconds: 45,
    clockMs: () => NOW_MS,
    nonceFactory: () => REQUEST_NONCE
  })
}

function isCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof AppError && error.code === code
}

test('configuration stays disabled by default and fails closed on incomplete gateway facts', () => {
  assert.equal(loadCanonicalContextRuntimeConfig({}), null)
  assert.throws(() => loadCanonicalContextRuntimeConfig({
    CANONICAL_CONTEXT_GATEWAY_ENABLED: 'true'
  }), isCode('CANONICAL_CONTEXT_CONFIG_INVALID'))
  assert.throws(() => loadCanonicalContextRuntimeConfig({
    CANONICAL_CONTEXT_GATEWAY_ENABLED: 'true',
    CANONICAL_OIDC_BROKER_ENABLED: 'true',
    CANONICAL_OIDC_ENABLED: 'true',
    CANONICAL_POSTGRES_APP_CREDENTIAL_REF: CANONICAL_APP_CREDENTIAL_REF,
    CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF: CANONICAL_BINDER_CREDENTIAL_REF,
    CANONICAL_GATEWAY_AUDIT_FILE: resolve('synthetic-audit.jsonl'),
    CANONICAL_CONTEXT_TICKET_TTL_SECONDS: '46'
  }), isCode('CANONICAL_CONTEXT_CONFIG_INVALID'))
  const loaded = loadCanonicalContextRuntimeConfig({
    CANONICAL_CONTEXT_GATEWAY_ENABLED: 'true',
    CANONICAL_OIDC_BROKER_ENABLED: 'true',
    CANONICAL_OIDC_ENABLED: 'true',
    CANONICAL_POSTGRES_APP_CREDENTIAL_REF: CANONICAL_APP_CREDENTIAL_REF,
    CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF: CANONICAL_BINDER_CREDENTIAL_REF,
    CANONICAL_GATEWAY_AUDIT_FILE: resolve('synthetic-audit.jsonl'),
    CANONICAL_CONTEXT_TICKET_TTL_SECONDS: '45'
  })
  assert.ok(loaded)
  assert.equal(loaded.ticketTtlSeconds, 45)
  assert.equal(isAbsolute(loaded.auditFile), true)
  assert.notEqual(loaded.appCredentialRef, loaded.binderCredentialRef)
})

test('separate binder and app pools resolve usr subject, exchange once, clear and discard before release', async () => {
  const binder = new FakePool(binderClient())
  const app = new FakePool(appClient())
  const audit = new MemoryAudit()
  const result = await gateway(binder, app, audit).withContext(request(), async (client) => {
    const queried = await client.query<{ answer: number }>('SELECT 42 AS answer')
    return queried.rows[0]?.answer
  })

  assert.equal(result, 42)
  assert.equal(binder.connectCount, 1)
  assert.equal(app.connectCount, 1)
  assert.deepEqual(binder.client.releases, [false])
  assert.deepEqual(app.client.releases, [false])
  assert.deepEqual(app.client.calls.map((call) => call.text), [
    'BEGIN',
    'SELECT auth.redeem_context_ticket($1::uuid,$2::uuid)',
    'SELECT 42 AS answer',
    'SELECT auth.clear_context()',
    'SELECT auth.current_principal_id()::text AS principal_id',
    'COMMIT',
    'DISCARD ALL'
  ])
  const issue = binder.client.calls.find((call) => call.text.includes('issue_context_ticket'))
  assert.deepEqual(issue?.values, [PRINCIPAL_ID, ACTOR_ID, FAMILY_ID, 'FAMILY', 45, REQUEST_NONCE])
  assert.deepEqual(audit.events, [{
    timestamp: new Date(NOW_MS).toISOString(),
    requestNonce: REQUEST_NONCE,
    issuer: ISSUER,
    subjectId: 'usr_synthetic_001',
    channel: 'FAMILY',
    decision: 'ALLOW',
    reasonCode: 'CONTEXT_TRANSACTION_READY'
  }])
  assert.equal(JSON.stringify(audit.events).includes('synthetic-signed-jwt'), false)
  assert.equal(JSON.stringify(audit.events).includes(FAMILY_ID), false)
})

test('unknown subject mapping denies before app pool and never auto-provisions an identity', async () => {
  const binder = new FakePool(binderClient(null))
  const app = new FakePool(appClient())
  const audit = new MemoryAudit()
  await assert.rejects(gateway(binder, app, audit).withContext(request(), async () => undefined),
    isCode('CANONICAL_IDENTITY_UNMAPPED'))
  assert.equal(app.connectCount, 0)
  assert.equal(binder.client.calls.some((call) => /INSERT|UPDATE/i.test(call.text)), false)
  assert.equal(binder.client.calls.some((call) => call.text.includes('issue_context_ticket')), false)
  assert.equal(audit.events[0]?.decision, 'DENY')
  assert.equal(audit.events[0]?.reasonCode, 'CANONICAL_IDENTITY_UNMAPPED')
})

test('non-usr verifier subject is rejected and redacted from denial audit', async () => {
  const binder = new FakePool(binderClient())
  const app = new FakePool(appClient())
  const audit = new MemoryAudit()
  await assert.rejects(
    gateway(binder, app, audit, verifier(identity('openid-sensitive-value')))
      .withContext(request(), async () => undefined),
    isCode('CANONICAL_SUBJECT_INVALID')
  )
  assert.equal(binder.connectCount, 0)
  assert.equal(app.connectCount, 0)
  assert.equal(audit.events[0]?.subjectId, 'UNVERIFIED')
  assert.equal(JSON.stringify(audit.events).includes('openid-sensitive-value'), false)
})

test('business callback cannot control transactions or roles and uncertain app connection is destroyed', async () => {
  const binder = new FakePool(binderClient())
  const app = new FakePool(appClient())
  const audit = new MemoryAudit()
  await assert.rejects(gateway(binder, app, audit).withContext(request(), async (client) => {
    await client.query('SET ROLE phoenix_bootstrap')
  }), isCode('CANONICAL_CONTEXT_TRANSACTION_CONTROL_FORBIDDEN'))
  assert.ok(app.client.calls.some((call) => call.text === 'ROLLBACK'))
  assert.deepEqual(app.client.releases, [true])
})

test('clear or durable audit failure rolls back and destroys the app connection', async () => {
  for (const failure of ['clear', 'audit'] as const) {
    const binder = new FakePool(binderClient())
    const app = new FakePool(appClient({ clearFails: failure === 'clear' }))
    const audit = new MemoryAudit()
    audit.fail = failure === 'audit'
    await assert.rejects(gateway(binder, app, audit).withContext(request(), async () => 'not-committed'))
    assert.ok(app.client.calls.some((call) => call.text === 'ROLLBACK'))
    assert.equal(app.client.calls.some((call) => call.text === 'COMMIT'), false)
    assert.deepEqual(app.client.releases, [true])
  }
})

test('DISCARD failure after a committed, cleared transaction destroys instead of reusing the connection', async () => {
  const binder = new FakePool(binderClient())
  const app = new FakePool(appClient({ discardFails: true }))
  const audit = new MemoryAudit()
  const result = await gateway(binder, app, audit).withContext(request(), async () => 'committed')
  assert.equal(result, 'committed')
  assert.ok(app.client.calls.some((call) => call.text === 'COMMIT'))
  assert.deepEqual(app.client.releases, [true])
})

test('protected JSONL audit writes an exact minimal schema and 0600 file without extra token fields', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'phoenix-canonical-audit-'))
  const path = join(directory, 'audit.jsonl')
  try {
    const sink = await ProtectedJsonLineAuditSink.open(path)
    await sink.record({
      timestamp: new Date(NOW_MS).toISOString(),
      requestNonce: REQUEST_NONCE,
      issuer: ISSUER,
      subjectId: 'usr_synthetic_001',
      channel: 'FAMILY',
      decision: 'ALLOW',
      reasonCode: 'SYNTHETIC_PASS',
      accessToken: 'must-not-be-written'
    } as CanonicalGatewayAuditEvent & { accessToken: string })
    await sink.close()
    const raw = await readFile(path, 'utf8')
    const parsed = JSON.parse(raw.trim()) as Record<string, unknown>
    assert.deepEqual(Object.keys(parsed).sort(), [
      'channel', 'decision', 'issuer', 'reasonCode', 'requestNonce', 'subjectId', 'timestamp'
    ])
    assert.equal(raw.includes('must-not-be-written'), false)
    if (process.platform !== 'win32') assert.equal((await stat(path)).mode & 0o077, 0)
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
})

test('runtime builds distinct least-privilege pools from separate protected pgpass records', async () => {
  const config = loadCanonicalContextRuntimeConfig({
    CANONICAL_CONTEXT_GATEWAY_ENABLED: 'true',
    CANONICAL_OIDC_BROKER_ENABLED: 'true',
    CANONICAL_OIDC_ENABLED: 'true',
    CANONICAL_POSTGRES_APP_CREDENTIAL_REF: CANONICAL_APP_CREDENTIAL_REF,
    CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF: CANONICAL_BINDER_CREDENTIAL_REF,
    CANONICAL_GATEWAY_AUDIT_FILE: resolve('synthetic-audit.jsonl')
  })
  assert.ok(config)
  const poolConfigs: PoolConfig[] = []
  const pools: FakePool[] = []
  const audit = new MemoryAudit()
  const runtime = await createCanonicalContextRuntime(config, verifier(), {
    credentialReader: async (_path, label) => label.includes('app')
      ? `127.0.0.1:5432:phoenix_canonical_dev:phoenix_canonical_app_runtime:${'a'.repeat(64)}`
      : `127.0.0.1:5432:phoenix_canonical_dev:phoenix_canonical_binder_runtime:${'b'.repeat(64)}`,
    poolFactory: (options) => {
      poolConfigs.push(options)
      const client = new FakeClient(() => ({ rows: [{ current_user: options.user }], rowCount: 1 }))
      const pool = new FakePool(client)
      pools.push(pool)
      return pool
    },
    auditFactory: async () => audit
  })
  assert.deepEqual(poolConfigs.map((entry) => entry.user), [
    'phoenix_canonical_app_runtime',
    'phoenix_canonical_binder_runtime'
  ])
  assert.notEqual(poolConfigs[0]?.password, poolConfigs[1]?.password)
  assert.equal(poolConfigs[0]?.host, '127.0.0.1')
  assert.equal(poolConfigs[1]?.host, '127.0.0.1')
  await runtime.close()
  assert.deepEqual(pools.map((pool) => pool.endCount), [1, 1])
  assert.equal(audit.closed, true)
})

test('runtime refuses shared app and binder password before constructing pools', async () => {
  const config = loadCanonicalContextRuntimeConfig({
    CANONICAL_CONTEXT_GATEWAY_ENABLED: 'true',
    CANONICAL_OIDC_BROKER_ENABLED: 'true',
    CANONICAL_OIDC_ENABLED: 'true',
    CANONICAL_POSTGRES_APP_CREDENTIAL_REF: CANONICAL_APP_CREDENTIAL_REF,
    CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF: CANONICAL_BINDER_CREDENTIAL_REF,
    CANONICAL_GATEWAY_AUDIT_FILE: resolve('synthetic-audit.jsonl')
  })
  assert.ok(config)
  let poolCreations = 0
  await assert.rejects(createCanonicalContextRuntime(config, verifier(), {
    credentialReader: async (_path, label) => {
      const role = label.includes('app') ? 'phoenix_canonical_app_runtime' : 'phoenix_canonical_binder_runtime'
      return `127.0.0.1:5432:phoenix_canonical_dev:${role}:${'c'.repeat(64)}`
    },
    poolFactory: () => {
      poolCreations += 1
      return new FakePool(appClient())
    },
    auditFactory: async () => new MemoryAudit()
  }), isCode('CANONICAL_CONTEXT_CONFIG_INVALID'))
  assert.equal(poolCreations, 0)
})
