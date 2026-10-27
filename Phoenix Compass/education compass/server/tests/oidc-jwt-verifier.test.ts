import assert from 'node:assert/strict'
import { generateKeyPairSync, type JsonWebKey, type KeyObject, sign } from 'node:crypto'
import test from 'node:test'
import { AppError } from '../src/domain/errors'
import {
  loadOidcJwtVerifierConfig,
  OidcJwtVerifier,
  type AllowedOidcAlgorithm,
  type OidcJwtVerifierConfig
} from '../src/auth/oidc-jwt-verifier'

const nowSeconds = 1_800_000_000
const nowMs = nowSeconds * 1000

function keyPair(algorithm: AllowedOidcAlgorithm, kid: string): { privateKey: KeyObject; jwk: JsonWebKey } {
  const pair = algorithm === 'RS256'
    ? generateKeyPairSync('rsa', { modulusLength: 2048, publicExponent: 0x10001 })
    : generateKeyPairSync('ec', { namedCurve: 'P-256' })
  return {
    privateKey: pair.privateKey,
    jwk: { ...pair.publicKey.export({ format: 'jwk' }), kid, alg: algorithm, use: 'sig', key_ops: ['verify'] }
  }
}

function encode(value: unknown): string {
  return Buffer.from(JSON.stringify(value), 'utf8').toString('base64url')
}

function jwt(
  algorithm: AllowedOidcAlgorithm,
  kid: string,
  privateKey: KeyObject,
  claims: Record<string, unknown>,
  header: Record<string, unknown> = {}
): string {
  const signingInput = `${encode({ typ: 'JWT', alg: algorithm, kid, ...header })}.${encode(claims)}`
  const signature = algorithm === 'RS256'
    ? sign('RSA-SHA256', Buffer.from(signingInput, 'ascii'), privateKey)
    : sign('SHA256', Buffer.from(signingInput, 'ascii'), { key: privateKey, dsaEncoding: 'ieee-p1363' })
  return `${signingInput}.${signature.toString('base64url')}`
}

function claims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    iss: 'https://identity.phoenix.example.test/',
    aud: 'phoenix-canonical-integration',
    sub: 'synthetic-subject-001',
    nbf: nowSeconds - 10,
    exp: nowSeconds + 300,
    ...overrides
  }
}

function config(overrides: Partial<OidcJwtVerifierConfig> = {}): OidcJwtVerifierConfig {
  return {
    issuer: 'https://identity.phoenix.example.test/',
    audience: 'phoenix-canonical-integration',
    jwksUri: 'https://identity.phoenix.example.test/.well-known/jwks.json',
    allowedAlgorithms: ['RS256', 'ES256'],
    tokenMaxTtlSeconds: 900,
    clockSkewSeconds: 60,
    jwksCacheSeconds: 3600,
    unknownKidRefreshRateLimitSeconds: 60,
    ...overrides
  }
}

function jwksFetch(sequence: JsonWebKey[][]): { fetch: typeof fetch; calls: () => number } {
  let count = 0
  const implementation = async (): Promise<Response> => {
    const index = Math.min(count, sequence.length - 1)
    count += 1
    return new Response(JSON.stringify({ keys: sequence[index] ?? [] }), {
      status: 200,
      headers: { 'Content-Type': 'application/jwk-set+json' }
    })
  }
  return { fetch: implementation as typeof fetch, calls: () => count }
}

function isCode(code: string): (error: unknown) => boolean {
  return (error) => error instanceof AppError && error.code === code
}

test('RS256 and ES256 tokens pass exact issuer, audience, lifetime and JWKS verification', async () => {
  const rsa = keyPair('RS256', 'rsa-2027-01')
  const ec = keyPair('ES256', 'ec-2027-01')
  const remote = jwksFetch([[rsa.jwk, ec.jwk]])
  const verifier = new OidcJwtVerifier(config(), remote.fetch, () => nowMs)

  const rsaIdentity = await verifier.verify(jwt('RS256', 'rsa-2027-01', rsa.privateKey, claims()))
  assert.deepEqual(rsaIdentity, {
    issuer: 'https://identity.phoenix.example.test/',
    subject: 'synthetic-subject-001',
    audience: 'phoenix-canonical-integration',
    expiresAt: nowSeconds + 300,
    notBefore: nowSeconds - 10,
    keyId: 'rsa-2027-01',
    algorithm: 'RS256'
  })
  const ecIdentity = await verifier.verify(jwt('ES256', 'ec-2027-01', ec.privateKey, claims({ sub: 'synthetic-subject-002' })))
  assert.equal(ecIdentity.subject, 'synthetic-subject-002')
  assert.equal(remote.calls(), 1, 'fresh JWKS cache is reused')
})

test('forbidden algorithms, injected key headers and tampered signatures are rejected', async () => {
  const rsa = keyPair('RS256', 'rsa-guard')
  const remote = jwksFetch([[rsa.jwk]])
  const verifier = new OidcJwtVerifier(config(), remote.fetch, () => nowMs)
  const valid = jwt('RS256', 'rsa-guard', rsa.privateKey, claims())
  const [header, payload, signature] = valid.split('.') as [string, string, string]
  await assert.rejects(verifier.verify(`${encode({ alg: 'none', kid: 'rsa-guard' })}.${payload}.x`), isCode('OIDC_TOKEN_INVALID'))
  await assert.rejects(verifier.verify(`${encode({ alg: 'HS256', kid: 'rsa-guard' })}.${payload}.x`), isCode('OIDC_TOKEN_INVALID'))
  await assert.rejects(verifier.verify(jwt('RS256', 'rsa-guard', rsa.privateKey, claims(), { jku: 'https://attacker.invalid/jwks' })),
    isCode('OIDC_TOKEN_INVALID'))
  await assert.rejects(verifier.verify(jwt('RS256', 'rsa-guard', rsa.privateKey, claims(), { crit: ['b64'], b64: false })),
    isCode('OIDC_TOKEN_INVALID'))
  const changed = `${header}.${encode({ ...claims(), sub: 'tampered' })}.${signature}`
  await assert.rejects(verifier.verify(changed), isCode('OIDC_TOKEN_INVALID'))
})

test('claim mismatches, expiry, future nbf and excessive token lifetime are rejected', async () => {
  const rsa = keyPair('RS256', 'rsa-claims')
  const verifier = new OidcJwtVerifier(config(), jwksFetch([[rsa.jwk]]).fetch, () => nowMs)
  for (const badClaims of [
    claims({ iss: 'https://wrong.example.test/' }),
    claims({ aud: 'wrong-audience' }),
    claims({ aud: ['phoenix-canonical-integration', 'other-audience'] }),
    claims({ sub: '' }),
    claims({ exp: nowSeconds - 61 }),
    claims({ nbf: nowSeconds + 61 }),
    claims({ nbf: nowSeconds, exp: nowSeconds + 901 })
  ]) {
    await assert.rejects(verifier.verify(jwt('RS256', 'rsa-claims', rsa.privateKey, badClaims)), isCode('OIDC_TOKEN_INVALID'))
  }
})

test('unknown kid performs one rate-limited refresh and then fails closed', async () => {
  const oldKey = keyPair('RS256', 'old-key')
  const newKey = keyPair('RS256', 'new-key')
  const unknownKey = keyPair('RS256', 'unknown-key')
  const remote = jwksFetch([[oldKey.jwk], [newKey.jwk]])
  const verifier = new OidcJwtVerifier(config(), remote.fetch, () => nowMs)

  await verifier.verify(jwt('RS256', 'old-key', oldKey.privateKey, claims()))
  await verifier.verify(jwt('RS256', 'new-key', newKey.privateKey, claims()))
  assert.equal(remote.calls(), 2, 'unknown cached kid refreshes JWKS exactly once')
  await assert.rejects(verifier.verify(jwt('RS256', 'unknown-key', unknownKey.privateKey, claims())),
    isCode('OIDC_TOKEN_INVALID'))
  assert.equal(remote.calls(), 2, 'rate limit blocks another unknown-kid refresh')
})

test('JWKS network, media type and shape failures deny verification', async () => {
  const rsa = keyPair('RS256', 'rsa-jwks')
  const token = jwt('RS256', 'rsa-jwks', rsa.privateKey, claims())
  const unavailable = new OidcJwtVerifier(config(), (async () => new Response('', { status: 503 })) as typeof fetch, () => nowMs)
  await assert.rejects(unavailable.verify(token), isCode('OIDC_JWKS_UNAVAILABLE'))
  const wrongType = new OidcJwtVerifier(config(), (async () => new Response('{}', {
    status: 200, headers: { 'Content-Type': 'text/plain' }
  })) as typeof fetch, () => nowMs)
  await assert.rejects(wrongType.verify(token), isCode('OIDC_JWKS_UNAVAILABLE'))
  const wrongShape = new OidcJwtVerifier(config(), (async () => new Response('{"keys":"bad"}', {
    status: 200, headers: { 'Content-Type': 'application/json' }
  })) as typeof fetch, () => nowMs)
  await assert.rejects(wrongShape.verify(token), isCode('OIDC_JWKS_UNAVAILABLE'))
})

test('configuration is disabled by default and fails closed when enabled facts are incomplete or unsafe', () => {
  assert.equal(loadOidcJwtVerifierConfig({}), null)
  assert.throws(() => loadOidcJwtVerifierConfig({ CANONICAL_OIDC_ENABLED: 'true' }), isCode('OIDC_CONFIG_INVALID'))
  assert.throws(() => new OidcJwtVerifier(config({ issuer: 'http://identity.invalid/' })), isCode('OIDC_CONFIG_INVALID'))
  assert.throws(() => new OidcJwtVerifier(config({ issuer: 'https://identity.example.test/?tenant=1' })),
    isCode('OIDC_CONFIG_INVALID'))
  assert.throws(() => new OidcJwtVerifier(config({ allowedAlgorithms: ['RS256', 'RS256'] })), isCode('OIDC_CONFIG_INVALID'))
  assert.throws(() => new OidcJwtVerifier(config({ tokenMaxTtlSeconds: 901 })), isCode('OIDC_CONFIG_INVALID'))
  const loaded = loadOidcJwtVerifierConfig({
    CANONICAL_OIDC_ENABLED: 'true',
    CANONICAL_OIDC_ISSUER: 'https://identity.phoenix.example.test/',
    CANONICAL_OIDC_AUDIENCE: 'phoenix-canonical-integration',
    CANONICAL_OIDC_JWKS_URI: 'https://identity.phoenix.example.test/.well-known/jwks.json'
  })
  assert.equal(loaded?.tokenMaxTtlSeconds, 900)
  assert.deepEqual(loaded?.allowedAlgorithms, ['RS256', 'ES256'])
})
