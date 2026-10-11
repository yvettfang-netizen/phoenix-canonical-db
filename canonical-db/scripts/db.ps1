param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'health', 'migrate', 'reset-test', 'test', 'backup', 'restore-test')]
    [string]$Action,
    [ValidateSet('16', '17')][string]$Version = '16',
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$envFile = Join-Path $root '.env'
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

switch ($Action) {
    'init' {
        Start-Database
        Migrate $devDb
    }
    'health' {
        Invoke-Docker ($compose + @('exec', '-T', $service, 'pg_isready', '-U', 'phoenix_bootstrap', '-d', $devDb))
    }
    'migrate' { Migrate $devDb }
    'reset-test' {
        Start-Database
        Reset-TestDatabase $testDb
    }
    'test' {
        Start-Database
        Reset-TestDatabase $testDb
        Migrate $testDb
        Migrate $testDb
        $sql = [IO.File]::ReadAllText((Join-Path $root 'tests/foundation.sql'))
        Invoke-Psql $testDb $sql | Out-Null
        Write-Output "PASS PostgreSQL $Version foundation and repeat migration"
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
