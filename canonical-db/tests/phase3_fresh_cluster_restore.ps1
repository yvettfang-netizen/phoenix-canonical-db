param([ValidateSet('16','17')][string]$Version = '16')

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$envFile = Join-Path $root '.env'
$rolesFile = Join-Path $root '.local-roles.env'
$service = if ($Version -eq '16') { 'pg16' } else { 'pg17' }
$sourceDb = "phoenix_canonical_test_$Version"
$image = if ($Version -eq '16') { 'postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d' } else { 'postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3' }
$compose = @('compose','--env-file',$envFile,'-f',(Join-Path $root 'compose.yaml'))
if ($Version -eq '17') { $compose += @('--profile','compat') }
$pgpass = '/tmp/phoenix-fresh-restore.pgpass'
$freshContainerName = "phoenix-canonical-fresh-restore-$Version-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$dump = Join-Path $root "runtime/phase3-fresh-restore-$Version.dump"
$manifest = "$dump.manifest.json"
$migrationCount = @(Get-ChildItem -LiteralPath (Join-Path $root 'migrations/canonical') -File -Filter '*.sql').Count
$transcript = Join-Path $root "evidence/phase3-fresh-restore-pg$Version-$([guid]::NewGuid().ToString('N')).txt"
New-Item -ItemType Directory -Force -Path (Join-Path $root 'evidence') | Out-Null
Start-Transcript -Path $transcript -Force | Out-Null

function Secret([string]$path,[string]$name) {
    $line = Get-Content -LiteralPath $path | Where-Object { $_ -match "^$name=(.+)$" } | Select-Object -First 1
    if (-not $line) { throw "missing secret $name" }
    return $line -replace "^$name=",''
}
$bootstrap = Secret $envFile 'PHOENIX_DB_BOOTSTRAP_PASSWORD'
$backup = Secret $rolesFile 'PHOENIX_LOCAL_BACKUP_PASSWORD'
$app = Secret $rolesFile 'PHOENIX_LOCAL_APP_PASSWORD'
$reader = Secret $rolesFile 'PHOENIX_LOCAL_READER_PASSWORD'
$binder = Secret $rolesFile 'PHOENIX_LOCAL_BINDER_PASSWORD'
$migrator = Secret $rolesFile 'PHOENIX_LOCAL_MIGRATOR_PASSWORD'
$runtimeSecrets = @{ phoenix_bootstrap=$bootstrap; phoenix_canonical_backup_local=$backup; phoenix_canonical_app_local=$app; phoenix_canonical_reader_local=$reader; phoenix_canonical_context_binder_local=$binder; phoenix_canonical_migrator_local=$migrator }

function Install-Pgpass([string]$target,[hashtable]$entries) {
    $content = (($entries.GetEnumerator() | ForEach-Object { "*:*:*:$($_.Key):$($_.Value)" }) -join "`n") + "`n"
    $content | & docker exec -i $target sh -c "umask 077; cat > '$pgpass'; chmod 600 '$pgpass'"
    if ($LASTEXITCODE -ne 0) { throw 'pgpass installation failed' }
}
function Source-Psql([string]$user,[string]$sql) {
    $out = $sql | & docker @compose exec -T -e "PGPASSFILE=$pgpass" $service psql -X -h 127.0.0.1 -U $user -d $sourceDb -v ON_ERROR_STOP=1 -At -f -
    if ($LASTEXITCODE -ne 0) { throw 'source psql failed' }
    return (@($out) -join "`n").Trim()
}
function Fresh-Psql([string]$user,[string]$sql) {
    $out = $sql | & docker exec -i -u postgres $freshContainerName psql -X -U postgres -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -At -f -
    if ($LASTEXITCODE -ne 0) { throw 'fresh psql failed' }
    return (@($out) -join "`n").Trim()
}

try {
    & pwsh -NoLogo -NoProfile -File (Join-Path $root 'scripts/db.ps1') -Action test -Version $Version | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'source synthetic suite failed' }
    $sourceContainer = (& docker @compose ps -q $service).Trim()
    Install-Pgpass $sourceContainer @{ phoenix_bootstrap=$bootstrap; phoenix_canonical_backup_local=$backup }
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'runtime') | Out-Null
    & docker @compose exec -T -e "PGPASSFILE=$pgpass" $service pg_dump -h 127.0.0.1 -U phoenix_canonical_backup_local -d $sourceDb -Fc > $dump
    if ($LASTEXITCODE -ne 0) { throw 'backup role export failed' }
    $digest = (Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash.ToLowerInvariant()
    @{ purpose='phoenix-canonical-fresh-cluster-test'; database='phoenix_canonical_test_' + $Version; format='pg_custom'; sha256=$digest; migration_count=$migrationCount } | ConvertTo-Json -Compress | Set-Content -NoNewline -Path $manifest
    Write-Output "BACKUP_ROLE_EXPORT digest=$digest"

    $freshPassword = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
    $envTmp = New-TemporaryFile
    @("POSTGRES_DB=phoenix_canonical_dev","POSTGRES_USER=postgres","POSTGRES_PASSWORD=$freshPassword","POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=peer --auth-host=scram-sha-256") | Set-Content -Path $envTmp -Encoding ascii
    & docker run -d --name $freshContainerName --network none --env-file $envTmp $image | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'fresh container failed to start' }
    Write-Output "FRESH_CONTAINER_NAME=$freshContainerName"
    for($i=0;$i -lt 30;$i++) {
        try { Fresh-Psql 'postgres' 'SELECT 1;' | Out-Null; break } catch { if($i -eq 29){throw}; Start-Sleep -Seconds 1 }
    }
    $rolesSql = @"
DO `$roles`$
BEGIN
  CREATE ROLE phoenix_canonical_migrator NOLOGIN NOINHERIT;
  CREATE ROLE phoenix_canonical_app NOLOGIN NOINHERIT;
  CREATE ROLE phoenix_canonical_reader NOLOGIN NOINHERIT;
  CREATE ROLE phoenix_canonical_context_binder NOLOGIN NOINHERIT;
  CREATE ROLE phoenix_canonical_backup_runtime NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
  CREATE ROLE phoenix_canonical_migrator_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$migrator';
  CREATE ROLE phoenix_canonical_app_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$app';
  CREATE ROLE phoenix_canonical_reader_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$reader';
  CREATE ROLE phoenix_canonical_context_binder_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$binder';
  CREATE ROLE phoenix_canonical_backup_local LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '$backup';
END
`$roles`$;
GRANT phoenix_canonical_migrator TO phoenix_canonical_migrator_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_app TO phoenix_canonical_app_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_reader TO phoenix_canonical_reader_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_context_binder_local WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_backup_runtime TO phoenix_canonical_backup_local WITH INHERIT TRUE, SET FALSE;
GRANT pg_read_all_data TO phoenix_canonical_backup_runtime WITH INHERIT TRUE, SET FALSE;
"@
    Fresh-Psql 'postgres' $rolesSql | Out-Null
    & docker cp $dump "${freshContainerName}:/tmp/restore.dump" | Out-Host
    & docker exec -i -u postgres $freshContainerName pg_restore -U postgres -d phoenix_canonical_dev --no-owner --exit-on-error /tmp/restore.dump | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'fresh-cluster pg_restore failed' }
    $catalog = Fresh-Psql 'postgres' "SELECT 'ledger='||count(*) FROM canonical_migrations.applied; SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname IN ('auth','core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning'); SELECT 'policies='||count(*) FROM pg_policies WHERE schemaname IN ('core','consent','audit','integration','docs','casework','education','identity','operations_ref','learning'); SELECT 'roles='||count(*) FROM pg_roles WHERE rolname LIKE 'phoenix_canonical_%';"
    Write-Output $catalog
    if ($catalog -notmatch "(?m)^ledger=$migrationCount$" -or $catalog -notmatch 'tables=50' -or $catalog -notmatch 'policies=41' -or $catalog -notmatch 'roles=10') { throw 'fresh-cluster catalog verification failed' }
    foreach($name in @('foundation.sql','rls_probe.sql','docs_probe.sql','contract_neutral_probe.sql','trusted_context_probe.sql','phase3_acceptance.sql')) {
        $sql = Get-Content -LiteralPath (Join-Path $root "tests/$name") -Raw
        Fresh-Psql 'postgres' $sql | Out-Null
        Write-Output "PASS fresh-cluster $name"
    }
    Write-Output "PASS PostgreSQL $Version fresh-cluster restore using backup role export"
}
catch {
    if ($freshContainerName) { docker inspect $freshContainerName 2>&1 | Select-Object -Last 20 | Out-Host; docker logs $freshContainerName 2>&1 | Out-Host }
    throw
}
finally {
    if ($freshContainerName) { & docker rm -f -v $freshContainerName | Out-Host }
    if ($envTmp) { Remove-Item -LiteralPath $envTmp -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $dump,$manifest -Force -ErrorAction SilentlyContinue
    try { Stop-Transcript | Out-Null } catch {}
}
