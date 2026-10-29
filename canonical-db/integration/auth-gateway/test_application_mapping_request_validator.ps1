Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$validator = Join-Path $root 'validate_application_mapping_request.ps1'
$fixture = Join-Path $root 'synthetic\application-mapping-request.synthetic.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "phoenix-mapping-validator-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $tempRoot

function Invoke-Validator([string]$Path) {
    $output = & pwsh -NoProfile -File $validator -Path $Path 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = @($output) -join "`n" }
}

function Assert-Rejected([string]$Name, [scriptblock]$Mutate) {
    $value = Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json -AsHashtable -Depth 20
    & $Mutate $value
    $path = Join-Path $tempRoot "$Name.json"
    [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 20))
    $result = Invoke-Validator $path
    if ($result.ExitCode -eq 0 -or $result.Output -notmatch 'REQUEST_INVALID') {
        throw "Expected rejection did not occur: $Name"
    }
    Write-Output "PASS rejected $Name"
}

try {
    $positive = Invoke-Validator $fixture
    if ($positive.ExitCode -ne 0 -or $positive.Output -notmatch '^PASS application mapping request structure') {
        throw "Synthetic positive fixture failed: $($positive.Output)"
    }
    Write-Output 'PASS accepted complete synthetic request without authorizing execution'

    Assert-Rejected 'execution-authorized' { param($v) $v.execution_authorized = $true }
    Assert-Rejected 'wrong-issuer' { param($v) $v.issuer = 'https://unapproved.invalid/canonical-identity' }
    Assert-Rejected 'non-v7-family' { param($v) $v.canonical.family_id = '018f0000-0000-4000-8000-000000002704' }
    Assert-Rejected 'missing-evidence-digest' { param($v) $v.evidence.founder_approval_sha256 = '' }
    Assert-Rejected 'forbidden-openid-field' { param($v) $v.openid = 'synthetic-but-forbidden' }
    Assert-Rejected 'direct-write-not-acknowledged' { param($v) $v.acknowledgements.direct_table_write_forbidden = $false }
    Assert-Rejected 'oversized-change-window' { param($v) $v.change_control.window_end = '2026-10-29T12:00:00+08:00' }

    Write-Output 'PASS request validator positive and seven fail-closed regressions'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
