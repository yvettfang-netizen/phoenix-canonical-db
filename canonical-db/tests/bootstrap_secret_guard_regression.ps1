$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\scripts\db.ps1')).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$tempDir = [IO.Path]::GetFullPath((Join-Path $tempRoot ('phoenix-guard-' + [guid]::NewGuid().ToString('N'))))
if (-not $tempDir.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'temporary path escaped intended directory' }
New-Item -ItemType Directory -Path (Join-Path $tempDir 'scripts') -Force | Out-Null
try {
    $copy = Join-Path $tempDir 'scripts\db.ps1'
    Copy-Item -LiteralPath $source -Destination $copy
    foreach ($case in @(
        @{ Name = 'missing'; Content = 'OTHER_SETTING=x' },
        @{ Name = 'malformed'; Content = 'PHOENIX_DB_BOOTSTRAP_PASSWORD=' + ('a' * 50) }
    )) {
        [IO.File]::WriteAllText((Join-Path $tempDir '.env'), $case.Content + "`n", [Text.UTF8Encoding]::new($false))
        Write-Output "COMMAND: pwsh -NoProfile -File <temporary db.ps1> -Action health (synthetic $($case.Name) credential)"
        $output = & pwsh -NoProfile -File $copy -Action health 2>&1
        $code = $LASTEXITCODE
        $output | ForEach-Object { Write-Output $_ }
        Write-Output "EXIT_CODE=$code"
        if ($code -eq 0 -or (($output -join ' ') -notmatch 'Local bootstrap secret is missing or invalid')) {
            throw "bootstrap guard failed for $($case.Name)"
        }
        Write-Output "PASS bootstrap guard $($case.Name)"
    }
} finally {
    if ($tempDir.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
