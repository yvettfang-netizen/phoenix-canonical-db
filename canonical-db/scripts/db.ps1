param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'health', 'migrate', 'provision-local-roles', 'reset-test', 'test', 'probe', 'audit-migration', 'backup', 'restore-test', 'audit-backup')]
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
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $password = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    [IO.File]::WriteAllText($envFile, "PHOENIX_DB_BOOTSTRAP_PASSWORD=$password`n")
}
$compose = @('compose', '--env-file', $envFile, '-f', (Join-Path $root 'compose.yaml'))
if ($Version -eq '17') { $compose += @('--profile', 'compat') }
$containerPgpass = '/tmp/phoenix-canonical-db.pgpass'
# Local .env files created before 2026-10-15 hold a 48-hex secret; new ones hold 64 hex. Accept both.
# Cast to [string]: an empty pipeline yields an empty collection, which -notmatch would filter to a falsy
# value and silently skip the guard, leaving an empty password in the container pgpass file.
$bootstrapPassword = [string]((Get-Content -LiteralPath $envFile | Where-Object { $_ -match '^PHOENIX_DB_BOOTSTRAP_PASSWORD=([0-9a-f]{48}|[0-9a-f]{64})$' } | Select-Object -First 1) -replace '^PHOENIX_DB_BOOTSTRAP_PASSWORD=', '')
if ($bootstrapPassword -notmatch '^([0-9a-f]{48}|[0-9a-f]{64})$') { throw 'Local bootstrap secret is missing or invalid.' }

function Invoke-Docker([string[]]$arguments) {
    & docker @arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed with exit code $LASTEXITCODE" }
}

function Invoke-Psql([string]$database, [string]$sql) {
    $result = $sql | & docker @compose exec -T -e "PGPASSFILE=$containerPgpass" $service psql -X -h 127.0.0.1 -U phoenix_bootstrap -d $database -v ON_ERROR_STOP=1 -At -f -
    if ($LASTEXITCODE -ne 0) { throw "psql failed for database $database" }
    return $result
}

function Start-Database {
    Invoke-Docker ($compose + @('up', '-d', '--wait', $service))
    $pgpassEntries = @{ phoenix_bootstrap = $bootstrapPassword }
    if (Test-Path -LiteralPath $localRolesFile) {
        $roleNames = @{
            PHOENIX_LOCAL_MIGRATOR_PASSWORD = 'phoenix_canonical_migrator_local'
            PHOENIX_LOCAL_APP_PASSWORD = 'phoenix_canonical_app_local'
            PHOENIX_LOCAL_READER_PASSWORD = 'phoenix_canonical_reader_local'
            PHOENIX_LOCAL_BINDER_PASSWORD = 'phoenix_canonical_context_binder_local'
            PHOENIX_LOCAL_BACKUP_PASSWORD = 'phoenix_canonical_backup_local'
        }
        foreach ($line in [IO.File]::ReadAllLines($localRolesFile)) {
            if ($line -match '^(PHOENIX_LOCAL_(?:MIGRATOR|APP|READER|BINDER|BACKUP)_PASSWORD)=(.*)$') {
                $key = $Matches[1]
                $secret = $Matches[2]
                if ($secret -notmatch '^[0-9a-f]{64}$') { throw "Invalid local-only secret: $key" }
                $pgpassEntries[$roleNames[$key]] = $secret
            }
        }
    }
    Set-ContainerPgpass $pgpassEntries
}

function Set-ContainerPgpass([hashtable]$entries) {
    $lines = foreach ($entry in $entries.GetEnumerator()) { "*:*:*:$($entry.Key):$($entry.Value)" }
    $content = ($lines -join "`n") + "`n"
    $content | & docker @compose exec -T $service sh -c "umask 077; cat > '$containerPgpass'; chmod 600 '$containerPgpass'"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install the container-local pgpass file.' }
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
            "PHOENIX_LOCAL_BINDER_PASSWORD=$(New-LocalSecret)"
        ) -join "`n"
        [IO.File]::WriteAllText($localRolesFile, "$content`n")
    }
    if (-not (Select-String -LiteralPath $localRolesFile -Pattern '^PHOENIX_LOCAL_BINDER_PASSWORD=[0-9a-f]{64}$' -Quiet)) {
        [IO.File]::AppendAllText($localRolesFile, "PHOENIX_LOCAL_BINDER_PASSWORD=$(New-LocalSecret)`n")
    }
    if (-not (Select-String -LiteralPath $localRolesFile -Pattern '^PHOENIX_LOCAL_BACKUP_PASSWORD=[0-9a-f]{64}$' -Quiet)) {
        [IO.File]::AppendAllText($localRolesFile, "PHOENIX_LOCAL_BACKUP_PASSWORD=$(New-LocalSecret)`n")
    }
    $secrets = @{}
    foreach ($line in [IO.File]::ReadAllLines($localRolesFile)) {
        if ($line -match '^(PHOENIX_LOCAL_(?:MIGRATOR|APP|READER|BINDER|BACKUP)_PASSWORD)=([0-9a-f]{64})$') {
            $secrets[$Matches[1]] = $Matches[2]
        }
    }
    foreach ($key in @('PHOENIX_LOCAL_MIGRATOR_PASSWORD', 'PHOENIX_LOCAL_APP_PASSWORD', 'PHOENIX_LOCAL_READER_PASSWORD', 'PHOENIX_LOCAL_BINDER_PASSWORD', 'PHOENIX_LOCAL_BACKUP_PASSWORD')) {
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
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_context_binder_local') THEN
    CREATE ROLE phoenix_canonical_context_binder_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__BINDER__';
  ELSE
    ALTER ROLE phoenix_canonical_context_binder_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '__BINDER__';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'phoenix_canonical_backup_local') THEN
    CREATE ROLE phoenix_canonical_backup_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '__BACKUP__';
  ELSE
    ALTER ROLE phoenix_canonical_backup_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '__BACKUP__';
  END IF;
END
$roles$;
GRANT phoenix_canonical_migrator TO phoenix_canonical_migrator_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_app TO phoenix_canonical_app_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_reader TO phoenix_canonical_reader_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_context_binder_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_backup_runtime TO phoenix_canonical_backup_local WITH INHERIT TRUE, SET FALSE;
'@
    $sql = $sql.Replace('__MIGRATOR__', $secrets['PHOENIX_LOCAL_MIGRATOR_PASSWORD']).Replace('__APP__', $secrets['PHOENIX_LOCAL_APP_PASSWORD']).Replace('__READER__', $secrets['PHOENIX_LOCAL_READER_PASSWORD']).Replace('__BINDER__', $secrets['PHOENIX_LOCAL_BINDER_PASSWORD']).Replace('__BACKUP__', $secrets['PHOENIX_LOCAL_BACKUP_PASSWORD'])
    Invoke-Psql $devDb $sql | Out-Null
    Set-ContainerPgpass @{ phoenix_bootstrap = $bootstrapPassword; phoenix_canonical_migrator_local = $secrets['PHOENIX_LOCAL_MIGRATOR_PASSWORD']; phoenix_canonical_app_local = $secrets['PHOENIX_LOCAL_APP_PASSWORD']; phoenix_canonical_reader_local = $secrets['PHOENIX_LOCAL_READER_PASSWORD']; phoenix_canonical_context_binder_local = $secrets['PHOENIX_LOCAL_BINDER_PASSWORD']; phoenix_canonical_backup_local = $secrets['PHOENIX_LOCAL_BACKUP_PASSWORD'] }
    $checks = @(
        @{ Name = 'phoenix_canonical_migrator_local'; Password = $secrets['PHOENIX_LOCAL_MIGRATOR_PASSWORD']; Sql = "SELECT has_schema_privilege(current_user,'core','CREATE') AND has_schema_privilege(current_user,'education','CREATE') AND has_schema_privilege(current_user,'identity','CREATE') AND has_table_privilege(current_user,'canonical_migrations.applied','INSERT') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user);" }
        @{ Name = 'phoenix_canonical_app_local'; Password = $secrets['PHOENIX_LOCAL_APP_PASSWORD']; Sql = "SELECT has_schema_privilege(current_user,'education','USAGE') AND has_schema_privilege(current_user,'identity','USAGE') AND NOT has_schema_privilege(current_user,'education','CREATE') AND NOT has_schema_privilege(current_user,'canonical_migrations','USAGE') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user);" }
        @{ Name = 'phoenix_canonical_reader_local'; Password = $secrets['PHOENIX_LOCAL_READER_PASSWORD']; Sql = "SELECT has_schema_privilege(current_user,'education','USAGE') AND has_schema_privilege(current_user,'identity','USAGE') AND NOT has_schema_privilege(current_user,'identity','CREATE') AND has_schema_privilege(current_user,'canonical_migrations','USAGE') AND has_table_privilege(current_user,'canonical_migrations.applied','SELECT') AND NOT has_schema_privilege(current_user,'canonical_migrations','CREATE') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user);" }
        @{ Name = 'phoenix_canonical_context_binder_local'; Password = $secrets['PHOENIX_LOCAL_BINDER_PASSWORD']; Sql = "SELECT NOT has_function_privilege(current_user,'auth.bind_context(uuid,uuid,uuid,text,timestamptz,uuid)','EXECUTE') AND has_function_privilege(current_user,'auth.issue_context_ticket(uuid,uuid,uuid,text,timestamptz,uuid,uuid)','EXECUTE') AND has_function_privilege(current_user,'auth.resolve_external_identity(text,text)','EXECUTE') AND NOT has_table_privilege(current_user,'auth.session_contexts','SELECT') AND NOT has_schema_privilege(current_user,'core','USAGE') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user);" }
    )
    foreach ($check in $checks) {
        $result = & docker @compose exec -T -e "PGPASSFILE=$containerPgpass" $service psql -X -h 127.0.0.1 -U $check.Name -d $devDb -v ON_ERROR_STOP=1 -At -c $check.Sql
        if ($LASTEXITCODE -ne 0 -or (@($result) -join '').Trim() -ne 't') { throw "Local login or privilege test failed: $($check.Name)" }
    }
    Write-Output "PASS local-only login and least-privilege checks on PostgreSQL $Version"
}

function Apply-Migration([string]$database, [IO.FileInfo]$file) {
    if ($file.Name -notmatch '^[0-9]{4}_[a-z0-9_]+\.sql$') { throw "Invalid migration name: $($file.Name)" }
    $sourceBytes = [IO.File]::ReadAllBytes($file.FullName)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($sourceBytes)).ToLowerInvariant()
    $name = $file.Name
    $ledgerExists = Invoke-Psql $database "SELECT to_regclass('canonical_migrations.applied') IS NOT NULL;"
    $existing = if ((@($ledgerExists) -join '').Trim() -eq 't') {
        Invoke-Psql $database "SELECT sha256 FROM canonical_migrations.applied WHERE migration_name = '$name';"
    } else { $null }
    if ($existing) {
        if ((@($existing) -join '').Trim() -ne $hash) { throw "Migration checksum changed: $name" }
        Write-Output "SKIP $database $name checksum verified"
        return
    }

    $source = [Text.UTF8Encoding]::new($false, $true).GetString($sourceBytes)
    $outerTransaction = [regex]::Match($source, '(?is)^\s*BEGIN\s*;\s*(.*?)\s*COMMIT\s*;\s*$')
    if (-not $outerTransaction.Success) { throw "Migration must have one outer BEGIN/COMMIT: $name" }
    $body = $outerTransaction.Groups[1].Value
    if ($body -match '(?im)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;') {
        throw "Nested transaction command in migration: $name"
    }
    $guard = if ((@($ledgerExists) -join '').Trim() -eq 't') {
        "DO `$guard`$ BEGIN IF EXISTS (SELECT 1 FROM canonical_migrations.applied WHERE migration_name = '$name') THEN RAISE EXCEPTION 'migration registered while waiting for lock: $name'; END IF; END `$guard`$;"
    } else { '' }
    $atomicSql = "BEGIN;`nSELECT pg_advisory_xact_lock(2202, 1);`n$guard`n$body`nINSERT INTO canonical_migrations.applied(migration_name,sha256) VALUES ('$name','$hash');`nCOMMIT;"
    Invoke-Psql $database $atomicSql | Out-Null
    Write-Output "APPLIED $database $name"
}

function Migrate([string]$database) {
    $files = Get-ChildItem -LiteralPath (Join-Path $root 'migrations/canonical') -Filter '*.sql' -File | Sort-Object Name
    foreach ($file in $files) { Apply-Migration $database $file }
}

function Assert-MigrationsApplied([string]$database) {
    $ledgerExists = Invoke-Psql $database "SELECT to_regclass('canonical_migrations.applied') IS NOT NULL;"
    if ((@($ledgerExists) -join '').Trim() -ne 't') { throw 'Canonical migration ledger is missing.' }
    $files = Get-ChildItem -LiteralPath (Join-Path $root 'migrations/canonical') -Filter '*.sql' -File | Sort-Object Name
    foreach ($file in $files) {
        if ($file.Name -notmatch '^[0-9]{4}_[a-z0-9_]+\.sql$') { throw "Invalid migration name: $($file.Name)" }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $existing = Invoke-Psql $database "SELECT sha256 FROM canonical_migrations.applied WHERE migration_name = '$($file.Name)';"
        if ((@($existing) -join '').Trim() -ne $hash) { throw "Migration missing or checksum changed: $($file.Name)" }
    }
    $ledgerCount = Invoke-Psql $database "SELECT count(*) FROM canonical_migrations.applied;"
    if ((@($ledgerCount) -join '').Trim() -ne [string]$files.Count) { throw 'Migration ledger includes an unexpected file.' }
}

function Test-MigrationAtomicity([string]$database) {
    $file = Get-Item -LiteralPath (Join-Path $root 'tests/9000_atomicity_probe.sql')
    $failed = $false
    try { Apply-Migration $database $file | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Synthetic migration did not fail as intended.' }
    $result = Invoke-Psql $database "SELECT to_regnamespace('acceptance_atomicity_probe') IS NULL AND NOT EXISTS (SELECT 1 FROM canonical_migrations.applied WHERE migration_name = '9000_atomicity_probe.sql');"
    if ((@($result) -join '').Trim() -ne 't') { throw 'Failed migration left schema or ledger residue.' }
    Write-Output "PASS PostgreSQL $Version atomic migration rollback"
}

function Test-MigrationChecksumDrift([string]$database) {
    $source = Get-Item -LiteralPath (Join-Path $root 'migrations/canonical/0002_education_identity_skeleton.sql')
    $auditDir = Join-Path $root "runtime/checksum-drift-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $auditDir | Out-Null
    $changed = Join-Path $auditDir $source.Name
    Copy-Item -LiteralPath $source.FullName -Destination $changed
    Add-Content -LiteralPath $changed -Value '-- SYNTHETIC CHECKSUM DRIFT; NEVER A CANONICAL MIGRATION'
    $blocked = $false
    try { Apply-Migration $database (Get-Item -LiteralPath $changed) | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch '^Migration checksum changed: 0002_education_identity_skeleton\.sql$') { throw }
        $blocked = $true
    }
    if (-not $blocked) { throw 'Altered applied migration was accepted.' }
    $expected = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $registered = Invoke-Psql $database "SELECT sha256 FROM canonical_migrations.applied WHERE migration_name = '0002_education_identity_skeleton.sql';"
    if ((@($registered) -join '').Trim() -ne $expected) { throw 'Applied migration checksum changed after drift test.' }
    Write-Output "PASS PostgreSQL $Version applied-migration checksum drift refusal"
}

function New-CanonicalBackup([string]$sourceDatabase = $devDb) {
    Start-Database
    Assert-MigrationsApplied $sourceDatabase
    $domainTables = Invoke-Psql $sourceDatabase "SELECT format('%I.%I', n.nspname, c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind IN ('r','p') AND n.nspname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','learning') ORDER BY 1;"
    $domainRows = 0L
    foreach ($table in @($domainTables)) {
        if (-not $table) { continue }
        $rowCount = Invoke-Psql $sourceDatabase "SELECT count(*) FROM $table;"
        $domainRows += [long]((@($rowCount) -join '').Trim())
    }
    if ($domainRows -ne 0) { throw 'Synthetic-only backup requires zero persistent domain rows.' }
    $backupDir = Join-Path $root 'backups'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $runId = [guid]::NewGuid().ToString('N')
    $destination = Join-Path $backupDir "${sourceDatabase}_pg${Version}_${stamp}_${runId}.dump"
    $containerBackup = "/tmp/phoenix_canonical_backup_${runId}.dump"
    if (Test-Path -LiteralPath $destination) { throw 'Refusing to overwrite an existing backup.' }
    Invoke-Docker ($compose + @('exec', '-T', '-e', "PGPASSFILE=$containerPgpass", $service, 'pg_dump', '-h', '127.0.0.1', '-U', 'phoenix_canonical_backup_local', '-d', $sourceDatabase, '-Fc', '-f', $containerBackup))
    $containerId = (& docker @compose ps -q $service).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $containerId) { throw 'Could not identify test container for backup copy.' }
    try { Invoke-Docker @('cp', "${containerId}:$containerBackup", $destination) }
    finally { & docker @compose exec -T $service rm -f $containerBackup | Out-Null }
    $digest = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    $migrationCount = (Get-ChildItem -LiteralPath (Join-Path $root 'migrations/canonical') -Filter '*.sql' -File).Count
    $manifest = [ordered]@{ purpose = 'phoenix-canonical-local-synthetic'; database = $sourceDatabase; pg_major = $Version; dump_sha256 = $digest; domain_rows = 0; migration_count = $migrationCount }
    [IO.File]::WriteAllText("$destination.manifest.json", ($manifest | ConvertTo-Json -Compress))
    return $destination
}

function Restore-CanonicalBackup([string]$path, [string]$sourceDatabase = $devDb) {
    $resolvedBackup = (Resolve-Path -LiteralPath $path).Path
    $backupDir = (Resolve-Path -LiteralPath (Join-Path $root 'backups')).Path
    if (-not $resolvedBackup.StartsWith("$backupDir$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Restore source must be inside this isolated project backup directory.'
    }
    $backupPrefix = [regex]::Escape($sourceDatabase)
    if ([IO.Path]::GetFileName($resolvedBackup) -notmatch "^${backupPrefix}_pg${Version}_[0-9]{8}-[0-9]{6}_[0-9a-f]{32}\.dump$") {
        throw 'Restore source does not match a versioned local synthetic backup name.'
    }
    $manifestPath = "$resolvedBackup.manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Backup provenance manifest is missing.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $digest = (Get-FileHash -LiteralPath $resolvedBackup -Algorithm SHA256).Hash.ToLowerInvariant()
    $currentMigrationCount = (Get-ChildItem -LiteralPath (Join-Path $root 'migrations/canonical') -Filter '*.sql' -File).Count
    if ($manifest.purpose -ne 'phoenix-canonical-local-synthetic' -or $manifest.database -ne $sourceDatabase -or
        $manifest.pg_major -ne $Version -or $manifest.domain_rows -ne 0 -or $manifest.migration_count -ne $currentMigrationCount -or $manifest.dump_sha256 -ne $digest) {
        throw 'Backup provenance or digest check failed.'
    }
    Start-Database
    $containerId = (& docker @compose ps -q $service).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $containerId) { throw 'Could not identify test container for restore copy.' }
    $containerRestore = "/tmp/phoenix_canonical_restore_$([guid]::NewGuid().ToString('N')).dump"
    Invoke-Docker @('cp', $resolvedBackup, "${containerId}:$containerRestore")
    try {
        Invoke-Docker ($compose + @('exec', '-T', $service, 'pg_restore', '-l', $containerRestore)) | Out-Null
        Reset-TestDatabase $restoreDb
        Invoke-Docker ($compose + @('exec', '-T', '-e', "PGPASSFILE=$containerPgpass", $service, 'pg_restore', '-h', '127.0.0.1', '-U', 'phoenix_bootstrap', '-d', $restoreDb, '--no-owner', '--exit-on-error', $containerRestore))
    } finally { & docker @compose exec -T $service rm -f $containerRestore | Out-Null }
    $sql = [IO.File]::ReadAllText((Join-Path $root 'tests/foundation.sql'))
    Invoke-Psql $restoreDb $sql | Out-Null
}

function Test-BackupTamperRefusal {
    Start-Database
    Reset-TestDatabase $testDb
    Migrate $testDb
    $source = New-CanonicalBackup $testDb
    Start-Database
    Reset-TestDatabase $restoreDb
    Invoke-Psql $restoreDb "CREATE TABLE public.synthetic_restore_guard(marker text PRIMARY KEY); INSERT INTO public.synthetic_restore_guard VALUES ('preserve-before-refusal');" | Out-Null
    $created = [Collections.Generic.List[string]]::new()
    try {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        foreach ($kind in @('dump', 'manifest')) {
            $candidate = Join-Path (Split-Path -Parent $source) "${testDb}_pg${Version}_${stamp}_$([guid]::NewGuid().ToString('N')).dump"
            Copy-Item -LiteralPath $source -Destination $candidate
            Copy-Item -LiteralPath "$source.manifest.json" -Destination "$candidate.manifest.json"
            $created.Add($candidate); $created.Add("$candidate.manifest.json")
            if ($kind -eq 'dump') {
                $stream = [IO.File]::Open($candidate, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $stream.WriteByte(0x50) } finally { $stream.Dispose() }
            } else {
                $badManifest = Get-Content -LiteralPath "$candidate.manifest.json" -Raw | ConvertFrom-Json
                $badManifest.purpose = 'tampered-purpose'
                [IO.File]::WriteAllText("$candidate.manifest.json", ($badManifest | ConvertTo-Json -Compress))
            }
            $blocked = $false
            try { Restore-CanonicalBackup $candidate $testDb }
            catch {
                if ($_.Exception.Message -notmatch '^Backup provenance or digest check failed\.$') { throw }
                $blocked = $true
            }
            if (-not $blocked) { throw "Tampered $kind backup was accepted." }
            $guard = Invoke-Psql $restoreDb "SELECT marker FROM public.synthetic_restore_guard;"
            if ((@($guard) -join '').Trim() -ne 'preserve-before-refusal') { throw "Restore database changed after tampered $kind refusal." }
        }
    } finally {
        foreach ($path in $created) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $source,"${source}.manifest.json" -Force -ErrorAction SilentlyContinue
    }
    Reset-TestDatabase $restoreDb
    Write-Output "PASS PostgreSQL $Version backup digest/provenance tamper refusal with restore database preserved"
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
    foreach ($name in @('foundation.sql', 'rls_probe.sql', 'docs_probe.sql', 'contract_neutral_probe.sql', 'trusted_context_probe.sql', 'phase3_acceptance.sql')) {
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
        Start-Database
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
        Write-Output "PASS PostgreSQL $Version foundation, repeat migration, and all synthetic probes"
    }
    'probe' {
        Start-Database
        Invoke-SyntheticProbes $devDb
        Write-Output "PASS PostgreSQL $Version nondestructive transactional synthetic probes"
    }
    'audit-migration' {
        Start-Database
        Reset-TestDatabase $testDb
        Migrate $testDb
        Migrate $testDb
        Test-MigrationAtomicity $testDb
        Test-MigrationChecksumDrift $testDb
    }
    'backup' {
        $destination = New-CanonicalBackup
        Write-Output "BACKUP $destination"
    }
    'restore-test' {
        if (-not $BackupPath) { throw 'Pass -BackupPath to an existing local test backup.' }
        Restore-CanonicalBackup $BackupPath
        Write-Output "PASS restore into $restoreDb"
    }
    'audit-backup' {
        Test-BackupTamperRefusal
    }
}
