param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'health', 'migrate', 'provision-local-roles', 'reset-test', 'test', 'probe', 'backup', 'restore-test')]
    [string]$Action,
    [ValidateSet('16', '17')][string]$Version = '16',
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$envFile = Join-Path $root '.env'
$localRolesFile = Join-Path $root '.local-roles.env'
$service = if ($Version -eq '16') { 'pg16' } else { 'pg17' }
$testDb = "phoenix_canonical_test_$Version"
$restoreDb = "phoenix_canonical_restore_test_$Version"
$devDb = 'phoenix_canonical_dev'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI is unavailable. Install/start Docker Desktop before running database actions.'
}
if (-not (Test-Path -LiteralPath $envFile)) {
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $password = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    [IO.File]::WriteAllText($envFile, "PHOENIX_DB_BOOTSTRAP_PASSWORD=$password`n")
}
$compose = @('compose', '--env-file', $envFile, '-f', (Join-Path $root 'compose.yaml'))
if ($Version -eq '17') { $compose += @('--profile', 'compat') }

function Invoke-Docker([string[]]$arguments) {
    & docker @arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed with exit code $LASTEXITCODE" }
}

function Invoke-Psql([string]$database, [string]$sql) {
    $result = $sql | & docker @compose exec -T $service psql -X -U phoenix_bootstrap -d $database -v ON_ERROR_STOP=1 -At -f -
    if ($LASTEXITCODE -ne 0) { throw "psql failed for database $database" }
    return $result
}

function Start-Database {
    Invoke-Docker ($compose + @('up', '-d', '--wait', $service))
}

function New-LocalSecret {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

function Provision-LocalRoles {
    if (-not (Test-Path -LiteralPath $localRolesFile)) {
        $content = @(
            "PHOENIX_LOCAL_MIGRATOR_PASSWORD=$(New-LocalSecret)"
            "PHOENIX_LOCAL_APP_PASSWORD=$(New-LocalSecret)"
            "PHOENIX_LOCAL_READER_PASSWORD=$(New-LocalSecret)"
        ) -join "`n"
        [IO.File]::WriteAllText($localRolesFile, "$content`n")
    }
    $secrets = @{}
    foreach ($line in [IO.File]::ReadAllLines($localRolesFile)) {
        if ($line -match '^(PHOENIX_LOCAL_(?:MIGRATOR|APP|READER)_PASSWORD)=([0-9a-f]{64})$') {
            $secrets[$Matches[1]] = $Matches[2]
        }
    }
    foreach ($key in @('PHOENIX_LOCAL_MIGRATOR_PASSWORD', 'PHOENIX_LOCAL_APP_PASSWORD', 'PHOENIX_LOCAL_READER_PASSWORD')) {
        if (-not $secrets.ContainsKey($key)) { throw "Missing or invalid local-only secret: $key" }
    }
    $sql = @'
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_migrator_local') THEN
    CREATE ROLE phoenix_canonical_migrator_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__MIGRATOR__';
  ELSE
    ALTER ROLE phoenix_canonical_migrator_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__MIGRATOR__';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_app_local') THEN
    CREATE ROLE phoenix_canonical_app_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__APP__';
  ELSE
    ALTER ROLE phoenix_canonical_app_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__APP__';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_reader_local') THEN
    CREATE ROLE phoenix_canonical_reader_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__READER__';
  ELSE
    ALTER ROLE phoenix_canonical_reader_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__READER__';
  END IF;
END
$roles$;
GRANT phoenix_canonical_migrator TO phoenix_canonical_migrator_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_app TO phoenix_canonical_app_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_reader TO phoenix_canonical_reader_local WITH INHERIT TRUE, SET FALSE;
'@
    $sql = $sql.Replace('__MIGRATOR__', $secrets['PHOENIX_LOCAL_MIGRATOR_PASSWORD']).Replace('__APP__', $secrets['PHOENIX_LOCAL_APP_PASSWORD']).Replace('__READER__', $secrets['PHOENIX_LOCAL_READER_PASSWORD'])
    Invoke-Psql $devDb $sql | Out-Null
    $checks = @(
        @{ Name = 'phoenix_canonical_migrator_local'; Password = $secrets['PHOENIX_LOCAL_MIGRATOR_PASSWORD']; Sql = "SELECT has_schema_privilege(current_user,'core','CREATE') AND has_schema_privilege(current_user,'education','CREATE') AND has_schema_privilege(current_user,'identity','CREATE') AND has_table_privilege(current_user,'canonical_migrations.applied','INSERT') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user);" }
        @{ Name = 'phoenix_canonical_app_local'; Password = $secrets['PHOENIX_LOCAL_APP_PASSWORD']; Sql = "SELECT has_schema_privilege(current_user,'education','USAGE') AND has_schema_privilege(current_user,'identity','USAGE') AND NOT has_schema_privilege(current_user,'education','CREATE') AND NOT has_schema_privilege(current_user,'canonical_migrations','USAGE') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user);" }
        @{ Name = 'phoenix_canonical_reader_local'; Password = $secrets['PHOENIX_LOCAL_READER_PASSWORD']; Sql = "SELECT has_schema_privilege(current_user,'education','USAGE') AND has_schema_privilege(current_user,'identity','USAGE') AND NOT has_schema_privilege(current_user,'identity','CREATE') AND NOT has_schema_privilege(current_user,'canonical_migrations','USAGE') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user);" }
    )
    foreach ($check in $checks) {
        $result = & docker @compose exec -T -e "PGPASSWORD=$($check.Password)" $service psql -X -h 127.0.0.1 -U $check.Name -d $devDb -v ON_ERROR_STOP=1 -At -c $check.Sql
        if ($LASTEXITCODE -ne 0 -or (@($result) -join '').Trim() -ne 't') { throw "Local login or privilege test failed: $($check.Name)" }
    }
    Write-Output "PASS local-only login and least-privilege checks on PostgreSQL $Version"
}

function Migrate([string]$database) {
    $files = Get-ChildItem -LiteralPath (Join-Path $root 'migrations/canonical') -Filter '*.sql' -File | Sort-Object Name
    foreach ($file in $files) {
        if ($file.Name -notmatch '^[0-9]{4}_[a-z0-9_]+\.sql$') { throw "Invalid migration name: $($file.Name)" }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $name = $file.Name
        $ledgerExists = Invoke-Psql $database "SELECT to_regclass('canonical_migrations.applied') IS NOT NULL;"
        $existing = if ((@($ledgerExists) -join '').Trim() -eq 't') {
            Invoke-Psql $database "SELECT sha256 FROM canonical_migrations.applied WHERE migration_name = '$name';"
        } else { $null }
        if ($existing) {
            if ((@($existing) -join '').Trim() -ne $hash) { throw "Migration checksum changed: $name" }
            Write-Output "SKIP $database $name checksum verified"
            continue
        }
        $sql = [IO.File]::ReadAllText($file.FullName)
        Invoke-Psql $database $sql | Out-Null
        Invoke-Psql $database "INSERT INTO canonical_migrations.applied(migration_name,sha256) VALUES ('$name','$hash') ON CONFLICT (migration_name) DO NOTHING;" | Out-Null
        Write-Output "APPLIED $database $name"
    }
}

function Reset-TestDatabase([string]$database) {
    if ($database -notin @('phoenix_canonical_test_16', 'phoenix_canonical_test_17', 'phoenix_canonical_restore_test_16', 'phoenix_canonical_restore_test_17')) {
        throw 'Refusing to reset a database outside the exact synthetic test allowlist.'
    }
    Invoke-Psql 'postgres' "DROP DATABASE IF EXISTS $database WITH (FORCE);" | Out-Null
    Invoke-Psql 'postgres' "CREATE DATABASE $database;" | Out-Null
    Write-Output "RESET $database"
}

function Invoke-SyntheticProbes([string]$database) {
    foreach ($name in @('foundation.sql', 'rls_probe.sql', 'docs_probe.sql', 'contract_neutral_probe.sql')) {
        $sql = [IO.File]::ReadAllText((Join-Path $root "tests/$name"))
        Invoke-Psql $database $sql | Out-Null
    }
    $probeGone = Invoke-Psql $database "SELECT to_regnamespace('acceptance_probe') IS NULL;"
    if ((@($probeGone) -join '').Trim() -ne 't') { throw 'Disposable acceptance probe left schema behind.' }
}

switch ($Action) {
    'init' {
        Start-Database
        Migrate $devDb
    }
    'health' {
        Invoke-Docker ($compose + @('exec', '-T', $service, 'pg_isready', '-U', 'phoenix_bootstrap', '-d', $devDb))
    }
    'migrate' { Migrate $devDb }
    'provision-local-roles' {
        Start-Database
        Migrate $devDb
        Provision-LocalRoles
    }
    'reset-test' {
        Start-Database
        Reset-TestDatabase $testDb
    }
    'test' {
        Start-Database
        Reset-TestDatabase $testDb
        Migrate $testDb
        Migrate $testDb
        Invoke-SyntheticProbes $testDb
        Write-Output "PASS PostgreSQL $Version foundation, repeat migration, synthetic RLS, docs and contract-neutral probes"
    }
    'probe' {
        Start-Database
        Invoke-SyntheticProbes $devDb
        Write-Output "PASS PostgreSQL $Version nondestructive transactional synthetic probes"
    }
    'backup' {
        Start-Database
        Migrate $devDb
        $backupDir = Join-Path $root 'backups'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $destination = Join-Path $backupDir "phoenix_canonical_dev_pg${Version}_$stamp.dump"
        Invoke-Docker ($compose + @('exec', '-T', $service, 'pg_dump', '-U', 'phoenix_bootstrap', '-d', $devDb, '-Fc', '-f', '/tmp/phoenix_canonical_backup.dump'))
        $containerId = (& docker @compose ps -q $service).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $containerId) { throw 'Could not identify test container for backup copy.' }
        Invoke-Docker @('cp', "${containerId}:/tmp/phoenix_canonical_backup.dump", $destination)
        Write-Output "BACKUP $destination"
    }
    'restore-test' {
        if (-not $BackupPath) { throw 'Pass -BackupPath to an existing local test backup.' }
        $resolvedBackup = (Resolve-Path -LiteralPath $BackupPath).Path
        Start-Database
        Reset-TestDatabase $restoreDb
        $containerId = (& docker @compose ps -q $service).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $containerId) { throw 'Could not identify test container for restore copy.' }
        Invoke-Docker @('cp', $resolvedBackup, "${containerId}:/tmp/phoenix_canonical_restore.dump")
        Invoke-Docker ($compose + @('exec', '-T', $service, 'pg_restore', '-U', 'phoenix_bootstrap', '-d', $restoreDb, '--no-owner', '--exit-on-error', '/tmp/phoenix_canonical_restore.dump'))
        $sql = [IO.File]::ReadAllText((Join-Path $root 'tests/foundation.sql'))
        Invoke-Psql $restoreDb $sql | Out-Null
        Write-Output "PASS restore into $restoreDb"
    }
}
