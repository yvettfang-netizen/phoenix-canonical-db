$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$tempDir = [IO.Path]::GetFullPath((Join-Path $tempRoot ('phoenix-v13-archive-' + [guid]::NewGuid().ToString('N'))))
if (-not $tempDir.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'temporary path escaped the intended directory'
}
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $tarPath = Join-Path $tempDir 'source.tar'
    Write-Output 'COMMAND: git archive --format=tar -o <temporary archive> HEAD canonical-db/deploy/tencent canonical-db/migrations/canonical canonical-db/tests'
    & git -C $root archive --format=tar -o $tarPath HEAD canonical-db/deploy/tencent canonical-db/migrations/canonical canonical-db/tests
    if ($LASTEXITCODE -ne 0) { throw "git archive failed: $LASTEXITCODE" }
    $extractDir = Join-Path $tempDir 'extract'
    New-Item -ItemType Directory -Path $extractDir | Out-Null
    Write-Output 'COMMAND: tar -xf <temporary archive> -C <temporary extract>'
    & tar -xf $tarPath -C $extractDir
    if ($LASTEXITCODE -ne 0) { throw "tar failed: $LASTEXITCODE" }
    $scripts = @(Get-ChildItem -LiteralPath (Join-Path $extractDir 'canonical-db') -Recurse -File -Filter '*.sh')
    if ($scripts.Count -eq 0) { throw 'no shell scripts found in archive' }
    foreach ($script in $scripts) {
        $bytes = [IO.File]::ReadAllBytes($script.FullName)
        $lf = [Array]::IndexOf($bytes, [byte]10)
        if ($lf -lt 0) { throw "missing first-line LF: $($script.FullName)" }
        if ($lf -gt 0 -and $bytes[$lf - 1] -eq 13) { throw "CRLF shebang: $($script.FullName)" }
        $relative = $script.FullName.Substring($extractDir.Length + 1)
        $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $script.FullName).Hash.ToLowerInvariant()
        Write-Output "PASS LF $relative SHA256=$sha"
    }
    Write-Output "PASS archive scripts=$($scripts.Count)"
} finally {
    if ($tempDir.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
