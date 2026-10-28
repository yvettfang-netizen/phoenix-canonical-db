import { constants } from 'node:fs'
import { open, readFile, stat, type FileHandle } from 'node:fs/promises'
import { isAbsolute } from 'node:path'
import { Pool, type PoolConfig, type QueryResultRow } from 'pg'
import { AppError, invariant } from '../domain/errors'
import {
  CANONICAL_APP_CREDENTIAL_REF,
  CANONICAL_BINDER_CREDENTIAL_REF
} from './canonical-oidc-broker'
import {
  CanonicalContextGateway,
  type CanonicalConnectionPool,
  type CanonicalGatewayAuditEvent,
  type CanonicalGatewayAuditSink,
  type CanonicalPoolClient,
  type CanonicalTokenVerifier
} from './canonical-context-gateway'

const APP_ROLE = 'phoenix_canonical_app_runtime'
const BINDER_ROLE = 'phoenix_canonical_binder_runtime'
const DATABASE = 'phoenix_canonical_dev'
const HOST = '127.0.0.1'
const TICKET_TTL_SECONDS = 45

export interface CanonicalContextRuntimeConfig {
  appCredentialRef: typeof CANONICAL_APP_CREDENTIAL_REF
  binderCredentialRef: typeof CANONICAL_BINDER_CREDENTIAL_REF
  auditFile: string
  ticketTtlSeconds: typeof TICKET_TTL_SECONDS
}

export interface CanonicalContextRuntime {
  gateway: CanonicalContextGateway
  close(): Promise<void>
}

interface PgpassEntry {
  host: typeof HOST
  port: number
  database: typeof DATABASE
  user: string
  password: string
}

export type CanonicalPoolFactory = (config: PoolConfig) => CanonicalConnectionPool

interface ClosableAuditSink extends CanonicalGatewayAuditSink {
  close(): Promise<void>
}

export interface CanonicalContextRuntimeDependencies {
  poolFactory?: CanonicalPoolFactory
  credentialReader?: (path: string, label: string) => Promise<string>
  auditFactory?: (path: string) => Promise<ClosableAuditSink>
}

function configError(message: string): never {
  throw new AppError(500, 'CANONICAL_CONTEXT_CONFIG_INVALID', message)
}

function exactReference(value: string | undefined, expected: string, label: string): string {
  if (value !== expected) configError(`${label} 必须使用批准的受保护引用`)
  return value
}

export function loadCanonicalContextRuntimeConfig(
  env: NodeJS.ProcessEnv = process.env
): CanonicalContextRuntimeConfig | null {
  const enabled = env.CANONICAL_CONTEXT_GATEWAY_ENABLED ?? 'false'
  if (enabled !== 'true' && enabled !== 'false') configError('CANONICAL_CONTEXT_GATEWAY_ENABLED 必须是 true 或 false')
  if (enabled === 'false') return null
  if (env.CANONICAL_OIDC_BROKER_ENABLED !== 'true' || env.CANONICAL_OIDC_ENABLED !== 'true') {
    configError('Canonical context gateway 需要同时启用已批准的 broker 和 verifier')
  }
  const auditFile = env.CANONICAL_GATEWAY_AUDIT_FILE?.trim() ?? ''
  if (!auditFile || !isAbsolute(auditFile)) configError('CANONICAL_GATEWAY_AUDIT_FILE 必须是绝对路径')
  const ticketTtlSeconds = Number(env.CANONICAL_CONTEXT_TICKET_TTL_SECONDS ?? TICKET_TTL_SECONDS)
  if (ticketTtlSeconds !== TICKET_TTL_SECONDS) configError('Canonical context ticket TTL 必须固定为 45 秒')
  return {
    appCredentialRef: exactReference(
      env.CANONICAL_POSTGRES_APP_CREDENTIAL_REF,
      CANONICAL_APP_CREDENTIAL_REF,
      'CANONICAL_POSTGRES_APP_CREDENTIAL_REF'
    ) as typeof CANONICAL_APP_CREDENTIAL_REF,
    binderCredentialRef: exactReference(
      env.CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF,
      CANONICAL_BINDER_CREDENTIAL_REF,
      'CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF'
    ) as typeof CANONICAL_BINDER_CREDENTIAL_REF,
    auditFile,
    ticketTtlSeconds: TICKET_TTL_SECONDS
  }
}

function pathFromFileReference(reference: string): string {
  invariant(reference.startsWith('file:/'), 500, 'CANONICAL_CONTEXT_CONFIG_INVALID', 'Canonical credential reference 必须是 file 路径')
  return reference.slice('file:'.length)
}

async function protectedFile(path: string, label: string): Promise<string> {
  let metadata
  try {
    metadata = await stat(path)
  } catch {
    configError(`${label} 不存在`)
  }
  if (!metadata.isFile()) configError(`${label} 必须是普通文件`)
  if (process.platform !== 'win32' && (metadata.mode & 0o077) !== 0) configError(`${label} 必须拒绝 group/other 访问`)
  return readFile(path, 'utf8')
}

function parsePgpass(raw: string, expectedUser: string, label: string): PgpassEntry {
  const lines = raw.split(/\r?\n/).filter((line) => line.length > 0)
  if (lines.length !== 1) configError(`${label} 必须只包含一条 pgpass 记录`)
  const fields = lines[0]?.split(':') ?? []
  if (fields.length !== 5) configError(`${label} pgpass 格式无效`)
  const [host, portRaw, database, user, password] = fields
  const port = Number(portRaw)
  if (host !== HOST || database !== DATABASE || user !== expectedUser ||
      !Number.isInteger(port) || port < 1 || port > 65535 || !password || !/^[0-9a-f]{64}$/.test(password)) {
    configError(`${label} pgpass 坐标、角色或口令格式无效`)
  }
  return { host, port, database, user, password }
}

class PgPoolAdapter implements CanonicalConnectionPool {
  constructor(private readonly pool: Pool) {}

  async connect(): Promise<CanonicalPoolClient> {
    return await this.pool.connect() as unknown as CanonicalPoolClient
  }

  async end(): Promise<void> {
    await this.pool.end()
  }
}

export class ProtectedJsonLineAuditSink implements CanonicalGatewayAuditSink {
  private pending: Promise<void> = Promise.resolve()

  private constructor(private readonly handle: FileHandle) {}

  static async open(path: string): Promise<ProtectedJsonLineAuditSink> {
    const flags = constants.O_APPEND | constants.O_CREAT | constants.O_WRONLY |
      (process.platform === 'win32' ? 0 : constants.O_NOFOLLOW)
    const handle = await open(path, flags, 0o600).catch(() => configError('Canonical gateway audit 文件无法打开'))
    const metadata = await handle.stat()
    if (!metadata.isFile() || (process.platform !== 'win32' && (metadata.mode & 0o077) !== 0)) {
      await handle.close()
      configError('Canonical gateway audit 文件必须是 0600 普通文件')
    }
    return new ProtectedJsonLineAuditSink(handle)
  }

  async record(event: CanonicalGatewayAuditEvent): Promise<void> {
    const parsedTimestamp = new Date(event.timestamp)
    let issuerValid = event.issuer === 'UNVERIFIED'
    if (!issuerValid && event.issuer.length <= 512) {
      try {
        const issuer = new URL(event.issuer)
        issuerValid = issuer.protocol === 'https:' && !issuer.username && !issuer.password && !issuer.hash
      } catch {
        issuerValid = false
      }
    }
    if (!Number.isFinite(parsedTimestamp.getTime()) || parsedTimestamp.toISOString() !== event.timestamp ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(event.requestNonce) ||
        !issuerValid || !/^(?:usr_[A-Za-z0-9_-]{1,128}|UNVERIFIED)$/.test(event.subjectId) ||
        !['FAMILY', 'ADVISOR', 'PARTNER', 'INTERNAL'].includes(event.channel) ||
        !['ALLOW', 'DENY'].includes(event.decision) || !/^[A-Z0-9_]{2,80}$/.test(event.reasonCode)) {
      throw new AppError(500, 'CANONICAL_AUDIT_EVENT_INVALID', 'Canonical gateway audit 事件无效')
    }
    const exactEvent: CanonicalGatewayAuditEvent = {
      timestamp: event.timestamp,
      requestNonce: event.requestNonce,
      issuer: event.issuer,
      subjectId: event.subjectId,
      channel: event.channel,
      decision: event.decision,
      reasonCode: event.reasonCode
    }
    const line = `${JSON.stringify(exactEvent)}\n`
    this.pending = this.pending.then(async () => {
      await this.handle.appendFile(line, 'utf8')
      await this.handle.sync()
    })
    await this.pending
  }

  async close(): Promise<void> {
    await this.pending
    await this.handle.close()
  }
}

function poolConfig(entry: PgpassEntry, applicationName: string): PoolConfig {
  return {
    host: entry.host,
    port: entry.port,
    database: entry.database,
    user: entry.user,
    password: entry.password,
    max: 5,
    connectionTimeoutMillis: 5_000,
    idleTimeoutMillis: 30_000,
    statement_timeout: 10_000,
    query_timeout: 12_000,
    application_name: applicationName
  }
}

async function assertPoolRole(pool: CanonicalConnectionPool, expected: string): Promise<void> {
  const client = await pool.connect()
  let destroy = false
  try {
    const result = await client.query<{ current_user: string }>('SELECT current_user::text AS current_user')
    invariant(result.rows[0]?.current_user === expected, 500,
      'CANONICAL_CONTEXT_ROLE_MISMATCH', 'Canonical pool 登录角色不匹配')
  } catch (error) {
    destroy = true
    throw error
  } finally {
    client.release(destroy)
  }
}

export async function createCanonicalContextRuntime(
  config: CanonicalContextRuntimeConfig,
  verifier: CanonicalTokenVerifier,
  dependencies: CanonicalContextRuntimeDependencies = {}
): Promise<CanonicalContextRuntime> {
  const poolFactory = dependencies.poolFactory ?? ((poolOptions) => new PgPoolAdapter(new Pool(poolOptions)))
  const credentialReader = dependencies.credentialReader ?? protectedFile
  const auditFactory = dependencies.auditFactory ?? ProtectedJsonLineAuditSink.open
  const [appRaw, binderRaw] = await Promise.all([
    credentialReader(pathFromFileReference(config.appCredentialRef), 'Canonical app pgpass'),
    credentialReader(pathFromFileReference(config.binderCredentialRef), 'Canonical binder pgpass')
  ])
  const appEntry = parsePgpass(appRaw, APP_ROLE, 'Canonical app pgpass')
  const binderEntry = parsePgpass(binderRaw, BINDER_ROLE, 'Canonical binder pgpass')
  invariant(appEntry.password !== binderEntry.password, 500,
    'CANONICAL_CONTEXT_CONFIG_INVALID', 'Canonical app 与 binder 不得复用口令')
  const appPool = poolFactory(poolConfig(appEntry, 'phoenix-canonical-app-gateway'))
  const binderPool = poolFactory(poolConfig(binderEntry, 'phoenix-canonical-binder-gateway'))
  const audit = await auditFactory(config.auditFile)
  try {
    await Promise.all([assertPoolRole(appPool, APP_ROLE), assertPoolRole(binderPool, BINDER_ROLE)])
    const gateway = new CanonicalContextGateway(verifier, binderPool, appPool, audit, {
      ticketTtlSeconds: config.ticketTtlSeconds
    })
    return {
      gateway,
      close: async () => {
        await Promise.allSettled([appPool.end(), binderPool.end(), audit.close()])
      }
    }
  } catch (error) {
    await Promise.allSettled([appPool.end(), binderPool.end(), audit.close()])
    throw error
  }
}
