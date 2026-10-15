param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'health', 'test', 'backup', 'restore-test', 'stop')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [ValidateSet('16', '17')][string]$Version,
    [Parameter(Mandatory = $true)][string]$BinPath,
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$bin = (Resolve-Path -LiteralPath $BinPath).Path
$runtime = Join-Path $root "runtime/native_$Version"
$data = Join-Path $runtime 'data'
$passwordFile = Join-Path $runtime 'bootstrap-password.txt'
$pgpassFile = Join-Path $runtime 'bootstrap.pgpass'
$port = if ($Version -eq '16') { 55416 } else { 55417 }
$devDb = 'phoenix_canonical_dev'
$testDb = "phoenix_canonical_test_$Version"
$restoreDb = "phoenix_canonical_restore_test_$Version"
foreach ($name in @('initdb','pg_ctl','psql','createdb','dropdb','pg_dump','pg_restore','pg_isready')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bin "$name.exe"))) { throw "Missing PostgreSQL binary: $name.exe" }
}
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
if (-not (Test-Path -LiteralPath $passwordFile)) {
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    [IO.File]::WriteAllText($passwordFile, ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant() + "`n")
}
$bootstrapPassword = [IO.File]::ReadAllText($passwordFile).Trim()
[IO.File]::WriteAllText($pgpassFile, "*:*:*:phoenix_bootstrap:$bootstrapPassword`n")
$env:PGPASSFILE = $pgpassFile

function Invoke-Pg([string]$tool, [string[]]$arguments) {
    & (Join-Path $bin "$tool.exe") @arguments
    if ($LASTEXITCODE -ne 0) { throw "$tool failed with exit code $LASTEXITCODE" }
}

function Invoke-Psql([string]$database, [string]$sql) {
    $result = $sql | & (Join-Path $bin 'psql.exe') -X -h 127.0.0.1 -p $port -U phoenix_bootstrap -d $database -v ON_ERROR_STOP=1 -At -f -
    if ($LASTEXITCODE -ne 0) { throw "psql failed for database $database" }
    return $result
}

function Start-Native {
    if (-not (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))) {
        Invoke-Pg 'initdb' @('-D', $data, '-U', 'phoenix_bootstrap', '--encoding=UTF8', '--auth-host=scram-sha-256', '--auth-local=scram-sha-256', "--pwfile=$passwordFile", '--no-instructions')
        [IO.File]::AppendAllText((Join-Path $data 'postgresql.conf'), "`nlisten_addresses = '127.0.0.1'`nport = $port`n")
    }
    & (Join-Path $bin 'pg_ctl.exe') -D $data status *> $null
    if ($LASTEXITCODE -ne 0) {
        Invoke-Pg 'pg_ctl' @('-D', $data, '-l', (Join-Path $runtime 'server.log'), '-w', 'start')
    }
    Invoke-Pg 'pg_isready' @('-h', '127.0.0.1', '-p', "$port", '-U', 'phoenix_bootstrap', '-d', 'postgres')
    $actualData = (@(Invoke-Psql 'postgres' 'SHOW data_directory;') -join '').Trim().Replace('\','/').TrimEnd('/')
    if ($actualData -ne $data.Replace('\','/').TrimEnd('/')) { throw "Connected to unexpected PostgreSQL data directory: $actualData" }
    $exists = (@(Invoke-Psql 'postgres' "SELECT 1 FROM pg_database WHERE datname = '$devDb';") -join '').Trim()
    if (-not $exists) {
        Invoke-Pg 'createdb' @('-h', '127.0.0.1', '-p', "$port", '-U', 'phoenix_bootstrap', $devDb)
    }
}

function Migrate([string]$database) {
    $files = Get-ChildItem -LiteralPath (Join-Path $root 'migrations/canonical') -Filter '*.sql' -File | Sort-Object Name
    foreach ($file in $files) {
        if ($file.Name -notmatch '^[0-9]{4}_[a-z0-9_]+\.sql$') { throw "Invalid migration name: $($file.Name)" }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $name = $file.Name
        $ledgerExists = (@(Invoke-Psql $database "SELECT to_regclass('canonical_migrations.applied') IS NOT NULL;") -join '').Trim()
        $existing = if ($ledgerExists -eq 't') { Invoke-Psql $database "SELECT sha256 FROM canonical_migrations.applied WHERE migration_name = '$name';" } else { $null }
        if ($existing) {
            if ((@($existing) -join '').Trim() -ne $hash) { throw "Migration checksum changed: $name" }
            Write-Output "SKIP $database $name checksum verified"
            continue
        }
        Invoke-Psql $database ([IO.File]::ReadAllText($file.FullName)) | Out-Null
        Invoke-Psql $database "INSERT INTO canonical_migrations.applied(migration_name,sha256) VALUES ('$name','$hash') ON CONFLICT (migration_name) DO NOTHING;" | Out-Null
        Write-Output "APPLIED $database $name"
    }
}

function Reset-TestDatabase([string]$database) {
    if ($database -notin @('phoenix_canonical_test_16','phoenix_canonical_test_17','phoenix_canonical_restore_test_16','phoenix_canonical_restore_test_17')) {
        throw 'Refusing to reset a database outside the exact synthetic test allowlist.'
    }
    Invoke-Pg 'dropdb' @('-h', '127.0.0.1', '-p', "$port", '-U', 'phoenix_bootstrap', '--if-exists', '--force', $database)
    Invoke-Pg 'createdb' @('-h', '127.0.0.1', '-p', "$port", '-U', 'phoenix_bootstrap', $database)
}

try {
    switch ($Action) {
        'stop' {
            if (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION')) { Invoke-Pg 'pg_ctl' @('-D', $data, '-m', 'fast', '-w', 'stop') }
        }
        'health' {
            Start-Native
            Write-Output "PASS PostgreSQL $Version native localhost health"
        }
        'init' {
            Start-Native
            Migrate $devDb
        }
        'test' {
            Start-Native
            Reset-TestDatabase $testDb
            Migrate $testDb
            Migrate $testDb
            Invoke-Psql $testDb ([IO.File]::ReadAllText((Join-Path $root 'tests/foundation.sql'))) | Out-Null
            Write-Output "PASS PostgreSQL $Version native foundation and repeat migration"
        }
        'backup' {
            Start-Native
            Migrate $devDb
            $backupDir = Join-Path $root 'backups'
            New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
            $destination = Join-Path $backupDir "phoenix_canonical_dev_native_pg${Version}_$(Get-Date -Format 'yyyyMMdd-HHmmss').dump"
            Invoke-Pg 'pg_dump' @('-h', '127.0.0.1', '-p', "$port", '-U', 'phoenix_bootstrap', '-d', $devDb, '-Fc', '-f', $destination)
            Write-Output "BACKUP $destination"
        }
        'restore-test' {
            if (-not $BackupPath) { throw 'Pass -BackupPath to a local synthetic backup.' }
            $resolvedBackup = (Resolve-Path -LiteralPath $BackupPath).Path
            $backupRoot = (Resolve-Path -LiteralPath (Join-Path $root 'backups')).Path
            if (-not $resolvedBackup.StartsWith($backupRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Backup must be inside the ignored canonical-db/backups directory.'
            }
            Start-Native
            Reset-TestDatabase $restoreDb
            Invoke-Pg 'pg_restore' @('-h', '127.0.0.1', '-p', "$port", '-U', 'phoenix_bootstrap', '-d', $restoreDb, '--no-owner', '--exit-on-error', $resolvedBackup)
            Invoke-Psql $restoreDb ([IO.File]::ReadAllText((Join-Path $root 'tests/foundation.sql'))) | Out-Null
            Write-Output "PASS PostgreSQL $Version native restore into $restoreDb"
        }
    }
} finally {
    Remove-Item Env:PGPASSFILE -ErrorAction SilentlyContinue
}
