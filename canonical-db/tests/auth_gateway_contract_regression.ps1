[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $root 'integration/auth-gateway/validate-auth-contract.ps1'
$fixture = Join-Path $root 'integration/auth-gateway/fixtures/auth-contract.valid.synthetic.json'
$template = Join-Path $root 'integration/auth-gateway/auth-contract.template.json'
$ownerConfirmedCandidate = Join-Path $root 'integration/auth-gateway/auth-contract.owner-confirmed.candidate.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("phoenix-auth-contract-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

function Clone-Config {
    return (Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json -Depth 30 | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30)
}

function Clone-OwnerConfirmedCandidate {
    return (Get-Content -LiteralPath $ownerConfirmedCandidate -Raw | ConvertFrom-Json -Depth 30 | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30)
}

function Save-Config($Config, [string]$Name) {
    $path = Join-Path $tempRoot "$Name.json"
    $Config | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    return $path
}

function Invoke-Gate([string]$Path, [string]$Mode) {
    $output = & pwsh -NoProfile -File $validator -Path $Path -Mode $Mode 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Expect-Pass([string]$Name, [string]$Path, [string]$Mode = 'synthetic') {
    $result = Invoke-Gate $Path $Mode
    if ($result.ExitCode -ne 0 -or $result.Output -notmatch 'AUTH_CONTRACT_VALID') {
        throw "FAIL $Name expected PASS: $($result.Output)"
    }
    Write-Output "PASS $Name"
}

function Expect-Reject([string]$Name, $Config, [string]$Mode = 'synthetic') {
    $path = if ($Config -is [string]) { $Config } else { Save-Config $Config $Name }
    $result = Invoke-Gate $path $Mode
    if ($result.ExitCode -eq 0 -or $result.Output -notmatch 'AUTH_CONTRACT_INVALID') {
        throw "FAIL $Name expected rejection: $($result.Output)"
    }
    Write-Output "PASS $Name rejected"
}

try {
    Expect-Pass 'valid_synthetic_contract' $fixture
    Expect-Reject 'integration_rejects_synthetic_fixture' $fixture 'integration'
    Expect-Reject 'integration_template_is_incomplete' $template 'integration'
    Expect-Pass 'owner_confirmed_candidate_matches_staged_origin_and_refs' $ownerConfirmedCandidate 'integration'

    $c = Clone-OwnerConfirmedCandidate; $c.identity_provider.issuer = 'https://other.example.com/canonical-identity'; Expect-Reject 'integration_rejects_issuer_drift' $c 'integration'
    $c = Clone-OwnerConfirmedCandidate; $c.identity_provider.audience = 'other-audience'; Expect-Reject 'integration_rejects_audience_drift' $c 'integration'
    $c = Clone-OwnerConfirmedCandidate; $c.identity_provider.jwks_uri = 'https://api.phoenixnova.com.cn/.well-known/other.json'; Expect-Reject 'integration_rejects_jwks_drift' $c 'integration'
    $c = Clone-OwnerConfirmedCandidate; $c.identity_provider.signing_key_ref = 'file:/run/secrets/other'; Expect-Reject 'integration_rejects_signing_ref_drift' $c 'integration'
    $c = Clone-OwnerConfirmedCandidate; $c.identity_provider.allowed_algorithms = @('RS256', 'ES256'); Expect-Reject 'integration_rejects_algorithm_widening' $c 'integration'
    $c = Clone-OwnerConfirmedCandidate; $c.identity_provider.token_max_ttl_seconds = 301; Expect-Reject 'integration_rejects_selected_ttl_drift' $c 'integration'
    $c = Clone-OwnerConfirmedCandidate; $c.database.app_credential_ref = 'file:/run/secrets/other-app'; Expect-Reject 'integration_rejects_app_ref_drift' $c 'integration'

    $c = Clone-Config; $c.identity_provider.PSObject.Properties.Remove('issuer'); Expect-Reject 'missing_issuer' $c
    $c = Clone-Config; $c.identity_provider.allowed_algorithms = @('HS256'); Expect-Reject 'shared_secret_algorithm' $c
    $c = Clone-Config; $c.identity_provider.allowed_algorithms = @('none'); Expect-Reject 'unsigned_algorithm' $c
    $c = Clone-Config; $c.identity_provider.token_max_ttl_seconds = 901; Expect-Reject 'token_ttl_over_15_minutes' $c
    $c = Clone-Config; $c.identity_provider.clock_skew_seconds = 61; Expect-Reject 'clock_skew_over_60_seconds' $c
    $c = Clone-Config; $c.identity_provider.jwks_cache_seconds = 3601; Expect-Reject 'jwks_cache_over_one_hour' $c
    $c = Clone-Config; $c.identity_provider.unknown_kid_refresh_once = $false; Expect-Reject 'unknown_kid_no_refresh' $c
    $c = Clone-Config; $c.identity_provider.required_claims = @('iss', 'aud', 'exp'); Expect-Reject 'missing_required_claims' $c
    $c = Clone-Config; $c.identity_mapping.auto_provision = $true; Expect-Reject 'automatic_principal_provisioning' $c
    $c = Clone-Config; $c.identity_mapping.missing_or_disabled_action = 'allow'; Expect-Reject 'missing_mapping_fail_open' $c
    $c = Clone-Config; $c.database.ticket_ttl_seconds = 61; Expect-Reject 'ticket_ttl_over_60_seconds' $c
    $c = Clone-Config; $c.database.pool_mode = 'transaction'; Expect-Reject 'transaction_pooling' $c
    $c = Clone-Config; $c.database.clear_context_on_return = $false; Expect-Reject 'missing_clear_on_return' $c
    $c = Clone-Config; $c.database.discard_connection_on_clear_failure = $false; Expect-Reject 'missing_discard_on_clear_failure' $c
    $c = Clone-Config; $c.database.separate_credentials = $false; Expect-Reject 'credentials_not_separated' $c
    $c = Clone-Config; $c.database.app_credential_ref = $c.database.binder_credential_ref; Expect-Reject 'same_credential_reference' $c
    $c = Clone-Config; $c.logging.log_token_raw = $true; Expect-Reject 'raw_token_logging' $c
    $c = Clone-Config; $c.logging.log_personal_data = $true; Expect-Reject 'personal_data_logging' $c
    $c = Clone-Config; $c.logging.required_fields = @('timestamp', 'request_nonce'); Expect-Reject 'missing_audit_fields' $c

    Write-Output 'RESULT=PASS_AUTH_GATEWAY_CONTRACT_REGRESSION'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
