param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('16', '17')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$canonicalRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$serverRoot = Join-Path $repoRoot 'Phoenix Compass\education compass\server'
$migrationRoot = Join-Path $canonicalRoot 'migrations\canonical'
$testRoot = Join-Path $canonicalRoot 'tests'
$images = @{
    '16' = 'postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d'
    '17' = 'postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
}
$runId = [guid]::NewGuid().ToString('N')
$container = "phoenix-v126-pg${Version}-$($runId.Substring(0, 12))"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "phoenix-v126-$runId"
$null = New-Item -ItemType Directory -Path $tempRoot

function New-HexSecret {
    $bytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToHexString($bytes).ToLowerInvariant()
}

function Invoke-Docker([string[]]$Arguments) {
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed with exit code $LASTEXITCODE" }
}

$bootstrapPassword = New-HexSecret
$appPassword = New-HexSecret
$binderPassword = New-HexSecret
$envFile = Join-Path $tempRoot 'postgres.env'
$rolesSql = Join-Path $tempRoot 'roles.sql'
$seedSql = Join-Path $tempRoot 'seed.sql'
[IO.File]::WriteAllText($envFile, "POSTGRES_PASSWORD=$bootstrapPassword`n")
[IO.File]::WriteAllText($rolesSql, @"
CREATE ROLE phoenix_canonical_app_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$appPassword';
CREATE ROLE phoenix_canonical_binder_runtime LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$binderPassword';
GRANT phoenix_canonical_app TO phoenix_canonical_app_runtime WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_binder_runtime WITH INHERIT TRUE, SET FALSE;
"@)
[IO.File]::WriteAllText($seedSql, @'
INSERT INTO core.families(family_id,display_name)
VALUES('018f0000-0000-7000-8000-000000000001','Synthetic V1.26 Canonical Family');
INSERT INTO core.people(person_id,display_name)
VALUES('018f0000-0000-7000-8000-000000002601','Synthetic V1.26 Actor');
INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from)
VALUES(
  '018f0000-0000-7000-8000-000000002602',
  '018f0000-0000-7000-8000-000000000001',
  '018f0000-0000-7000-8000-000000002601','PRIMARY',clock_timestamp()-interval '1 minute'
);
INSERT INTO auth.principals(principal_id,person_id,principal_kind,status)
VALUES(
  '018f0000-0000-7000-8000-000000002603',
  '018f0000-0000-7000-8000-000000002601','FAMILY','ACTIVE'
);
INSERT INTO auth.external_identities(
  external_identity_id,issuer,subject,principal_id,status,created_by_principal_id
) VALUES(
  '018f0000-0000-7000-8000-000000002604',
  'https://api.phoenix.synthetic.test/canonical-identity',
  'usr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '018f0000-0000-7000-8000-000000002603','ACTIVE',
  '018f0000-0000-7000-8000-000000002603'
);
INSERT INTO integration.legacy_id_mappings(
  mapping_id,source_system,entity_kind,legacy_id,canonical_id,
  mapping_status,evidence_ref,decided_by,decided_at
) VALUES(
  '018f0000-0000-7000-8000-000000002605','PHOENIX_FAMILY_OS','FAMILY',
  'fam_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  '018f0000-0000-7000-8000-000000000001',
  'VERIFIED','synthetic/v1.26/e2e',
  '018f0000-0000-7000-8000-000000002601',clock_timestamp()
);
'@)

$previous = @{}
foreach ($name in @('CANONICAL_E2E_PORT', 'CANONICAL_E2E_APP_PASSWORD', 'CANONICAL_E2E_BINDER_PASSWORD')) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    Invoke-Docker @(
        'run', '-d', '--name', $container,
        '--env-file', $envFile,
        '-e', 'POSTGRES_DB=phoenix_canonical_dev',
        '-e', 'POSTGRES_USER=phoenix_bootstrap',
        '-e', 'POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256',
        '-p', '127.0.0.1::5432',
        '-v', "${migrationRoot}:/opt/migrations:ro",
        '-v', "${testRoot}:/opt/tests:ro",
        $images[$Version]
    )
    $ready = $false
    for ($attempt = 1; $attempt -le 40; $attempt++) {
        & docker exec $container pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'Ephemeral PostgreSQL did not become ready.' }

    Invoke-Docker @('exec', '-e', 'F10_EXPECTED_MIGRATION_COUNT=25', $container, 'bash', '/opt/tests/f10_ephemeral_init.sh')
    Invoke-Docker @('cp', $rolesSql, "${container}:/tmp/v126-roles.sql")
    Invoke-Docker @('cp', $seedSql, "${container}:/tmp/v126-seed.sql")
    Invoke-Docker @('exec', '-e', 'PGPASSFILE=/tmp/f10-bootstrap.pgpass', $container,
        'psql', '-X', '-h', '127.0.0.1', '-U', 'phoenix_bootstrap', '-d', 'phoenix_canonical_dev',
        '-v', 'ON_ERROR_STOP=1', '-f', '/tmp/v126-roles.sql')
    Invoke-Docker @('exec', '-e', 'PGPASSFILE=/tmp/f10-bootstrap.pgpass', $container,
        'psql', '-X', '-h', '127.0.0.1', '-U', 'phoenix_bootstrap', '-d', 'phoenix_canonical_dev',
        '-v', 'ON_ERROR_STOP=1', '-f', '/tmp/v126-seed.sql')

    $published = (& docker port $container '5432/tcp').Trim()
    if ($LASTEXITCODE -ne 0 -or $published -notmatch '127\.0\.0\.1:(\d+)$') {
        throw "Unexpected loopback port binding: $published"
    }
    [Environment]::SetEnvironmentVariable('CANONICAL_E2E_PORT', $Matches[1], 'Process')
    [Environment]::SetEnvironmentVariable('CANONICAL_E2E_APP_PASSWORD', $appPassword, 'Process')
    [Environment]::SetEnvironmentVariable('CANONICAL_E2E_BINDER_PASSWORD', $binderPassword, 'Process')

    Push-Location $serverRoot
    try {
        & npm.cmd run test:canonical-http-e2e
        if ($LASTEXITCODE -ne 0) { throw "Canonical HTTP E2E failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }

    Invoke-Docker @('exec', '-e', 'PGPASSFILE=/tmp/f10-bootstrap.pgpass', $container,
        'psql', '-X', '-At', '-h', '127.0.0.1', '-U', 'phoenix_bootstrap', '-d', 'phoenix_canonical_dev',
        '-v', 'ON_ERROR_STOP=1', '-c',
        "SELECT 'session_contexts='||count(*) FROM auth.session_contexts; SELECT 'unredeemed_tickets='||count(*) FROM auth.context_exchange_tickets;")
    Write-Output "PASS PG$Version isolated synthetic HTTP -> broker -> binder -> app pool -> RLS E2E"
} finally {
    foreach ($entry in $previous.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    & docker rm -f $container *> $null
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
