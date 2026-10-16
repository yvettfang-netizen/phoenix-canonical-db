$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$db = Join-Path $root 'canonical-db\scripts\db.ps1'
function Run([string]$label, [string[]]$arguments) {
    $out = Join-Path $PSScriptRoot "v1.3-D3-pg16-$label-retest.txt"
    "COMMAND: pwsh -NoProfile -File canonical-db/scripts/db.ps1 $($arguments -join ' ')" | Set-Content -LiteralPath $out -Encoding utf8
    $raw = & pwsh -NoProfile -File $db @arguments *>&1
    $raw | Out-File -LiteralPath $out -Append -Encoding utf8
    $code = $LASTEXITCODE
    "EXIT_CODE=$code" | Add-Content -LiteralPath $out -Encoding utf8
    "${label}: EXIT_CODE=$code"
    if ($code -ne 0) { throw "$label failed" }
    return @($raw)
}
Run 'audit-backup' @('-Action','audit-backup','-Version','16') | Out-Null
$backupOutput = Run 'backup' @('-Action','backup','-Version','16')
$pathLine = @($backupOutput | Where-Object { $_ -match '^BACKUP (.+)$' } | Select-Object -Last 1)
if ($pathLine.Count -ne 1 -or $pathLine[0] -notmatch '^BACKUP (.+)$') { throw 'backup path missing' }
$backupPath = $Matches[1]
Run 'restore-test' @('-Action','restore-test','-Version','16','-BackupPath',$backupPath) | Out-Null
'PASS PG16 backup retest'
