[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [ValidateSet('synthetic', 'integration')]
    [string]$Mode = 'integration'
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    throw "AUTH_CONTRACT_INVALID: $Message"
}

function Require-ObjectProperty($Object, [string]$Name, [string]$Parent) {
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
        Fail "$Parent.$Name is required"
    }
    return $Object.$Name
}

function Require-Text($Object, [string]$Name, [string]$Parent) {
    $value = Require-ObjectProperty $Object $Name $Parent
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        Fail "$Parent.$Name must be non-empty text"
    }
    return $value
}

function Require-Integer($Object, [string]$Name, [string]$Parent, [int]$Minimum, [int]$Maximum) {
    $value = Require-ObjectProperty $Object $Name $Parent
    if ($value -isnot [int] -and $value -isnot [long]) {
        Fail "$Parent.$Name must be an integer"
    }
    if ($value -lt $Minimum -or $value -gt $Maximum) {
        Fail "$Parent.$Name must be between $Minimum and $Maximum"
    }
    return [int]$value
}

function Require-Boolean($Object, [string]$Name, [string]$Parent, [bool]$Expected) {
    $value = Require-ObjectProperty $Object $Name $Parent
    if ($value -isnot [bool] -or $value -ne $Expected) {
        Fail "$Parent.$Name must be $($Expected.ToString().ToLowerInvariant())"
    }
}

function Require-HttpsUrl([string]$Value, [string]$Field) {
    $uri = $null
    if (-not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        Fail "$Field must be an absolute HTTPS URL"
    }
}

function Reject-Placeholder([string]$Value, [string]$Field) {
    if ($Value -match '(?i)(__required__|required_|synthetic|placeholder|\btbd\b|\.invalid(?:/|$))') {
        Fail "$Field still contains a placeholder or synthetic value"
    }
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Fail "file not found: $Path"
}

try {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 30
}
catch {
    Fail "JSON parse failed: $($_.Exception.Message)"
}

if ((Require-Text $config 'contract_version' 'root') -ne '1.0') { Fail 'root.contract_version must be 1.0' }
$environment = Require-Text $config 'environment' 'root'
if ($Mode -eq 'synthetic' -and $environment -ne 'synthetic') { Fail 'synthetic mode requires root.environment=synthetic' }
if ($Mode -eq 'integration' -and $environment -eq 'synthetic') { Fail 'integration mode rejects a synthetic environment' }

$governance = Require-ObjectProperty $config 'governance' 'root'
$contractPath = Require-Text $governance 'auth_contract_path' 'governance'
if ($contractPath -ne 'canonical-db/integration/auth-gateway/AUTH_GATEWAY_INTEGRATION_CONTRACT_V1.0.md') {
    Fail 'governance.auth_contract_path is not the approved skeleton path'
}
if ((Require-Text $governance 'auth_contract_version' 'governance') -ne '1.0') { Fail 'governance.auth_contract_version must be 1.0' }

$idp = Require-ObjectProperty $config 'identity_provider' 'root'
$providerName = Require-Text $idp 'provider_name' 'identity_provider'
$issuer = Require-Text $idp 'issuer' 'identity_provider'
$audience = Require-Text $idp 'audience' 'identity_provider'
$jwksUri = Require-Text $idp 'jwks_uri' 'identity_provider'
$signingKeyRef = Require-Text $idp 'signing_key_ref' 'identity_provider'
Require-HttpsUrl $issuer 'identity_provider.issuer'
Require-HttpsUrl $jwksUri 'identity_provider.jwks_uri'
$requiredClaims = @(Require-ObjectProperty $idp 'required_claims' 'identity_provider')
foreach ($claim in @('iss', 'aud', 'exp', 'nbf', 'sub')) {
    if ($requiredClaims -notcontains $claim) { Fail "identity_provider.required_claims is missing $claim" }
}

$algorithms = @(Require-ObjectProperty $idp 'allowed_algorithms' 'identity_provider')
if ($algorithms.Count -lt 1) { Fail 'identity_provider.allowed_algorithms must not be empty' }
$allowed = @('RS256', 'ES256')
foreach ($algorithm in $algorithms) {
    if ($algorithm -isnot [string] -or $allowed -notcontains $algorithm) {
        Fail "identity_provider.allowed_algorithms contains forbidden value: $algorithm"
    }
}
if (($algorithms | Select-Object -Unique).Count -ne $algorithms.Count) { Fail 'identity_provider.allowed_algorithms contains duplicates' }

[void](Require-Integer $idp 'token_max_ttl_seconds' 'identity_provider' 1 900)
[void](Require-Integer $idp 'clock_skew_seconds' 'identity_provider' 0 60)
[void](Require-Integer $idp 'jwks_cache_seconds' 'identity_provider' 1 3600)
Require-Boolean $idp 'unknown_kid_refresh_once' 'identity_provider' $true
[void](Require-Integer $idp 'refresh_rate_limit_seconds' 'identity_provider' 1 3600)

$mapping = Require-ObjectProperty $config 'identity_mapping' 'root'
$lookupKey = @(Require-ObjectProperty $mapping 'lookup_key' 'identity_mapping')
if ($lookupKey.Count -ne 2 -or $lookupKey[0] -ne 'issuer' -or $lookupKey[1] -ne 'subject') {
    Fail 'identity_mapping.lookup_key must be issuer,subject'
}
Require-Boolean $mapping 'auto_provision' 'identity_mapping' $false
if ((Require-Text $mapping 'missing_or_disabled_action' 'identity_mapping') -ne 'deny') {
    Fail 'identity_mapping.missing_or_disabled_action must be deny'
}

$database = Require-ObjectProperty $config 'database' 'root'
if ((Require-Text $database 'binder_role' 'database') -ne 'phoenix_canonical_context_binder') { Fail 'database.binder_role is invalid' }
if ((Require-Text $database 'app_role' 'database') -ne 'phoenix_canonical_app') { Fail 'database.app_role is invalid' }
$binderCredential = Require-Text $database 'binder_credential_ref' 'database'
$appCredential = Require-Text $database 'app_credential_ref' 'database'
if ($binderCredential -eq $appCredential) { Fail 'database binder and app credential references must differ' }
[void](Require-Integer $database 'ticket_ttl_seconds' 'database' 1 60)
$poolMode = Require-Text $database 'pool_mode' 'database'
if (@('direct', 'session') -notcontains $poolMode) { Fail 'database.pool_mode must be direct or session' }
Require-Boolean $database 'clear_context_on_return' 'database' $true
Require-Boolean $database 'discard_connection_on_clear_failure' 'database' $true
Require-Boolean $database 'separate_credentials' 'database' $true

$logging = Require-ObjectProperty $config 'logging' 'root'
Require-Boolean $logging 'request_nonce_uuid' 'logging' $true
Require-Boolean $logging 'log_token_raw' 'logging' $false
Require-Boolean $logging 'log_personal_data' 'logging' $false
$requiredFields = @(Require-ObjectProperty $logging 'required_fields' 'logging')
foreach ($field in @('timestamp', 'request_nonce', 'issuer', 'subject_id', 'channel', 'decision', 'reason_code')) {
    if ($requiredFields -notcontains $field) { Fail "logging.required_fields is missing $field" }
}

$ownership = Require-ObjectProperty $config 'ownership' 'root'
$ownerValues = @{}
foreach ($field in @('application_owner', 'binder_owner', 'principal_resolution_owner', 'audit_event_owner', 'incident_response_owner')) {
    $ownerValues[$field] = Require-Text $ownership $field 'ownership'
}

if ($Mode -eq 'integration') {
    Reject-Placeholder $providerName 'identity_provider.provider_name'
    Reject-Placeholder $issuer 'identity_provider.issuer'
    Reject-Placeholder $audience 'identity_provider.audience'
    Reject-Placeholder $jwksUri 'identity_provider.jwks_uri'
    Reject-Placeholder $signingKeyRef 'identity_provider.signing_key_ref'
    Reject-Placeholder $binderCredential 'database.binder_credential_ref'
    Reject-Placeholder $appCredential 'database.app_credential_ref'
    foreach ($field in $ownerValues.Keys) { Reject-Placeholder $ownerValues[$field] "ownership.$field" }
    if ($providerName -ne 'Phoenix First-Party Canonical Identity Broker V1.0') {
        Fail 'identity_provider.provider_name is not the Founder-selected broker'
    }
    if ($issuer -ne 'https://api.phoenixnova.com.cn/canonical-identity') {
        Fail 'identity_provider.issuer does not match the verified isolated public origin'
    }
    if ($audience -ne 'phoenix-canonical-postgresql') {
        Fail 'identity_provider.audience is not the approved Canonical audience'
    }
    if ($jwksUri -ne 'https://api.phoenixnova.com.cn/.well-known/phoenix-canonical-jwks.json') {
        Fail 'identity_provider.jwks_uri does not match the approved Canonical JWKS path'
    }
    if ($signingKeyRef -ne 'file:/run/secrets/phoenix_canonical_oidc_signing_key_v1') {
        Fail 'identity_provider.signing_key_ref is not the approved protected reference'
    }
    if ($algorithms.Count -ne 1 -or $algorithms[0] -ne 'ES256') {
        Fail 'identity_provider.allowed_algorithms must be exactly ES256 for the selected broker'
    }
    if ($idp.token_max_ttl_seconds -ne 300 -or $idp.jwks_cache_seconds -ne 300) {
        Fail 'identity_provider token TTL and JWKS cache must both be 300 seconds'
    }
    if ($appCredential -ne 'file:/run/secrets/phoenix_canonical_app_pgpass_v1' -or
        $binderCredential -ne 'file:/run/secrets/phoenix_canonical_binder_pgpass_v1') {
        Fail 'database credential references do not match the approved protected files'
    }
}

Write-Output "AUTH_CONTRACT_VALID mode=$Mode environment=$environment algorithms=$($algorithms -join ',') token_ttl=$($idp.token_max_ttl_seconds) ticket_ttl=$($database.ticket_ttl_seconds) pool=$poolMode"
