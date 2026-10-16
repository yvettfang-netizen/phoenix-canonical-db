$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$evidence = $PSScriptRoot
$db = Join-Path $root 'canonical-db\scripts\db.ps1'
$tests = Join-Path $root 'canonical-db\tests'
$summary = Join-Path $evidence 'v1.3-D3-summary.txt'
"COMMAND: pwsh -NoProfile -File canonical-db/evidence/v1.3-D3-cross-acceptance.ps1" | Set-Content -LiteralPath $summary -Encoding utf8
function Run([string]$label, [string]$script, [string[]]$arguments) {
    $out = Join-Path $evidence ("v1.3-D3-$label.txt")
    $printed = "COMMAND: pwsh -NoProfile -File $script $($arguments -join ' ')"
    $printed | Set-Content -LiteralPath $out -Encoding utf8
    $raw = & pwsh -NoProfile -File $script @arguments *>&1
    $raw | Out-File -LiteralPath $out -Append -Encoding utf8
    $exit = $LASTEXITCODE
    "EXIT_CODE=$exit" | Add-Content -LiteralPath $out -Encoding utf8
    "${label}: EXIT_CODE=$exit" | Tee-Object -FilePath $summary -Append
    return @{ Exit = $exit; Output = @($raw) }
}
foreach ($version in @('16','17')) {
    foreach ($action in @('test','probe','audit-migration','audit-backup')) {
        Run "pg$version-$action" $db @('-Action',$action,'-Version',$version) | Out-Null
    }
    $backup = Run "pg$version-backup" $db @('-Action','backup','-Version',$version)
    if ($backup.Exit -eq 0) {
        $path = @($backup.Output | Where-Object { $_ -match '^BACKUP (.+)$' } | Select-Object -Last 1)
        if ($path.Count -eq 1 -and $path[0] -match '^BACKUP (.+)$') {
            Run "pg$version-restore-test" $db @('-Action','restore-test','-Version',$version,'-BackupPath',$Matches[1]) | Out-Null
        } else { "pg$version-restore-test: SKIP backup path missing" | Tee-Object -FilePath $summary -Append }
    } else { "pg$version-restore-test: SKIP backup failed" | Tee-Object -FilePath $summary -Append }
    foreach ($test in @('phase3_defect_regression','phase3_fresh_cluster_restore','f10_local_acceptance')) {
        Run "pg$version-$test" (Join-Path $tests "$test.ps1") @('-Version',$version) | Out-Null
    }
    Run "pg$version-phase3_pg_hba_auth_regression" (Join-Path $tests 'phase3_pg_hba_auth_regression.ps1') @('-Version',$version) | Out-Null
}
Write-Output (Get-Content -LiteralPath $summary)
