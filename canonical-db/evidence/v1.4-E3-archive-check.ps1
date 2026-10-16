$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$tempDir = [IO.Path]::GetFullPath((Join-Path $tempRoot ('phoenix-v14-archive-' + [guid]::NewGuid().ToString('N'))))
if (-not $tempDir.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'temporary path escaped the intended directory'
}
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $tarPath = Join-Path $tempDir 'source.tar'
    Write-Output 'COMMAND: git archive --format=tar -o <temporary archive> HEAD canonical-db/deploy/tencent canonical-db/migrations/canonical canonical-db/tests'
    & git -C $repo archive --format=tar -o $tarPath HEAD canonical-db/deploy/tencent canonical-db/migrations/canonical canonical-db/tests
    if ($LASTEXITCODE -ne 0) { throw "git archive failed: $LASTEXITCODE" }
    $extractDir = Join-Path $tempDir 'extract'
    New-Item -ItemType Directory -Path $extractDir | Out-Null
    Write-Output 'COMMAND: tar -xf <temporary archive> -C <temporary extract>'
    & tar -xf $tarPath -C $extractDir
    if ($LASTEXITCODE -ne 0) { throw "tar failed: $LASTEXITCODE" }
    $files = @(Get-ChildItem -LiteralPath (Join-Path $extractDir 'canonical-db') -Recurse -File |
        Where-Object { $_.Extension -in @('.sh', '.sql', '.yaml') } | Sort-Object FullName)
    if ($files.Count -eq 0) { throw 'no target files found in archive' }
    $totalCr = 0
    foreach ($file in $files) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $cr = 0
        foreach ($byte in $bytes) { if ($byte -eq 13) { $cr++ } }
        $totalCr += $cr
        $relative = $file.FullName.Substring($extractDir.Length + 1)
        $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        Write-Output "FILE $relative CR=$cr SHA256=$sha"
    }
    Write-Output "TOTAL files=$($files.Count) CR=$totalCr"
    if ($totalCr -ne 0) { throw 'archive contains CR bytes' }
    Write-Output 'PASS archived .sh/.sql/.yaml contain zero CR bytes'
} finally {
    if ($tempDir.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
