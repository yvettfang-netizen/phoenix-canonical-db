import { createPublicKey, type JsonWebKey, type KeyObject, verify as verifySignature } from 'node:crypto'
import { AppError, invariant } from '../domain/errors'

export type AllowedOidcAlgorithm = 'RS256' | 'ES256'

export interface OidcJwtVerifierConfig {
  issuer: string
  audience: string
  jwksUri: string
  allowedAlgorithms: readonly AllowedOidcAlgorithm[]
  tokenMaxTtlSeconds: number
  clockSkewSeconds: number
  jwksCacheSeconds: number
  unknownKidRefreshRateLimitSeconds: number
}

export interface VerifiedOidcIdentity {
  issuer: string
  subject: string
  audience: string
  expiresAt: number
  notBefore: number
  keyId: string
  algorithm: AllowedOidcAlgorithm
}

type JsonObject = Record<string, unknown>

interface CachedJwks {
  keys: JsonObject[]
  expiresAtMs: number
}

const MAX_TOKEN_BYTES = 32 * 1024
const MAX_JWKS_BYTES = 1024 * 1024
const MAX_JWKS_KEYS = 100

function configError(message: string): never {
  throw new AppError(500, 'OIDC_CONFIG_INVALID', message)
}

function invalidToken(message: string): never {
  throw new AppError(401, 'OIDC_TOKEN_INVALID', message)
}

function requireConfigText(value: string | undefined, label: string): string {
  if (!value?.trim()) configError(`${label} 未配置`)
  return value.trim()
}

function boundedInteger(raw: string | undefined, fallback: number, min: number, max: number, label: string): number {
  const value = Number(raw ?? fallback)
  if (!Number.isInteger(value) || value < min || value > max) configError(`${label} 无效`)
  return value
}

function strictHttpsUrl(raw: string, label: string, allowQuery = true): URL {
  let url: URL
  try {
    url = new URL(raw)
  } catch {
    configError(`${label} 不是有效 URL`)
  }
  if (url.protocol !== 'https:' || url.username || url.password || url.hash || (!allowQuery && url.search)) {
    configError(`${label} 必须是无凭据或片段的 HTTPS URL`)
  }
  return url
}

function validateConfig(config: OidcJwtVerifierConfig): void {
  strictHttpsUrl(config.issuer, 'CANONICAL_OIDC_ISSUER', false)
  strictHttpsUrl(config.jwksUri, 'CANONICAL_OIDC_JWKS_URI')
  if (!config.audience.trim() || config.audience.length > 512) configError('CANONICAL_OIDC_AUDIENCE 无效')
  const uniqueAlgorithms = new Set(config.allowedAlgorithms)
  if (uniqueAlgorithms.size !== config.allowedAlgorithms.length || uniqueAlgorithms.size === 0) {
    configError('CANONICAL_OIDC_ALLOWED_ALGORITHMS 必须是不重复的 RS256/ES256')
  }
  for (const algorithm of uniqueAlgorithms) {
    if (algorithm !== 'RS256' && algorithm !== 'ES256') configError('仅允许 RS256 或 ES256')
  }
  if (!Number.isInteger(config.tokenMaxTtlSeconds) || config.tokenMaxTtlSeconds < 1 || config.tokenMaxTtlSeconds > 900) {
    configError('CANONICAL_OIDC_TOKEN_MAX_TTL_SECONDS 必须为 1–900')
  }
  if (!Number.isInteger(config.clockSkewSeconds) || config.clockSkewSeconds < 0 || config.clockSkewSeconds > 60) {
    configError('CANONICAL_OIDC_CLOCK_SKEW_SECONDS 必须为 0–60')
  }
  if (!Number.isInteger(config.jwksCacheSeconds) || config.jwksCacheSeconds < 1 || config.jwksCacheSeconds > 3600) {
    configError('CANONICAL_OIDC_JWKS_CACHE_SECONDS 必须为 1–3600')
  }
  if (!Number.isInteger(config.unknownKidRefreshRateLimitSeconds) ||
      config.unknownKidRefreshRateLimitSeconds < 1 || config.unknownKidRefreshRateLimitSeconds > 3600) {
    configError('CANONICAL_OIDC_UNKNOWN_KID_REFRESH_RATE_LIMIT_SECONDS 必须为 1–3600')
  }
}

export function loadOidcJwtVerifierConfig(env: NodeJS.ProcessEnv = process.env): OidcJwtVerifierConfig | null {
  const enabled = env.CANONICAL_OIDC_ENABLED ?? 'false'
  if (enabled !== 'true' && enabled !== 'false') configError('CANONICAL_OIDC_ENABLED 必须是 true 或 false')
  if (enabled === 'false') return null
  const rawAlgorithms = (env.CANONICAL_OIDC_ALLOWED_ALGORITHMS ?? 'RS256,ES256')
    .split(',').map((item) => item.trim()).filter(Boolean)
  const config: OidcJwtVerifierConfig = {
    issuer: requireConfigText(env.CANONICAL_OIDC_ISSUER, 'CANONICAL_OIDC_ISSUER'),
    audience: requireConfigText(env.CANONICAL_OIDC_AUDIENCE, 'CANONICAL_OIDC_AUDIENCE'),
    jwksUri: requireConfigText(env.CANONICAL_OIDC_JWKS_URI, 'CANONICAL_OIDC_JWKS_URI'),
    allowedAlgorithms: rawAlgorithms as AllowedOidcAlgorithm[],
    tokenMaxTtlSeconds: boundedInteger(env.CANONICAL_OIDC_TOKEN_MAX_TTL_SECONDS, 900, 1, 900,
      'CANONICAL_OIDC_TOKEN_MAX_TTL_SECONDS'),
    clockSkewSeconds: boundedInteger(env.CANONICAL_OIDC_CLOCK_SKEW_SECONDS, 60, 0, 60,
      'CANONICAL_OIDC_CLOCK_SKEW_SECONDS'),
    jwksCacheSeconds: boundedInteger(env.CANONICAL_OIDC_JWKS_CACHE_SECONDS, 3600, 1, 3600,
      'CANONICAL_OIDC_JWKS_CACHE_SECONDS'),
    unknownKidRefreshRateLimitSeconds: boundedInteger(
      env.CANONICAL_OIDC_UNKNOWN_KID_REFRESH_RATE_LIMIT_SECONDS, 60, 1, 3600,
      'CANONICAL_OIDC_UNKNOWN_KID_REFRESH_RATE_LIMIT_SECONDS'
    )
  }
  validateConfig(config)
  return config
}

function decodeJsonSegment(segment: string, label: string): JsonObject {
  if (!segment || !/^[A-Za-z0-9_-]+$/.test(segment)) invalidToken(`${label} 编码无效`)
  const bytes = Buffer.from(segment, 'base64url')
  if (bytes.toString('base64url') !== segment) invalidToken(`${label} 必须使用规范 Base64URL`)
  try {
    const value: unknown = JSON.parse(bytes.toString('utf8'))
    if (!value || typeof value !== 'object' || Array.isArray(value)) invalidToken(`${label} 必须是 JSON object`)
    return value as JsonObject
  } catch (error) {
    if (error instanceof AppError) throw error
    invalidToken(`${label} JSON 无效`)
  }
}

function numericDate(value: unknown, label: string): number {
  if (!Number.isSafeInteger(value)) invalidToken(`${label} 必须是整数 NumericDate`)
  return value as number
}

function expectedAudience(value: unknown, expected: string): boolean {
  return typeof value === 'string' && value === expected
}

function publicKeyFor(jwk: JsonObject, algorithm: AllowedOidcAlgorithm): KeyObject {
  for (const privateMember of ['d', 'p', 'q', 'dp', 'dq', 'qi', 'oth']) {
    if (jwk[privateMember] !== undefined) invalidToken('JWKS 不得包含私钥材料')
  }
  if (jwk.use !== undefined && jwk.use !== 'sig') invalidToken('JWKS key use 不允许验证签名')
  if (jwk.alg !== undefined && jwk.alg !== algorithm) invalidToken('JWKS key alg 与 token 不匹配')
  if (jwk.key_ops !== undefined &&
      (!Array.isArray(jwk.key_ops) || !jwk.key_ops.every((item) => typeof item === 'string') || !jwk.key_ops.includes('verify'))) {
    invalidToken('JWKS key_ops 不允许验证签名')
  }
  if (algorithm === 'RS256') {
    if (jwk.kty !== 'RSA' || typeof jwk.n !== 'string' || typeof jwk.e !== 'string') invalidToken('RS256 JWK 无效')
  } else if (jwk.kty !== 'EC' || jwk.crv !== 'P-256' || typeof jwk.x !== 'string' || typeof jwk.y !== 'string') {
    invalidToken('ES256 JWK 无效')
  }
  try {
    const key = createPublicKey({ key: jwk as JsonWebKey, format: 'jwk' })
    if (algorithm === 'RS256' && (key.asymmetricKeyDetails?.modulusLength ?? 0) < 2048) {
      invalidToken('RS256 key 至少需要 2048 bit')
    }
    if (algorithm === 'ES256' && key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
      invalidToken('ES256 key 必须使用 P-256')
    }
    return key
  } catch {
    invalidToken('JWK 无法导入')
  }
}

export class OidcJwtVerifier {
  private cache: CachedJwks | null = null
  private lastUnknownKidRefreshMs = Number.NEGATIVE_INFINITY

  constructor(
    private readonly config: OidcJwtVerifierConfig,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly clockMs: () => number = () => Date.now()
  ) {
    validateConfig(config)
  }

  async verify(token: string): Promise<VerifiedOidcIdentity> {
    if (!token || Buffer.byteLength(token, 'utf8') > MAX_TOKEN_BYTES) invalidToken('JWT 为空或过大')
    const parts = token.split('.')
    if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) invalidToken('JWT compact 格式无效')
    const header = decodeJsonSegment(parts[0], 'JWT header')
    const claims = decodeJsonSegment(parts[1], 'JWT payload')
    const algorithm = header.alg
    if (algorithm !== 'RS256' && algorithm !== 'ES256') invalidToken('JWT alg 不允许')
    if (!this.config.allowedAlgorithms.includes(algorithm)) invalidToken('JWT alg 未配置')
    const keyId = header.kid
    if (typeof keyId !== 'string' || !keyId || keyId.length > 256) invalidToken('JWT kid 无效')
    for (const remoteKeyHeader of ['jku', 'jwk', 'x5u', 'x5c', 'crit', 'b64', 'zip']) {
      if (header[remoteKeyHeader] !== undefined) invalidToken(`JWT header 不允许 ${remoteKeyHeader}`)
    }
    if (header.typ !== undefined && header.typ !== 'JWT' && header.typ !== 'at+jwt') invalidToken('JWT typ 无效')

    const issuer = claims.iss
    const subject = claims.sub
    if (issuer !== this.config.issuer) invalidToken('JWT issuer 不匹配')
    if (typeof subject !== 'string' || !subject || subject.length > 512) invalidToken('JWT subject 无效')
    if (!expectedAudience(claims.aud, this.config.audience)) invalidToken('JWT audience 不匹配')
    const expiresAt = numericDate(claims.exp, 'JWT exp')
    const notBefore = numericDate(claims.nbf, 'JWT nbf')
    if (expiresAt <= notBefore || expiresAt - notBefore > this.config.tokenMaxTtlSeconds) invalidToken('JWT 生命周期超限')
    const now = Math.floor(this.clockMs() / 1000)
    if (expiresAt <= now - this.config.clockSkewSeconds) invalidToken('JWT 已过期')
    if (notBefore > now + this.config.clockSkewSeconds) invalidToken('JWT 尚未生效')

    const jwk = await this.resolveKey(keyId, algorithm)
    const publicKey = publicKeyFor(jwk, algorithm)
    const signature = Buffer.from(parts[2], 'base64url')
    if (signature.toString('base64url') !== parts[2]) invalidToken('JWT signature 编码无效')
    if (algorithm === 'ES256' && signature.length !== 64) invalidToken('ES256 signature 长度无效')
    const signingInput = Buffer.from(`${parts[0]}.${parts[1]}`, 'ascii')
    const verified = algorithm === 'RS256'
      ? verifySignature('RSA-SHA256', signingInput, publicKey, signature)
      : verifySignature('SHA256', signingInput, { key: publicKey, dsaEncoding: 'ieee-p1363' }, signature)
    if (!verified) invalidToken('JWT signature 无效')
    return {
      issuer: this.config.issuer,
      subject,
      audience: this.config.audience,
      expiresAt,
      notBefore,
      keyId,
      algorithm
    }
  }

  private async resolveKey(keyId: string, algorithm: AllowedOidcAlgorithm): Promise<JsonObject> {
    const now = this.clockMs()
    const hadFreshCache = Boolean(this.cache && this.cache.expiresAtMs > now)
    let keys = await this.loadKeys(false)
    let matches = keys.filter((item) => item.kid === keyId)
    if (matches.length === 0 && hadFreshCache) {
      if (now - this.lastUnknownKidRefreshMs < this.config.unknownKidRefreshRateLimitSeconds * 1000) {
        invalidToken('JWT kid 未找到且刷新受限')
      }
      this.lastUnknownKidRefreshMs = now
      keys = await this.loadKeys(true)
      matches = keys.filter((item) => item.kid === keyId)
    }
    if (matches.length !== 1) invalidToken(matches.length === 0 ? 'JWT kid 未找到' : 'JWKS kid 不唯一')
    const key = matches[0]
    invariant(key, 401, 'OIDC_TOKEN_INVALID', 'JWT kid 未找到')
    if (key.alg !== undefined && key.alg !== algorithm) invalidToken('JWT alg 与 JWKS 不匹配')
    return key
  }

  private async loadKeys(force: boolean): Promise<JsonObject[]> {
    const now = this.clockMs()
    if (!force && this.cache && this.cache.expiresAtMs > now) return this.cache.keys
    let response: Response
    try {
      response = await this.fetchImpl(this.config.jwksUri, {
        method: 'GET',
        redirect: 'error',
        headers: { Accept: 'application/json, application/jwk-set+json' },
        signal: AbortSignal.timeout(5_000)
      })
    } catch {
      throw new AppError(503, 'OIDC_JWKS_UNAVAILABLE', 'OIDC JWKS 暂不可用')
    }
    if (!response.ok) throw new AppError(503, 'OIDC_JWKS_UNAVAILABLE', 'OIDC JWKS 暂不可用')
    const contentType = response.headers.get('content-type') ?? ''
    if (!/^application\/(?:json|jwk-set\+json)(?:\s*;|$)/i.test(contentType)) {
      throw new AppError(503, 'OIDC_JWKS_UNAVAILABLE', 'OIDC JWKS Content-Type 无效')
    }
    const contentLength = response.headers.get('content-length')
    if (contentLength !== null && (!/^\d+$/.test(contentLength) || Number(contentLength) > MAX_JWKS_BYTES)) {
      throw new AppError(503, 'OIDC_JWKS_UNAVAILABLE', 'OIDC JWKS 响应过大')
    }
    const text = await response.text()
    if (Buffer.byteLength(text, 'utf8') > MAX_JWKS_BYTES) {
      throw new AppError(503, 'OIDC_JWKS_UNAVAILABLE', 'OIDC JWKS 响应过大')
    }
    let body: unknown
    try {
      body = JSON.parse(text)
    } catch {
      throw new AppError(503, 'OIDC_JWKS_UNAVAILABLE', 'OIDC JWKS JSON 无效')
    }
    if (!body || typeof body !== 'object' || Array.isArray(body) ||
        !Array.isArray((body as JsonObject).keys) || (body as { keys: unknown[] }).keys.length > MAX_JWKS_KEYS ||
        !(body as { keys: unknown[] }).keys.every((item) => item && typeof item === 'object' && !Array.isArray(item))) {
      throw new AppError(503, 'OIDC_JWKS_UNAVAILABLE', 'OIDC JWKS 结构无效')
    }
    const keys = (body as { keys: JsonObject[] }).keys
    this.cache = { keys, expiresAtMs: now + this.config.jwksCacheSeconds * 1000 }
    return keys
  }
}
