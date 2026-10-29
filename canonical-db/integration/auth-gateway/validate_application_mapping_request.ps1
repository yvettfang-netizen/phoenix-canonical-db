param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    throw "REQUEST_INVALID: $Message"
}

function Assert-ExactKeys([object]$Value, [string[]]$Expected, [string]$Label) {
    if ($Value -isnot [Collections.IDictionary]) { Fail "$Label must be an object" }
    $actual = @($Value.Keys | ForEach-Object { [string]$_ })
    $missing = @($Expected | Where-Object { $_ -notin $actual })
    $extra = @($actual | Where-Object { $_ -notin $Expected })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        Fail "$Label keys differ; missing=$($missing -join ','); extra=$($extra -join ',')"
    }
}

function Assert-Match([object]$Value, [string]$Pattern, [string]$Label) {
    if ($Value -isnot [string] -or $Value -notmatch $Pattern) { Fail "$Label has invalid format" }
}

function Assert-Reference([object]$Value, [string]$Label) {
    Assert-Match $Value '^(?:evidence|vault|notion)://[^\s]{3,500}$|^https://[^\s]{3,500}$' $Label
}

$resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
$bytes = [IO.File]::ReadAllBytes($resolved)
if ($bytes.Length -eq 0 -or $bytes.Length -gt 65536) { Fail 'file must be 1..65536 bytes' }
$utf8 = [Text.UTF8Encoding]::new($false, $true)
try { $raw = $utf8.GetString($bytes) } catch { Fail 'file must be valid UTF-8' }
try { $request = $raw | ConvertFrom-Json -AsHashtable -Depth 20 } catch { Fail 'file must be valid JSON' }

Assert-ExactKeys $request @(
    'schema_version','request_status','execution_authorized','target_environment','action',
    'source_system','issuer','application_user_id','application_family_id','canonical',
    'evidence','change_control','acknowledgements'
) 'request'
Assert-ExactKeys $request.canonical @(
    'external_identity_id','principal_id','actor_person_id','family_id','family_membership_id',
    'family_mapping_id','principal_kind','requested_mapping_status'
) 'canonical'
Assert-ExactKeys $request.evidence @(
    'application_ownership_ref','application_ownership_sha256','canonical_membership_ref',
    'canonical_membership_sha256','founder_approval_ref','founder_approval_sha256','approval_status'
) 'evidence'
Assert-ExactKeys $request.change_control @(
    'operator_principal_id','reviewer_person_id','rollback_owner_principal_id','window_start','window_end'
) 'change_control'
Assert-ExactKeys $request.acknowledgements @(
    'no_name_phone_openid_matching','no_secret_material','filled_request_stored_outside_git',
    'direct_table_write_forbidden','no_record_created_by_validation'
) 'acknowledgements'

if ($request.schema_version -ne '1.0') { Fail 'schema_version must be 1.0' }
if ($request.request_status -notin @('DRAFT','SYNTHETIC','FOUNDER_APPROVED')) { Fail 'request_status is invalid' }
if ($request.execution_authorized -isnot [bool] -or $request.execution_authorized) {
    Fail 'offline packet must keep execution_authorized=false'
}
if ($request.target_environment -ne 'TENCENT_ISOLATED_NON_PRODUCTION') { Fail 'target environment is not approved' }
if ($request.action -ne 'REGISTER_EXTERNAL_IDENTITY_AND_VERIFY_FAMILY_MAPPING') { Fail 'action is invalid' }
if ($request.source_system -ne 'PHOENIX_FAMILY_OS') { Fail 'source_system must be PHOENIX_FAMILY_OS' }
if ($request.issuer -ne 'https://api.phoenixnova.com.cn/canonical-identity') { Fail 'issuer is not the verified origin' }
Assert-Match $request.application_user_id '^usr_[A-Za-z0-9_-]{1,128}$' 'application_user_id'
Assert-Match $request.application_family_id '^fam_[0-9a-f]{32}$' 'application_family_id'

$uuidV7 = '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
$canonicalIds = @(
    $request.canonical.external_identity_id,$request.canonical.principal_id,
    $request.canonical.actor_person_id,$request.canonical.family_id,
    $request.canonical.family_membership_id,$request.canonical.family_mapping_id
)
foreach ($id in $canonicalIds) { Assert-Match $id $uuidV7 'canonical UUIDv7' }
if (@($canonicalIds | Sort-Object -Unique).Count -ne $canonicalIds.Count) { Fail 'canonical record IDs must be distinct' }
if ($request.canonical.principal_kind -ne 'FAMILY') { Fail 'principal_kind must be FAMILY' }
if ($request.canonical.requested_mapping_status -ne 'VERIFIED') { Fail 'requested_mapping_status must be VERIFIED' }

foreach ($entry in @(
    @($request.evidence.application_ownership_ref,'application_ownership_ref'),
    @($request.evidence.canonical_membership_ref,'canonical_membership_ref'),
    @($request.evidence.founder_approval_ref,'founder_approval_ref')
)) { Assert-Reference $entry[0] $entry[1] }
foreach ($digest in @(
    $request.evidence.application_ownership_sha256,
    $request.evidence.canonical_membership_sha256,
    $request.evidence.founder_approval_sha256
)) { Assert-Match $digest '^[0-9a-f]{64}$' 'evidence SHA-256' }
if ($request.evidence.approval_status -notin @('PENDING','SYNTHETIC','FOUNDER_APPROVED')) {
    Fail 'approval_status is invalid'
}
if ($request.request_status -eq 'FOUNDER_APPROVED' -and $request.evidence.approval_status -ne 'FOUNDER_APPROVED') {
    Fail 'FOUNDER_APPROVED request requires matching evidence status'
}

foreach ($id in @(
    $request.change_control.operator_principal_id,
    $request.change_control.reviewer_person_id,
    $request.change_control.rollback_owner_principal_id
)) { Assert-Match $id $uuidV7 'change-control UUIDv7' }
$start = [DateTimeOffset]::MinValue
$end = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse([string]$request.change_control.window_start, [ref]$start) -or
    -not [DateTimeOffset]::TryParse([string]$request.change_control.window_end, [ref]$end)) {
    Fail 'change window must use ISO-8601 timestamps'
}
$duration = $end - $start
if ($duration.TotalSeconds -le 0 -or $duration.TotalMinutes -gt 60) { Fail 'change window must be >0 and <=60 minutes' }

foreach ($key in $request.acknowledgements.Keys) {
    if ($request.acknowledgements[$key] -isnot [bool] -or -not $request.acknowledgements[$key]) {
        Fail "acknowledgement $key must be true"
    }
}

Write-Output 'PASS application mapping request structure; execution_authorized=false; no record written'
