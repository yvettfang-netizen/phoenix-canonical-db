param([ValidateSet('16','17')][string]$Version = '16')

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$image = if ($Version -eq '16') { 'postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d' } else { 'postgres:17@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3' }
$name = "phoenix-canonical-hba-$Version-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$envTmp = New-TemporaryFile
$pgpass = '/tmp/phoenix-hba-probe.pgpass'
$password = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
@("POSTGRES_DB=phoenix_hba_probe","POSTGRES_USER=postgres","POSTGRES_PASSWORD=$password","POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C.UTF-8 --auth-local=scram-sha-256 --auth-host=scram-sha-256") | Set-Content -Path $envTmp -Encoding ascii

try {
    & docker run -d --name $name --network none --env-file $envTmp $image | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'hba probe container failed to start' }
    for ($i = 0; $i -lt 60; $i++) {
        & docker exec $name pg_isready -U postgres -d postgres 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        if ($i -eq 59) { throw 'hba probe server did not become ready' }
        Start-Sleep -Seconds 1
    }
    $unauth = & docker exec $name psql -X -w -U postgres -d postgres -Atc 'SELECT 1' 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'unauthenticated local socket unexpectedly succeeded' }
    Write-Output 'PASS local socket without pgpass rejected'
    $content = "*:*:*:postgres:$password`n"
    $content | & docker exec -i $name sh -c "umask 077; cat > '$pgpass'; chmod 600 '$pgpass'"
    if ($LASTEXITCODE -ne 0) { throw 'pgpass installation failed' }
    $hba = & docker exec --env "PGPASSFILE=$pgpass" $name psql -X -w -U postgres -d postgres -Atc "SELECT type||'|'||auth_method FROM pg_hba_file_rules WHERE type IN ('local','host') ORDER BY line_number"
    if ($LASTEXITCODE -ne 0) { throw 'hba inspection failed' }
    $hbaText = @($hba) -join "`n"
    Write-Output $hbaText
    if ($hbaText -notmatch 'local\|scram-sha-256' -or $hbaText -notmatch 'host\|scram-sha-256') { throw 'scram hba rules not found' }
    Write-Output "PASS PostgreSQL $Version local socket and host authentication require SCRAM/pgpass"
}
finally {
    & docker rm -f -v $name 2>$null | Out-Host
    Remove-Item -LiteralPath $envTmp -Force -ErrorAction SilentlyContinue
}
