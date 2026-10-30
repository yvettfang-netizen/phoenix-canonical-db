param([ValidateSet('16','17')][string]$Version = '16')

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
$image = if ($Version -eq '16') {
    'postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d'
} else {
    'postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
}
$source = "phoenix-canonical-f10-v25-pwsh-pg$Version"
$restore = "phoenix-canonical-f10-v25-pwsh-restore-pg$Version"
$backupVolume = "phoenix_canonical_f10_backup_pg${Version}_v25_pwsh"
$sourceEnv = Join-Path $root "runtime/f10-v25-pg$Version.env"
$restoreEnv = Join-Path $root "runtime/f10-v25-restore-pg$Version.env"
$evidence = Join-Path $root "evidence/v1.28-0024-pwsh-f10-pg$Version.txt"
$names = @(docker ps -a --format '{{.Names}}')
$volumes = @(docker volume ls --format '{{.Name}}')
if ($names -contains $source -or $names -contains $restore -or $volumes -contains $backupVolume -or
    (Test-Path -LiteralPath $sourceEnv) -or (Test-Path -LiteralPath $restoreEnv)) {
    throw 'Exact F10 test resource already exists; no resource was changed'
}

function New-SyntheticEnv([string]$path) {
    $secret = [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
    @(
        'POSTGRES_DB=phoenix_canonical_dev',
        'POSTGRES_USER=phoenix_bootstrap',
        "POSTGRES_PASSWORD=$secret",
        'POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256'
    ) | Set-Content -LiteralPath $path
    $secret = $null
}
function Wait-Database([string]$name) {
    for ($i=0; $i -lt 40; $i++) {
        & docker exec $name pg_isready -U phoenix_bootstrap -d phoenix_canonical_dev *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    throw "PostgreSQL did not become ready: $name"
}
function Run-Checked([string]$label,[string[]]$arguments) {
    Write-Output "COMMAND: $label"
    & docker @arguments 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$label failed with exit code $LASTEXITCODE" }
}
function Run-PsqlFile([string]$name,[string]$file) {
    Run-Checked "docker exec $name bootstrap psql -f /opt/tests/$file" @(
        'exec','-e','PGPASSFILE=/tmp/f10-bootstrap.pgpass',$name,
        'psql','-X','-q','-h','127.0.0.1','-U','phoenix_bootstrap',
        '-d','phoenix_canonical_dev','-v','ON_ERROR_STOP=1','-f',"/opt/tests/$file"
    )
    Write-Output "PASS baseline $file"
}

Start-Transcript -Path $evidence -Force | Out-Null
try {
    Write-Output "TASK=C VERSION=$Version IMAGE=$image"
    Write-Output 'BOUNDARY: exact one-off containers, network none, no host ports, no existing Compose volumes'
    New-SyntheticEnv $sourceEnv
    New-SyntheticEnv $restoreEnv
    Run-Checked "docker volume create $backupVolume" @('volume','create',$backupVolume)
    Run-Checked "docker run $source --network none --env-file <ignored synthetic file> --mount exact backup volume" @(
        'run','-d','--name',$source,'--network','none','--env-file',$sourceEnv,
        '--mount',"type=volume,source=$backupVolume,target=/f10backup",$image
    )
    Wait-Database $source
    Run-Checked "docker exec $source mkdir /opt/migrations /opt/tests" @('exec',$source,'mkdir','-p','/opt/migrations','/opt/tests')
    Run-Checked "docker cp current Canonical migrations into $source" @('cp','migrations/canonical/.',"${source}:/opt/migrations")
    Run-Checked "docker cp test files into $source" @('cp','tests/.',"${source}:/opt/tests")
    Run-Checked "docker exec $source stage 0011-0025 outside migration directory for E1 ledger=10 check" @(
        'exec',$source,'bash','-c','mv /opt/migrations/001[1-9]_*.sql /opt/migrations/002[0-5]_*.sql /tmp/')
    Run-Checked "docker exec $source bash f10_ephemeral_init.sh expected=10" @(
        'exec','-e','F10_EXPECTED_MIGRATION_COUNT=10',$source,'bash','/opt/tests/f10_ephemeral_init.sh')
    Run-Checked "docker exec $source restore staged 0011-0025" @(
        'exec',$source,'bash','-c','mv /tmp/001[1-9]_*.sql /tmp/002[0-5]_*.sql /opt/migrations/')
    Run-Checked "docker exec $source bash f10_ephemeral_init.sh" @('exec',$source,'bash','/opt/tests/f10_ephemeral_init.sh')
    Run-Checked "docker exec $source bash f10_ephemeral_init.sh repeat" @('exec',$source,'bash','/opt/tests/f10_ephemeral_init.sh')
    Write-Output 'COMMAND: disposable container extra empty 0026 file; migration inventory must refuse'
    $extra = & docker exec $source bash -c 'touch /opt/migrations/0026_extra_probe.sql; bash /opt/tests/f10_ephemeral_init.sh' 2>&1
    $extraCode = $LASTEXITCODE
    $extra | Out-Host
    if ($extraCode -eq 0 -or (($extra -join ' ') -notmatch 'FAIL migration inventory')) { throw 'Extra migration file was not refused' }
    Write-Output "PASS extra migration refused, exit=$extraCode"
    Run-Checked "docker exec $source remove exact disposable extra file" @('exec',$source,'rm','/opt/migrations/0026_extra_probe.sql')
    Write-Output 'COMMAND: disposable container temporarily hides 0025; migration inventory must refuse'
    $missing = & docker exec $source bash -c 'mv /opt/migrations/0025_family_mapping_lock_hardening.sql /tmp/0025_family_mapping_lock_hardening.sql; bash /opt/tests/f10_ephemeral_init.sh' 2>&1
    $missingCode = $LASTEXITCODE
    $missing | Out-Host
    if ($missingCode -eq 0 -or (($missing -join ' ') -notmatch 'FAIL migration inventory')) { throw 'Missing migration file was not refused' }
    Write-Output "PASS missing migration refused, exit=$missingCode"
    Run-Checked "docker exec $source restore exact staged 0025" @(
        'exec',$source,'mv','/tmp/0025_family_mapping_lock_hardening.sql',
        '/opt/migrations/0025_family_mapping_lock_hardening.sql')

    foreach ($suite in @('foundation.sql','rls_probe.sql','docs_probe.sql',
        'contract_neutral_probe.sql','trusted_context_probe.sql','phase3_acceptance.sql')) {
        Run-PsqlFile $source $suite
    }
    Run-Checked "docker exec $source bash f10_ephemeral_seed.sh" @('exec',$source,'bash','/opt/tests/f10_ephemeral_seed.sh')
    Run-Checked "docker exec $source bash f10_ephemeral_regression.sh" @('exec',$source,'bash','/opt/tests/f10_ephemeral_regression.sh')
    Run-Checked "docker exec $source bash claude_f10_reaudit_probes.sh" @('exec',$source,'bash','/opt/tests/claude_f10_reaudit_probes.sh')
    Run-Checked "docker exec $source bash f10_v15_channel_kind.sh" @('exec',$source,'bash','/opt/tests/f10_v15_channel_kind.sh')
    Run-Checked "docker exec $source bash f10_v15_gap_regression.sh" @('exec',$source,'bash','/opt/tests/f10_v15_gap_regression.sh')
    Run-Checked "docker exec $source bash f10_v16_contract_gaps.sh" @('exec',$source,'bash','/opt/tests/f10_v16_contract_gaps.sh')
    Run-PsqlFile $source 'f10_v16_document_trigger.sql'
    Run-Checked "docker exec $source bash f10_v17_assignment_scope.sh" @('exec',$source,'bash','/opt/tests/f10_v17_assignment_scope.sh')
    Run-Checked "docker exec $source bash f10_v18_identity_pool.sh" @('exec',$source,'bash','/opt/tests/f10_v18_identity_pool.sh')
    Run-Checked "docker exec $source bash f10_v19_e_r6_repro.sh" @('exec',$source,'bash','/opt/tests/f10_v19_e_r6_repro.sh')
    Run-Checked "docker exec $source bash f10_v20_0018_acl.sh" @('exec',$source,'bash','/opt/tests/f10_v20_0018_acl.sh')
    Run-Checked "docker exec $source bash f10_v21_0019_education.sh" @('exec',$source,'bash','/opt/tests/f10_v21_0019_education.sh')
    Run-Checked "docker exec $source bash f10_v22_0021_operations_entitlement.sh" @('exec',$source,'bash','/opt/tests/f10_v22_0021_operations_entitlement.sh')
    Run-Checked "docker exec $source bash f10_v23_0022_learning.sh" @('exec',$source,'bash','/opt/tests/f10_v23_0022_learning.sh')
    Run-Checked "docker exec $source bash f10_v25_0023_application_family_context.sh" @('exec',$source,'bash','/opt/tests/f10_v25_0023_application_family_context.sh')
    Run-Checked "docker exec $source bash f10_v28_0024_family_mapping_management.sh" @('exec',$source,'bash','/opt/tests/f10_v28_0024_family_mapping_management.sh')
    $auditLog = Join-Path $root "evidence/v1.28-0024-pwsh-audit-log-pg$Version.txt"
    $auditIds = Join-Path $root "evidence/v1.28-0024-pwsh-audit-db-ids-pg$Version.txt"
    $reconcile = Join-Path $root "evidence/v1.28-0024-pwsh-audit-reconcile-pg$Version.txt"
    @(docker logs $source 2>&1 | Select-String 'PHOENIX_AUDIT' | ForEach-Object { $_.Line }) | Set-Content -LiteralPath $auditLog
    if ($LASTEXITCODE -ne 0) { throw 'Could not read disposable server audit log' }
    if ((Get-Content -LiteralPath $auditLog -Raw) -match 'Synthetic Renamed|Forbidden Cross Family') {
        throw 'Display name leaked into PHOENIX_AUDIT log'
    }
    Write-Output 'PASS T1 display names absent from PHOENIX_AUDIT log'
    & docker exec -e PGPASSFILE=/tmp/f10-backup.pgpass $source psql -X -At -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -c 'SELECT attempt_id FROM audit.access_events WHERE attempt_id IS NOT NULL ORDER BY event_id' | Set-Content -LiteralPath $auditIds
    if ($LASTEXITCODE -ne 0) { throw 'Could not read disposable persisted audit IDs' }
    & pwsh -NoProfile -File tests/f10_audit_reconcile.ps1 -LogPath $auditLog -PersistedIdsPath $auditIds -ExpectedRolledBackResourceId '018f0000-0000-7000-8000-000000009902' | Tee-Object -FilePath $reconcile
    if ($LASTEXITCODE -ne 0) { throw 'D9 log/database reconciliation failed' }
    Run-PsqlFile $source 'f10_d6_immutability_regression.sql'
    Run-PsqlFile $source 'f10_v15_schema_installer.sql'

    Write-Output 'COMMAND: docker exec psql local socket without pgpass; expected rejection'
    $unauth = & docker exec $source psql -X -w -U phoenix_bootstrap -d phoenix_canonical_dev -Atc 'SELECT 1' 2>&1
    $unauth | Out-Host
    if ($LASTEXITCODE -eq 0) { throw 'Unauthenticated local socket unexpectedly succeeded' }
    Write-Output "PASS socket password required, exit=$LASTEXITCODE"
    Run-Checked "docker exec $source inspect pg_hba_file_rules" @(
        'exec','-e','PGPASSFILE=/tmp/f10-bootstrap.pgpass',$source,
        'psql','-X','-h','127.0.0.1','-U','phoenix_bootstrap','-d','phoenix_canonical_dev',
        '-Atc',"SELECT type||'|'||auth_method FROM pg_hba_file_rules WHERE type IN ('local','host') ORDER BY line_number"
    )

    Write-Output 'COMMAND: alter only the disposable container copy of 0009; repeat init expects checksum refusal'
    & docker exec $source bash -c 'printf "\n-- synthetic drift probe\n" >> /opt/migrations/0009_application_write_api.sql; bash /opt/tests/f10_ephemeral_init.sh' 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0) { throw 'Migration drift unexpectedly accepted' }
    Write-Output "PASS drift rejected, exit=$LASTEXITCODE"
    Run-Checked "docker cp pristine 0009 back into $source" @('cp','migrations/canonical/0009_application_write_api.sql',"${source}:/opt/migrations/0009_application_write_api.sql")
    Write-Output 'COMMAND: psql -f /opt/tests/9000_atomicity_probe.sql; expected synthetic failure'
    & docker exec -e PGPASSFILE=/tmp/f10-bootstrap.pgpass $source psql -X -q -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -f /opt/tests/9000_atomicity_probe.sql 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0) { throw 'Forced atomicity failure unexpectedly succeeded' }
    Write-Output "PASS forced failure rejected, exit=$LASTEXITCODE"
    Run-Checked "docker exec $source verify atomic rollback" @(
        'exec','-e','PGPASSFILE=/tmp/f10-bootstrap.pgpass',$source,
        'psql','-X','-At','-h','127.0.0.1','-U','phoenix_bootstrap','-d','phoenix_canonical_dev',
        '-c',"SELECT 'atomic_schema_exists='||(to_regnamespace('acceptance_atomicity_probe') IS NOT NULL); SELECT 'ledger='||count(*) FROM canonical_migrations.applied;"
    )

    Write-Output "COMMAND: docker exec $source pg_dump with dedicated backup LOGIN and 0600 pgpass into exact synthetic backup volume"
    & docker exec $source bash -c 'set -euo pipefail; umask 077; export PGPASSFILE=/tmp/f10-backup.pgpass; pg_dump -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -Fc > /f10backup/source.dump; sha256sum /f10backup/source.dump | cut -d" " -f1 > /f10backup/source.dump.sha256; stat -c "DUMP_MODE=%a DUMP_SIZE=%s" /f10backup/source.dump; echo "DUMP_SHA=$(cat /f10backup/source.dump.sha256)"; pg_restore -l /f10backup/source.dump | awk ''BEGIN{n=0} /^[0-9]+;/{n++} END{print "PG_RESTORE_ENTRIES=" n}''' 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Backup role export failed' }

    Run-Checked "docker run $restore --network none --env-file <ignored synthetic file> --mount read-only backup volume" @(
        'run','-d','--name',$restore,'--network','none','--env-file',$restoreEnv,
        '--mount',"type=volume,source=$backupVolume,target=/f10backup,readonly",$image
    )
    Wait-Database $restore
    Run-Checked "docker exec $restore mkdir /opt/tests" @('exec',$restore,'mkdir','-p','/opt/tests')
    Run-Checked "docker cp test files into $restore" @('cp','tests/.',"${restore}:/opt/tests")
    Run-Checked "docker exec $restore bash f10_ephemeral_restore.sh" @('exec',$restore,'bash','/opt/tests/f10_ephemeral_restore.sh')
    Run-Checked "docker inspect exact source network/port" @('inspect',$source,'--format','NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}')
    Run-Checked "docker inspect exact restore network/port" @('inspect',$restore,'--format','NETWORK={{.HostConfig.NetworkMode}} PORTS={{json .HostConfig.PortBindings}}')
    Write-Output "PASS PostgreSQL $Version F10 full synthetic acceptance"
}
finally {
    foreach ($name in @($restore,$source)) {
        if (@(docker ps -a --format '{{.Names}}') -contains $name) {
            Write-Output "CLEANUP: docker stop $name"
            & docker stop $name 2>&1 | Out-Host
            Write-Output "CLEANUP: docker rm -v $name"
            & docker rm -v $name 2>&1 | Out-Host
        }
    }
    if (@(docker volume ls --format '{{.Name}}') -contains $backupVolume) {
        Write-Output "CLEANUP: docker volume rm $backupVolume"
        & docker volume rm $backupVolume 2>&1 | Out-Host
    }
    foreach ($path in @($sourceEnv,$restoreEnv)) {
        $allowed = Join-Path $root 'runtime'
        if ($path.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $path)) {
            Write-Output "CLEANUP: Remove-Item exact ignored synthetic env file $(Split-Path $path -Leaf)"
            Remove-Item -LiteralPath $path -Force
        }
    }
    Stop-Transcript | Out-Null
}
