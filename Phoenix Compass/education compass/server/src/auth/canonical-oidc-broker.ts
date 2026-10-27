import {
  createPublicKey,
  randomUUID,
  sign,
  type JsonWebKey,
  type KeyObject
} from 'node:crypto'
import { AppError, invariant } from '../domain/errors'

export const CANONICAL_OIDC_BROKER_NAME = 'Phoenix First-Party Canonical Identity Broker'
export const CANONICAL_OIDC_BROKER_VERSION = '1.0'
export const CANONICAL_OIDC_ALGORITHM = 'ES256' as const
export const CANONICAL_OIDC_AUDIENCE = 'phoenix-canonical-postgresql'
export const CANONICAL_OIDC_ISSUER_PATH = '/canonical-identity'
export const CANONICAL_OIDC_JWKS_PATH = '/.well-known/phoenix-canonical-jwks.json'
export const CANONICAL_OIDC_SIGNING_KEY_FILE = '/run/secrets/phoenix_canonical_oidc_signing_key_v1'
export const CANONICAL_OIDC_SIGNING_KEY_REF = `file:${CANONICAL_OIDC_SIGNING_KEY_FILE}`
export const CANONICAL_APP_CREDENTIAL_REF = 'file:/run/secrets/phoenix_canonical_app_pgpass_v1'
export const CANONICAL_BINDER_CREDENTIAL_REF = 'file:/run/secrets/phoenix_canonical_binder_pgpass_v1'

const DEFAULT_TOKEN_TTL_SECONDS = 300
const MAX_TOKEN_TTL_SECONDS = 900
const DEFAULT_KEY_ID = 'phoenix-canonical-es256-v1'

export interface CanonicalOidcBrokerConfig {
  issuer: string
  audience: typeof CANONICAL_OIDC_AUDIENCE
  jwksUri: string
  algorithm: typeof CANONICAL_OIDC_ALGORITHM
  tokenTtlSeconds: number
  keyId: string
  signingKeyFile: typeof CANONICAL_OIDC_SIGNING_KEY_FILE
  signingKeyRef: typeof CANONICAL_OIDC_SIGNING_KEY_REF
  appCredentialRef: typeof CANONICAL_APP_CREDENTIAL_REF
  binderCredentialRef: typeof CANONICAL_BINDER_CREDENTIAL_REF
}

export interface CanonicalBrokerToken {
  accessToken: string
  tokenType: 'Bearer'
  expiresIn: number
  issuer: string
  audience: typeof CANONICAL_OIDC_AUDIENCE
  subject: string
  keyId: string
}

type JsonObject = Record<string, unknown>

function configError(message: string): never {
  throw new AppError(500, 'CANONICAL_OIDC_BROKER_CONFIG_INVALID', message)
}

function requiredText(value: string | undefined, label: string): string {
  if (!value?.trim()) configError(`${label} 未配置`)
  return value.trim()
}

function exactReference(value: string | undefined, expected: string, label: string): string {
  const actual = requiredText(value, label)
  if (actual !== expected) configError(`${label} 必须使用批准的受保护引用`)
  return actual
}

function publicBaseUrl(raw: string): URL {
  let value: URL
  try {
    value = new URL(raw)
  } catch {
    configError('PUBLIC_BASE_URL 不是有效 URL')
  }
  if (value.protocol !== 'https:' || value.username || value.password || value.search || value.hash || value.pathname !== '/') {
    configError('PUBLIC_BASE_URL 必须是无凭据、路径、查询或片段的 HTTPS origin')
  }
  return value
}

function boundedTtl(raw: string | undefined): number {
  const value = Number(raw ?? DEFAULT_TOKEN_TTL_SECONDS)
  if (!Number.isInteger(value) || value < 60 || value > MAX_TOKEN_TTL_SECONDS) {
    configError('CANONICAL_OIDC_BROKER_TOKEN_TTL_SECONDS 必须为 60–900')
  }
  return value
}

function validateConfig(config: CanonicalOidcBrokerConfig): void {
  if (config.audience !== CANONICAL_OIDC_AUDIENCE || config.algorithm !== CANONICAL_OIDC_ALGORITHM) {
    configError('Canonical broker audience 或 algorithm 漂移')
  }
  if (config.signingKeyFile !== CANONICAL_OIDC_SIGNING_KEY_FILE ||
      config.signingKeyRef !== CANONICAL_OIDC_SIGNING_KEY_REF ||
      config.appCredentialRef !== CANONICAL_APP_CREDENTIAL_REF ||
      config.binderCredentialRef !== CANONICAL_BINDER_CREDENTIAL_REF) {
    configError('Canonical broker 受保护引用漂移')
  }
  if (!/^phoenix-canonical-es256-v[1-9][0-9]*$/.test(config.keyId)) configError('Canonical broker key ID 无效')
  if (!Number.isInteger(config.tokenTtlSeconds) || config.tokenTtlSeconds < 60 || config.tokenTtlSeconds > MAX_TOKEN_TTL_SECONDS) {
    configError('Canonical broker token TTL 无效')
  }
  let issuer: URL
  let jwks: URL
  try {
    issuer = new URL(config.issuer)
    jwks = new URL(config.jwksUri)
  } catch {
    configError('Canonical broker issuer 或 JWKS URI 不是有效 URL')
  }
  if (issuer.protocol !== 'https:' || issuer.pathname !== CANONICAL_OIDC_ISSUER_PATH || issuer.search || issuer.hash ||
      jwks.protocol !== 'https:' || jwks.pathname !== CANONICAL_OIDC_JWKS_PATH || jwks.search || jwks.hash ||
      issuer.username || issuer.password || jwks.username || jwks.password || issuer.origin !== jwks.origin) {
    configError('Canonical broker issuer 或 JWKS URI 无效')
  }
}

export function loadCanonicalOidcBrokerConfig(env: NodeJS.ProcessEnv = process.env): CanonicalOidcBrokerConfig | null {
  const enabled = env.CANONICAL_OIDC_BROKER_ENABLED ?? 'false'
  if (enabled !== 'true' && enabled !== 'false') configError('CANONICAL_OIDC_BROKER_ENABLED 必须是 true 或 false')
  if (enabled === 'false') return null
  const base = publicBaseUrl(requiredText(env.PUBLIC_BASE_URL, 'PUBLIC_BASE_URL'))
  const config: CanonicalOidcBrokerConfig = {
    issuer: new URL(CANONICAL_OIDC_ISSUER_PATH, base).toString(),
    audience: CANONICAL_OIDC_AUDIENCE,
    jwksUri: new URL(CANONICAL_OIDC_JWKS_PATH, base).toString(),
    algorithm: CANONICAL_OIDC_ALGORITHM,
    tokenTtlSeconds: boundedTtl(env.CANONICAL_OIDC_BROKER_TOKEN_TTL_SECONDS),
    keyId: env.CANONICAL_OIDC_BROKER_KEY_ID?.trim() || DEFAULT_KEY_ID,
    signingKeyFile: exactReference(
      env.CANONICAL_OIDC_BROKER_SIGNING_KEY_FILE,
      CANONICAL_OIDC_SIGNING_KEY_FILE,
      'CANONICAL_OIDC_BROKER_SIGNING_KEY_FILE'
    ) as typeof CANONICAL_OIDC_SIGNING_KEY_FILE,
    signingKeyRef: exactReference(
      env.CANONICAL_OIDC_BROKER_SIGNING_KEY_REF,
      CANONICAL_OIDC_SIGNING_KEY_REF,
      'CANONICAL_OIDC_BROKER_SIGNING_KEY_REF'
    ) as typeof CANONICAL_OIDC_SIGNING_KEY_REF,
    appCredentialRef: exactReference(
      env.CANONICAL_POSTGRES_APP_CREDENTIAL_REF,
      CANONICAL_APP_CREDENTIAL_REF,
      'CANONICAL_POSTGRES_APP_CREDENTIAL_REF'
    ) as typeof CANONICAL_APP_CREDENTIAL_REF,
    binderCredentialRef: exactReference(
      env.CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF,
      CANONICAL_BINDER_CREDENTIAL_REF,
      'CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF'
    ) as typeof CANONICAL_BINDER_CREDENTIAL_REF
  }
  validateConfig(config)
  return config
}

function encode(value: JsonObject): string {
  return Buffer.from(JSON.stringify(value), 'utf8').toString('base64url')
}

export class CanonicalOidcBroker {
  readonly config: CanonicalOidcBrokerConfig
  private readonly publicJwk: JsonWebKey

  constructor(
    config: CanonicalOidcBrokerConfig,
    private readonly privateKey: KeyObject,
    private readonly clockMs: () => number = () => Date.now(),
    private readonly idFactory: () => string = randomUUID
  ) {
    validateConfig(config)
    this.config = Object.freeze({ ...config })
    invariant(privateKey.type === 'private' && privateKey.asymmetricKeyType === 'ec' &&
      privateKey.asymmetricKeyDetails?.namedCurve === 'prime256v1',
    500, 'CANONICAL_OIDC_SIGNING_KEY_INVALID', 'Canonical broker 必须使用 P-256 私钥')
    const exported = createPublicKey(privateKey).export({ format: 'jwk' })
    this.publicJwk = {
      ...exported,
      kid: config.keyId,
      alg: CANONICAL_OIDC_ALGORITHM,
      use: 'sig',
      key_ops: ['verify']
    }
  }

  jwks(): { keys: JsonWebKey[] } {
    return { keys: [{ ...this.publicJwk, key_ops: ['verify'] }] }
  }

  issueForApplicationUser(subject: string): CanonicalBrokerToken {
    invariant(/^usr_[A-Za-z0-9_-]{1,128}$/.test(subject), 400,
      'CANONICAL_OIDC_SUBJECT_INVALID', 'Canonical broker subject 必须是非个人信息应用用户 ID')
    const issuedAt = Math.floor(this.clockMs() / 1000)
    const header: JsonObject = {
      alg: CANONICAL_OIDC_ALGORITHM,
      typ: 'at+jwt',
      kid: this.config.keyId
    }
    const claims: JsonObject = {
      iss: this.config.issuer,
      aud: this.config.audience,
      sub: subject,
      iat: issuedAt,
      nbf: issuedAt,
      exp: issuedAt + this.config.tokenTtlSeconds,
      jti: this.idFactory()
    }
    const signingInput = `${encode(header)}.${encode(claims)}`
    const signature = sign('SHA256', Buffer.from(signingInput, 'ascii'), {
      key: this.privateKey,
      dsaEncoding: 'ieee-p1363'
    })
    return {
      accessToken: `${signingInput}.${signature.toString('base64url')}`,
      tokenType: 'Bearer',
      expiresIn: this.config.tokenTtlSeconds,
      issuer: this.config.issuer,
      audience: this.config.audience,
      subject,
      keyId: this.config.keyId
    }
  }
}
