param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('16', '17')]
    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$canonicalRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$envFile = Join-Path $canonicalRoot '.env'
$composeFile = Join-Path $canonicalRoot 'compose.yaml'
$dbScript = Join-Path $canonicalRoot 'scripts\db.ps1'
$service = if ($Version -eq '16') { 'pg16' } else { 'pg17' }
$compose = @('compose', '--env-file', $envFile, '-f', $composeFile)
if ($Version -eq '17') { $compose += @('--profile', 'compat') }

& pwsh -NoProfile -File $dbScript -Action health -Version $Version | Out-Null
if ($LASTEXITCODE -ne 0) { throw "PG$Version health failed" }

$sql = @'
SELECT 'pg_major=' || current_setting('server_version_num')::integer / 10000;
SELECT 'ledger=' || count(*) FROM canonical_migrations.applied;
SELECT 'mapping_rows=' || count(*) FROM integration.legacy_id_mappings;
SELECT 'external_identity_rows=' || count(*) FROM auth.external_identities;
SELECT 'app_mapping_dml=' || has_table_privilege('phoenix_canonical_app','integration.legacy_id_mappings','INSERT,UPDATE,DELETE');
SELECT 'binder_mapping_dml=' || has_table_privilege('phoenix_canonical_context_binder','integration.legacy_id_mappings','INSERT,UPDATE,DELETE');
SELECT 'public_mapping_dml=' || has_table_privilege('public','integration.legacy_id_mappings','INSERT,UPDATE,DELETE');
SELECT 'app_register_external_identity=' || has_function_privilege('phoenix_canonical_app','auth.register_external_identity(uuid,text,text,uuid)','EXECUTE');
SELECT 'app_disable_external_identity=' || has_function_privilege('phoenix_canonical_app','auth.disable_external_identity(uuid)','EXECUTE');
SELECT 'controlled_family_mapping_functions=' || count(*)
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='integration' AND p.prokind='f'
   AND pg_get_functiondef(p.oid) ILIKE '%legacy_id_mappings%';
'@

$psqlArguments = $compose + @(
    'exec','-T','-e','PGPASSFILE=/tmp/phoenix-canonical-db.pgpass',$service,
    'psql','-X','-h','127.0.0.1','-U','phoenix_bootstrap','-d','phoenix_canonical_dev',
    '-v','ON_ERROR_STOP=1','-At','-f','-'
)
$result = $sql | & docker @psqlArguments
if ($LASTEXITCODE -ne 0) { throw "PG$Version read-only catalog query failed" }
$lines = @($result | ForEach-Object { [string]$_ })
$expected = @(
    "pg_major=$Version",
    'ledger=23',
    'mapping_rows=0',
    'external_identity_rows=0',
    'app_mapping_dml=false',
    'binder_mapping_dml=false',
    'public_mapping_dml=false',
    'app_register_external_identity=true',
    'app_disable_external_identity=true',
    'controlled_family_mapping_functions=0'
)
foreach ($item in $expected) {
    if ($item -notin $lines) { throw "PG$Version catalog assertion missing: $item" }
}
$lines | ForEach-Object { Write-Output $_ }
Write-Output "PASS PG$Version identity API available, family mapping DML denied, controlled mapping API absent, zero records"
