param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('test')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runId = [guid]::NewGuid().ToString('N')
$storeRoot = Join-Path $root "runtime/mock-object-store-$runId"
$restoreRoot = Join-Path $root "runtime/mock-object-restore-$runId"
$backupPath = Join-Path $root "backups/mock-object-store-$runId.zip"

function Get-Digest([byte[]]$bytes) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Put-MockObject([string]$directory, [byte[]]$bytes) {
    $key = Get-Digest $bytes
    $objectDir = Join-Path $directory 'objects'
    New-Item -ItemType Directory -Force -Path $objectDir | Out-Null
    $path = Join-Path $objectDir $key
    if (Test-Path -LiteralPath $path) {
        $existing = [IO.File]::ReadAllBytes($path)
        if ((Get-Digest $existing) -ne $key) { throw 'Existing mock object failed its digest check.' }
        return $key
    }
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    return $key
}

function Get-MockObject([string]$directory, [string]$key) {
    if ($key -notmatch '^[0-9a-f]{64}$') { throw 'Invalid mock object key.' }
    $path = Join-Path (Join-Path $directory 'objects') $key
    $bytes = [IO.File]::ReadAllBytes($path)
    if ((Get-Digest $bytes) -ne $key) { throw 'Mock object content does not match its key.' }
    return ,$bytes
}

if ($Action -eq 'test') {
    New-Item -ItemType Directory -Force -Path $storeRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
    $payload = [Text.Encoding]::UTF8.GetBytes("SYNTHETIC PHOENIX DOCUMENT $runId")
    $key = Put-MockObject $storeRoot $payload
    if ((Put-MockObject $storeRoot $payload) -ne $key) { throw 'Identical synthetic object did not deduplicate.' }
    if ((Get-Digest (Get-MockObject $storeRoot $key)) -ne $key) { throw 'Synthetic object readback failed.' }

    $manifest = [ordered]@{ synthetic_only = $true; object_key = $key; sha256 = $key; size_bytes = $payload.Length }
    [IO.File]::WriteAllText((Join-Path $storeRoot 'manifest.json'), ($manifest | ConvertTo-Json -Compress))
    [IO.Compression.ZipFile]::CreateFromDirectory($storeRoot, $backupPath)
    [IO.Compression.ZipFile]::ExtractToDirectory($backupPath, $restoreRoot)
    $restoredManifest = Get-Content -LiteralPath (Join-Path $restoreRoot 'manifest.json') -Raw | ConvertFrom-Json
    if (-not $restoredManifest.synthetic_only -or $restoredManifest.object_key -ne $key -or $restoredManifest.size_bytes -ne $payload.Length) {
        throw 'Restored mock manifest does not match the synthetic source.'
    }
    if ((Get-Digest (Get-MockObject $restoreRoot $key)) -ne $key) { throw 'Restored mock object failed integrity check.' }
    Write-Output "PASS synthetic mock object put/get, deduplication, backup and restore: $backupPath"
}
