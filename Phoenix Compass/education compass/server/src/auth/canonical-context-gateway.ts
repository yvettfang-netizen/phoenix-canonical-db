import { randomUUID } from 'node:crypto'
import type { QueryResultRow } from 'pg'
import { AppError, invariant } from '../domain/errors'
import type { VerifiedOidcIdentity } from './oidc-jwt-verifier'

export type CanonicalContextChannel = 'FAMILY' | 'ADVISOR' | 'PARTNER' | 'INTERNAL'
export type CanonicalAuditDecision = 'ALLOW' | 'DENY'

export interface CanonicalContextRequest {
  accessToken: string
  actorPersonId: string | null
  familyId: string | null
  channel: CanonicalContextChannel
}

export interface CanonicalGatewayAuditEvent {
  timestamp: string
  requestNonce: string
  issuer: string
  subjectId: string
  channel: CanonicalContextChannel
  decision: CanonicalAuditDecision
  reasonCode: string
}

export interface CanonicalGatewayAuditSink {
  record(event: CanonicalGatewayAuditEvent): Promise<void>
}

export interface CanonicalTokenVerifier {
  verify(token: string): Promise<VerifiedOidcIdentity>
}

export interface CanonicalPoolClient {
  query<R extends QueryResultRow = QueryResultRow>(text: string, values?: readonly unknown[]): Promise<{
    rows: R[]
    rowCount: number | null
  }>
  release(destroy?: boolean): void
}

export interface CanonicalConnectionPool {
  connect(): Promise<CanonicalPoolClient>
  end(): Promise<void>
}

export interface CanonicalContextExecutor {
  query<R extends QueryResultRow = QueryResultRow>(text: string, values?: readonly unknown[]): Promise<{
    rows: R[]
    rowCount: number | null
  }>
}

export interface CanonicalContextGatewayOptions {
  ticketTtlSeconds: number
  clockMs?: () => number
  nonceFactory?: () => string
}

const UUID_V7 = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
const CHANNELS = new Set<CanonicalContextChannel>(['FAMILY', 'ADVISOR', 'PARTNER', 'INTERNAL'])
const FORBIDDEN_TRANSACTION_SQL = /(?:^|;)\s*(?:BEGIN|START\s+TRANSACTION|COMMIT|ROLLBACK|SAVEPOINT|RELEASE\s+SAVEPOINT|SET\s+ROLE|RESET\s+ROLE|DISCARD)\b/i

function requestError(message: string): never {
  throw new AppError(400, 'CANONICAL_CONTEXT_REQUEST_INVALID', message)
}

function validateOptionalUuidV7(value: string | null, label: string): void {
  if (value !== null && !UUID_V7.test(value)) requestError(`${label} 必须是 UUIDv7 或 null`)
}

function failureCode(error: unknown): string {
  return error instanceof AppError ? error.code : 'CANONICAL_CONTEXT_UNAVAILABLE'
}

function safeDatabaseError(): AppError {
  return new AppError(503, 'CANONICAL_CONTEXT_UNAVAILABLE', 'Canonical 上下文暂不可用')
}

export class CanonicalContextGateway {
  private readonly ticketTtlSeconds: number
  private readonly clockMs: () => number
  private readonly nonceFactory: () => string

  constructor(
    private readonly verifier: CanonicalTokenVerifier,
    private readonly binderPool: CanonicalConnectionPool,
    private readonly appPool: CanonicalConnectionPool,
    private readonly audit: CanonicalGatewayAuditSink,
    options: CanonicalContextGatewayOptions
  ) {
    invariant(Number.isInteger(options.ticketTtlSeconds) && options.ticketTtlSeconds > 0 && options.ticketTtlSeconds <= 60,
      500, 'CANONICAL_CONTEXT_CONFIG_INVALID', 'Canonical ticket TTL 必须为 1–60 秒')
    invariant(binderPool !== appPool, 500, 'CANONICAL_CONTEXT_CONFIG_INVALID', 'Binder 与 app 必须使用不同连接池')
    this.ticketTtlSeconds = options.ticketTtlSeconds
    this.clockMs = options.clockMs ?? (() => Date.now())
    this.nonceFactory = options.nonceFactory ?? randomUUID
  }

  async withContext<T>(
    request: CanonicalContextRequest,
    work: (client: CanonicalContextExecutor) => Promise<T>
  ): Promise<T> {
    const requestNonce = this.nonceFactory()
    if (!UUID_V4.test(requestNonce)) {
      throw new AppError(500, 'CANONICAL_CONTEXT_CONFIG_INVALID', 'Canonical request nonce 必须是 UUIDv4')
    }
    if (!CHANNELS.has(request.channel)) requestError('Canonical channel 无效')
    validateOptionalUuidV7(request.actorPersonId, 'actorPersonId')
    validateOptionalUuidV7(request.familyId, 'familyId')

    let identity: VerifiedOidcIdentity | null = null
    try {
      identity = await this.verifier.verify(request.accessToken)
      invariant(/^usr_[A-Za-z0-9_-]{1,128}$/.test(identity.subject), 401,
        'CANONICAL_SUBJECT_INVALID', 'Canonical subject 必须是受控应用用户 ID')
      const principalId = await this.resolveAndIssueTicket(identity, request, requestNonce)
      return await this.runWithTicket(principalId.principalId, principalId.ticketId, identity, request, requestNonce, work)
    } catch (error) {
      await this.recordDeny(identity, request.channel, requestNonce, failureCode(error))
      if (error instanceof AppError) throw error
      throw safeDatabaseError()
    }
  }

  private async resolveAndIssueTicket(
    identity: VerifiedOidcIdentity,
    request: CanonicalContextRequest,
    requestNonce: string
  ): Promise<{ principalId: string; ticketId: string }> {
    const client = await this.binderPool.connect().catch(() => { throw safeDatabaseError() })
    let destroy = false
    try {
      const resolved = await client.query<{ principal_id: string | null }>(
        'SELECT auth.resolve_external_identity($1::text,$2::text)::text AS principal_id',
        [identity.issuer, identity.subject]
      )
      const principalId = resolved.rows[0]?.principal_id ?? null
      invariant(principalId && UUID_V7.test(principalId), 403,
        'CANONICAL_IDENTITY_UNMAPPED', 'Canonical identity 未映射或已停用')
      const issued = await client.query<{ ticket_id: string }>(
        `SELECT auth.issue_context_ticket(
           $1::uuid,$2::uuid,$3::uuid,$4::text,
           clock_timestamp()+($5::integer * interval '1 second'),$6::uuid,$1::uuid
         )::text AS ticket_id`,
        [principalId, request.actorPersonId, request.familyId, request.channel, this.ticketTtlSeconds, requestNonce]
      )
      const ticketId = issued.rows[0]?.ticket_id
      invariant(ticketId && UUID.test(ticketId), 503,
        'CANONICAL_TICKET_ISSUE_FAILED', 'Canonical ticket 签发失败')
      return { principalId, ticketId }
    } catch (error) {
      destroy = !(error instanceof AppError && error.code === 'CANONICAL_IDENTITY_UNMAPPED')
      throw error
    } finally {
      client.release(destroy)
    }
  }

  private async runWithTicket<T>(
    principalId: string,
    ticketId: string,
    identity: VerifiedOidcIdentity,
    request: CanonicalContextRequest,
    requestNonce: string,
    work: (client: CanonicalContextExecutor) => Promise<T>
  ): Promise<T> {
    const client = await this.appPool.connect().catch(() => { throw safeDatabaseError() })
    let destroy = false
    let transactionStarted = false
    try {
      await client.query('BEGIN')
      transactionStarted = true
      await client.query('SELECT auth.redeem_context_ticket($1::uuid,$2::uuid)', [ticketId, principalId])
      const executor: CanonicalContextExecutor = {
        query: async <R extends QueryResultRow = QueryResultRow>(text: string, values?: readonly unknown[]) => {
          if (FORBIDDEN_TRANSACTION_SQL.test(text)) {
            throw new AppError(500, 'CANONICAL_CONTEXT_TRANSACTION_CONTROL_FORBIDDEN',
              'Canonical 业务回调不得控制事务或角色')
          }
          return client.query<R>(text, values)
        }
      }
      const result = await work(executor)
      await client.query('SELECT auth.clear_context()')
      const cleared = await client.query<{ principal_id: string | null }>(
        'SELECT auth.current_principal_id()::text AS principal_id'
      )
      invariant(cleared.rows[0]?.principal_id === null, 503,
        'CANONICAL_CONTEXT_CLEAR_FAILED', 'Canonical context 清理失败')
      await this.audit.record({
        timestamp: new Date(this.clockMs()).toISOString(),
        requestNonce,
        issuer: identity.issuer,
        subjectId: identity.subject,
        channel: request.channel,
        decision: 'ALLOW',
        reasonCode: 'CONTEXT_TRANSACTION_READY'
      })
      await client.query('COMMIT')
      transactionStarted = false
      try {
        await client.query('DISCARD ALL')
      } catch {
        destroy = true
      }
      return result
    } catch (error) {
      destroy = true
      if (transactionStarted) await client.query('ROLLBACK').catch(() => undefined)
      throw error
    } finally {
      client.release(destroy)
    }
  }

  private async recordDeny(
    identity: VerifiedOidcIdentity | null,
    channel: CanonicalContextChannel,
    requestNonce: string,
    reasonCode: string
  ): Promise<void> {
    await this.audit.record({
      timestamp: new Date(this.clockMs()).toISOString(),
      requestNonce,
      issuer: identity?.issuer ?? 'UNVERIFIED',
      subjectId: identity && /^usr_[A-Za-z0-9_-]{1,128}$/.test(identity.subject)
        ? identity.subject
        : 'UNVERIFIED',
      channel,
      decision: 'DENY',
      reasonCode
    }).catch(() => undefined)
  }
}
