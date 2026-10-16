param([Parameter(Mandatory = $true)][ValidateSet('16', '17')][string]$Version)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$service = if ($Version -eq '16') { 'pg16' } else { 'pg17' }
$compose = @('compose', '--env-file', (Join-Path $root '.env'), '-f', (Join-Path $root 'compose.yaml'))
if ($Version -eq '17') { $compose += @('--profile', 'compat') }
$pgpass = '/tmp/phoenix-canonical-db.pgpass'
function Invoke-As([string]$role, [string]$sql, [bool]$expectSuccess) {
    Write-Output "COMMAND: docker compose exec -T -e PGPASSFILE=$pgpass $service psql -X -h 127.0.0.1 -U $role -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -Atqc <SQL>"
    Write-Output "SQL: $sql"
    $output = & docker @compose exec -T -e "PGPASSFILE=$pgpass" $service psql -X -h 127.0.0.1 -U $role -d phoenix_canonical_dev -v ON_ERROR_STOP=1 -Atqc $sql 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Output $_ }
    Write-Output "EXIT_CODE=$code"
    if ($expectSuccess -and $code -ne 0) { throw "expected allow for $role" }
    if (-not $expectSuccess -and ($code -eq 0 -or (($output -join ' ') -notmatch 'permission denied'))) {
        throw "expected permission denial for $role"
    }
}
Invoke-As 'phoenix_canonical_reader_local' 'SELECT count(*) FROM canonical_migrations.applied' $true
Invoke-As 'phoenix_canonical_reader_local' "INSERT INTO canonical_migrations.applied(migration_name,sha256) VALUES ('__unauthorized_probe__',repeat('0',64))" $false
Invoke-As 'phoenix_canonical_reader_local' 'CREATE TABLE canonical_migrations.unauthorized_probe(id int)' $false
Invoke-As 'phoenix_canonical_app_local' 'SELECT count(*) FROM canonical_migrations.applied' $false
Invoke-As 'phoenix_canonical_context_binder_local' 'SELECT count(*) FROM canonical_migrations.applied' $false
Write-Output "PASS R-8 separate LOGIN PostgreSQL $Version"
