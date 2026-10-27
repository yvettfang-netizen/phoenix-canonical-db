import assert from 'node:assert/strict'
import { generateKeyPairSync } from 'node:crypto'
import { AddressInfo } from 'node:net'
import test from 'node:test'
import {
  CANONICAL_APP_CREDENTIAL_REF,
  CANONICAL_BINDER_CREDENTIAL_REF,
  CANONICAL_OIDC_AUDIENCE,
  CANONICAL_OIDC_JWKS_PATH,
  CANONICAL_OIDC_SIGNING_KEY_FILE,
  CANONICAL_OIDC_SIGNING_KEY_REF,
  CanonicalOidcBroker,
  loadCanonicalOidcBrokerConfig
} from '../src/auth/canonical-oidc-broker'
import { OidcJwtVerifier } from '../src/auth/oidc-jwt-verifier'
import { AppError } from '../src/domain/errors'
import { createAppServer, type AppDependencies } from '../src/http/app'

const nowSeconds = 1_800_000_000
const nowMs = nowSeconds * 1000

function enabledEnv(overrides: NodeJS.ProcessEnv = {}): NodeJS.ProcessEnv {
  return {
    CANONICAL_OIDC_BROKER_ENABLED: 'true',
    PUBLIC_BASE_URL: 'https://api.phoenix.synthetic.test',
    CANONICAL_OIDC_BROKER_KEY_ID: 'phoenix-canonical-es256-v1',
    CANONICAL_OIDC_BROKER_TOKEN_TTL_SECONDS: '300',
    CANONICAL_OIDC_BROKER_SIGNING_KEY_FILE: CANONICAL_OIDC_SIGNING_KEY_FILE,
    CANONICAL_OIDC_BROKER_SIGNING_KEY_REF: CANONICAL_OIDC_SIGNING_KEY_REF,
    CANONICAL_POSTGRES_APP_CREDENTIAL_REF: CANONICAL_APP_CREDENTIAL_REF,
    CANONICAL_POSTGRES_BINDER_CREDENTIAL_REF: CANONICAL_BINDER_CREDENTIAL_REF,
    ...overrides
  }
}

function isCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof AppError && error.code === code
}

function decodeSegment(token: string, index: number): Record<string, unknown> {
  const segment = token.split('.')[index]
  assert.ok(segment)
  return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8')) as Record<string, unknown>
}

test('first-party broker selection derives exact metadata and protected reference names', () => {
  assert.equal(loadCanonicalOidcBrokerConfig({}), null)
  const config = loadCanonicalOidcBrokerConfig(enabledEnv())
  assert.ok(config)
  assert.equal(config.issuer, 'https://api.phoenix.synthetic.test/canonical-identity')
  assert.equal(config.audience, CANONICAL_OIDC_AUDIENCE)
  assert.equal(config.jwksUri, 'https://api.phoenix.synthetic.test/.well-known/phoenix-canonical-jwks.json')
  assert.equal(config.algorithm, 'ES256')
  assert.equal(config.tokenTtlSeconds, 300)
  assert.equal(config.signingKeyRef, CANONICAL_OIDC_SIGNING_KEY_REF)
  assert.notEqual(config.appCredentialRef, config.binderCredentialRef)
})

test('enabled broker fails closed on absent origin, unsafe origin or reference drift', () => {
  assert.throws(() => loadCanonicalOidcBrokerConfig({ CANONICAL_OIDC_BROKER_ENABLED: 'true' }),
    isCode('CANONICAL_OIDC_BROKER_CONFIG_INVALID'))
  assert.throws(() => loadCanonicalOidcBrokerConfig(enabledEnv({ PUBLIC_BASE_URL: 'http://api.invalid' })),
    isCode('CANONICAL_OIDC_BROKER_CONFIG_INVALID'))
  assert.throws(() => loadCanonicalOidcBrokerConfig(enabledEnv({ PUBLIC_BASE_URL: 'https://api.invalid/path' })),
    isCode('CANONICAL_OIDC_BROKER_CONFIG_INVALID'))
  assert.throws(() => loadCanonicalOidcBrokerConfig(enabledEnv({ PUBLIC_BASE_URL: 'https://user:secret@api.invalid' })),
    isCode('CANONICAL_OIDC_BROKER_CONFIG_INVALID'))
  assert.throws(() => loadCanonicalOidcBrokerConfig(enabledEnv({
    CANONICAL_POSTGRES_APP_CREDENTIAL_REF: CANONICAL_BINDER_CREDENTIAL_REF
  })), isCode('CANONICAL_OIDC_BROKER_CONFIG_INVALID'))
  assert.throws(() => loadCanonicalOidcBrokerConfig(enabledEnv({
    CANONICAL_OIDC_BROKER_TOKEN_TTL_SECONDS: '901'
  })), isCode('CANONICAL_OIDC_BROKER_CONFIG_INVALID'))
})

test('broker issues minimal short-lived ES256 token that passes the FD-6 verifier', async () => {
  const config = loadCanonicalOidcBrokerConfig(enabledEnv())
  assert.ok(config)
  const pair = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  const broker = new CanonicalOidcBroker(config, pair.privateKey, () => nowMs, () => 'synthetic-jti-001')
  assert.equal(Object.isFrozen(broker.config), true)
  const mutableJwks = broker.jwks()
  ;(mutableJwks.keys[0]?.key_ops as string[]).push('sign')
  assert.deepEqual(broker.jwks().keys[0]?.key_ops, ['verify'])
  const issued = broker.issueForApplicationUser('usr_synthetic_001')
  const header = decodeSegment(issued.accessToken, 0)
  const claims = decodeSegment(issued.accessToken, 1)

  assert.deepEqual(Object.keys(header).sort(), ['alg', 'kid', 'typ'])
  assert.deepEqual(Object.keys(claims).sort(), ['aud', 'exp', 'iat', 'iss', 'jti', 'nbf', 'sub'])
  assert.equal(claims.sub, 'usr_synthetic_001')
  assert.equal(claims.exp, nowSeconds + 300)
  assert.equal(JSON.stringify(claims).includes('openid'), false)
  assert.equal(JSON.stringify(claims).includes('synthetic@example'), false)

  const verifier = new OidcJwtVerifier({
    issuer: config.issuer,
    audience: config.audience,
    jwksUri: config.jwksUri,
    allowedAlgorithms: ['ES256'],
    tokenMaxTtlSeconds: 300,
    clockSkewSeconds: 60,
    jwksCacheSeconds: 300,
    unknownKidRefreshRateLimitSeconds: 60
  }, (async () => new Response(JSON.stringify(broker.jwks()), {
    status: 200,
    headers: { 'Content-Type': 'application/jwk-set+json' }
  })) as typeof fetch, () => nowMs)
  const verified = await verifier.verify(issued.accessToken)
  assert.equal(verified.subject, 'usr_synthetic_001')
  assert.equal(verified.algorithm, 'ES256')
})

test('broker rejects non-P-256 signing keys and non-application subjects', () => {
  const config = loadCanonicalOidcBrokerConfig(enabledEnv())
  assert.ok(config)
  const rsa = generateKeyPairSync('rsa', { modulusLength: 2048 })
  assert.throws(() => new CanonicalOidcBroker(config, rsa.privateKey),
    isCode('CANONICAL_OIDC_SIGNING_KEY_INVALID'))
  const ec = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  const broker = new CanonicalOidcBroker(config, ec.privateKey, () => nowMs)
  assert.throws(() => broker.issueForApplicationUser('openid-sensitive-value'),
    isCode('CANONICAL_OIDC_SUBJECT_INVALID'))
})

test('only the public JWKS endpoint is exposed without application authentication', async () => {
  const config = loadCanonicalOidcBrokerConfig(enabledEnv())
  assert.ok(config)
  const ec = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  const broker = new CanonicalOidcBroker(config, ec.privateKey, () => nowMs)
  const auth = {
    authenticate: async () => { throw new AppError(401, 'AUTH_REQUIRED', '需要登录') }
  }
  const server = createAppServer({ auth, canonicalOidcBroker: broker } as unknown as AppDependencies)
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
  try {
    const address = server.address() as AddressInfo
    const response = await fetch(`http://127.0.0.1:${address.port}${CANONICAL_OIDC_JWKS_PATH}`)
    assert.equal(response.status, 200)
    assert.match(response.headers.get('content-type') ?? '', /^application\/jwk-set\+json/)
    assert.equal(response.headers.get('cache-control'), 'public, max-age=300, must-revalidate')
    const body = await response.json() as { keys: Array<Record<string, unknown>> }
    assert.equal(body.keys.length, 1)
    assert.equal(body.keys[0]?.d, undefined)
    assert.equal(body.keys[0]?.crv, 'P-256')

    const issueResponse = await fetch(`http://127.0.0.1:${address.port}/canonical-identity`, {
      method: 'POST'
    })
    assert.equal(issueResponse.status, 401)
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()))
  }
})
