param(
    [Parameter(Mandatory)][string]$LogPath,
    [Parameter(Mandatory)][string]$PersistedIdsPath,
    [Parameter(Mandatory)][string]$ExpectedRolledBackResourceId
)
$ErrorActionPreference = 'Stop'
$persisted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($line in Get-Content -LiteralPath $PersistedIdsPath) {
    if ($line -match '^[0-9a-f-]{36}$') { [void]$persisted.Add($line) }
}
$attempts = @()
foreach ($line in Get-Content -LiteralPath $LogPath) {
    if ($line -match 'PHOENIX_AUDIT attempt_id=([0-9a-f-]{36}) action=([^ ]+) resource_kind=([^ ]+) resource_id=([^ ]+) decision=([^ ]+) reason=([^ ]+) principal_id=([^ ]+) backend_pid=([0-9]+) occurred_at=(.+)$') {
        $attempts += [pscustomobject]@{ Id=$Matches[1]; Action=$Matches[2]; Resource=$Matches[4]; Decision=$Matches[5]; Reason=$Matches[6] }
    }
}
if ($attempts.Count -eq 0) { throw 'No PHOENIX_AUDIT entries to reconcile' }
$missing = @($attempts | Where-Object { -not $persisted.Contains($_.Id) })
Write-Output "LOG_ATTEMPTS=$($attempts.Count)"
Write-Output "PERSISTED_MATCHES=$($attempts.Count - $missing.Count)"
Write-Output "LOG_ONLY_ATTEMPTS=$($missing.Count)"
foreach ($attempt in $missing) {
    Write-Output "ROLLED_BACK_ATTEMPT attempt_id=$($attempt.Id) action=$($attempt.Action) resource_id=$($attempt.Resource) decision=$($attempt.Decision) reason=$($attempt.Reason)"
}
if (@($missing | Where-Object { $_.Resource -eq $ExpectedRolledBackResourceId -and $_.Decision -eq 'DENY' }).Count -lt 1) {
    throw 'Expected rolled-back denial absent from server log or unexpectedly persisted'
}
Write-Output 'PASS D9 log/database read-only reconciliation identified client rollback'
