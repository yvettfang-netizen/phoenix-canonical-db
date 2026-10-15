param(
    [ValidateSet('16','17')][string]$Version = '16'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$envFile = Join-Path $root '.env'
$localRolesFile = Join-Path $root '.local-roles.env'
$service = if ($Version -eq '16') { 'pg16' } else { 'pg17' }
$testDb = "phoenix_canonical_test_$Version"
$containerPgpass = '/tmp/phoenix-defect-regression.pgpass'
$compose = @('compose','--env-file',$envFile,'-f',(Join-Path $root 'compose.yaml'))
if ($Version -eq '17') { $compose += @('--profile','compat') }

function Read-Secret([string]$path, [string]$name) {
    $line = Get-Content -LiteralPath $path | Where-Object { $_ -match "^$name=(.+)$" } | Select-Object -First 1
    if (-not $line) { throw "Missing synthetic secret $name" }
    return ($line -replace "^$name=",'')
}
$secrets = @{
    phoenix_bootstrap = Read-Secret $envFile 'PHOENIX_DB_BOOTSTRAP_PASSWORD'
    phoenix_canonical_app_local = Read-Secret $localRolesFile 'PHOENIX_LOCAL_APP_PASSWORD'
    phoenix_canonical_reader_local = Read-Secret $localRolesFile 'PHOENIX_LOCAL_READER_PASSWORD'
    phoenix_canonical_context_binder_local = Read-Secret $localRolesFile 'PHOENIX_LOCAL_BINDER_PASSWORD'
    phoenix_canonical_backup_local = Read-Secret $localRolesFile 'PHOENIX_LOCAL_BACKUP_PASSWORD'
}

function Set-Pgpass {
    $content = (($secrets.GetEnumerator() | ForEach-Object { "*:*:*:$($_.Key):$($_.Value)" }) -join "`n") + "`n"
    $content | & docker @compose exec -T $service sh -c "umask 077; cat > '$containerPgpass'; chmod 600 '$containerPgpass'"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to install synthetic pgpass file.' }
}
function Invoke-Psql([string]$user,[string]$sql) {
    $out = $sql | & docker @compose exec -T -e "PGPASSFILE=$containerPgpass" $service psql -X -h 127.0.0.1 -U $user -d $testDb -v ON_ERROR_STOP=1 -At -f -
    if ($LASTEXITCODE -ne 0) { throw "psql failed for $user" }
    return (@($out) -join "`n").Trim()
}
function Assert-Equal([string]$name,[string]$actual,[string]$expected) {
    if ($actual -ne $expected) { throw "$name expected [$expected] but was [$actual]" }
    Write-Output "PASS $name = $actual"
}
function Assert-Contains([string]$name,[string]$actual,[string]$expected) {
    if ($actual -notmatch [regex]::Escape($expected)) { throw "$name missing [$expected] in [$actual]" }
    Write-Output "PASS $name"
}
function Invoke-RegressionSql([string]$user,[string]$sql,[string]$label) {
    $out = Invoke-Psql $user $sql
    Assert-Contains $label $out 'PASS'
}

try {
    & pwsh -NoLogo -NoProfile -File (Join-Path $root 'scripts/db.ps1') -Action test -Version $Version | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Existing synthetic acceptance suite failed before defect regression.' }
    Set-Pgpass
    $fixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'phase3_defect_fixture.sql') -Raw
    Invoke-Psql 'phoenix_bootstrap' $fixture | Out-Null

    # F-01/T4b/T5: context is bound to backend start, not merely PID.
    Invoke-RegressionSql 'phoenix_bootstrap' @"
DO `$test`$
BEGIN
  INSERT INTO auth.session_contexts(backend_pid,backend_start,principal_id,actor_person_id,family_id,channel,request_nonce,expires_at)
  VALUES (2147483000,'2000-01-01 UTC','01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000001','FAMILY','01940000-0000-7000-8000-000000000c99',clock_timestamp()+interval '1 hour');
END
`$test`$;
SELECT CASE WHEN auth.current_family_id() IS NULL THEN 'PASS' ELSE 'FAIL' END;
"@ 'F-01 stale pid/start mismatch refused'

    $ticket = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '30 seconds','01940000-0000-7000-8000-000000000c01','01940000-0000-7000-8000-000000000201');"
    $redeem = Invoke-Psql 'phoenix_canonical_app_local' "SELECT auth.redeem_context_ticket('$ticket','01940000-0000-7000-8000-000000000201'); SELECT auth.current_family_id();"
    Assert-Contains 'F-02 correct ticket redeemed on separate LOGIN' $redeem '01940000-0000-7000-8000-000000000001'
    Assert-Equal 'F-02 app clear_context' (Invoke-Psql 'phoenix_canonical_app_local' "SELECT auth.clear_context(); SELECT COALESCE(auth.current_family_id()::text,'NULL');") 'NULL'

    Invoke-RegressionSql 'phoenix_canonical_app_local' @"
DO `$test`$
DECLARE blocked boolean := false;
BEGIN
  BEGIN PERFORM auth.redeem_context_ticket('00000000-0000-4000-8000-000000000001','01940000-0000-7000-8000-000000000201'); EXCEPTION WHEN others THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL'; END IF;
END
`$test`$;
SELECT 'PASS';
"@ 'F-02 forged ticket refused'

    $wrongTicket = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '30 seconds','01940000-0000-7000-8000-000000000c02','01940000-0000-7000-8000-000000000201');"
    Invoke-RegressionSql 'phoenix_canonical_app_local' @"
DO `$test`$
DECLARE blocked boolean := false;
BEGIN
  BEGIN PERFORM auth.redeem_context_ticket('$wrongTicket','01940000-0000-7000-8000-000000000202'); EXCEPTION WHEN others THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL'; END IF;
END
`$test`$;
SELECT 'PASS';
"@ 'F-02 wrong intended principal refused'

    $expiredTicket = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '1 millisecond','01940000-0000-7000-8000-000000000c03','01940000-0000-7000-8000-000000000201');"
    Start-Sleep -Milliseconds 50
    Invoke-RegressionSql 'phoenix_canonical_app_local' @"
DO `$test`$
DECLARE blocked boolean := false;
BEGIN
  BEGIN PERFORM auth.redeem_context_ticket('$expiredTicket','01940000-0000-7000-8000-000000000201'); EXCEPTION WHEN others THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL'; END IF;
END
`$test`$;
SELECT 'PASS';
"@ 'F-02 expired ticket refused'

    $reuseTicket = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '30 seconds','01940000-0000-7000-8000-000000000c04','01940000-0000-7000-8000-000000000201');"
    Invoke-Psql 'phoenix_canonical_app_local' "SELECT auth.redeem_context_ticket('$reuseTicket','01940000-0000-7000-8000-000000000201'); SELECT auth.clear_context();" | Out-Null
    Invoke-RegressionSql 'phoenix_canonical_app_local' @"
DO `$test`$
DECLARE blocked boolean := false;
BEGIN
  BEGIN PERFORM auth.redeem_context_ticket('$reuseTicket','01940000-0000-7000-8000-000000000201'); EXCEPTION WHEN others THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL'; END IF;
END
`$test`$;
SELECT 'PASS';
"@ 'F-02 one-time ticket reuse refused'

    # F-03/T1 and F-04/T2/T3: family and subject filters.
    $familyTicket = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '30 seconds','01940000-0000-7000-8000-000000000c05','01940000-0000-7000-8000-000000000201');"
    $familyOut = Invoke-Psql 'phoenix_canonical_app_local' "SELECT auth.redeem_context_ticket('$familyTicket','01940000-0000-7000-8000-000000000201'); SELECT count(*) FROM casework.advisor_assignments; SELECT count(*) FILTER (WHERE case_id='01940000-0000-7000-8000-000000000702') FROM casework.advisor_assignments; SELECT auth.clear_context();"
    Assert-Contains 'T1 family assignment visibility' $familyOut "1`n0"

    $advisorTicket = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000203','01940000-0000-7000-8000-000000000106','01940000-0000-7000-8000-000000000002','ADVISOR',clock_timestamp()+interval '30 seconds','01940000-0000-7000-8000-000000000c06','01940000-0000-7000-8000-000000000203');"
    $advisorOut = Invoke-Psql 'phoenix_canonical_app_local' "SELECT auth.redeem_context_ticket('$advisorTicket','01940000-0000-7000-8000-000000000203'); SELECT string_agg(display_name,' | ' ORDER BY display_name) FROM core.people; SELECT count(*) FROM core.family_memberships; SELECT count(*) FROM education.applications; SELECT auth.clear_context();"
    Assert-Contains 'T3 advisor subject-only visibility' $advisorOut 'Synthetic Student B'
    Assert-Contains 'T3 advisor subject membership only' $advisorOut "1`n0"

    $partnerTicket = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000204','01940000-0000-7000-8000-000000000107','01940000-0000-7000-8000-000000000002','PARTNER',clock_timestamp()+interval '30 seconds','01940000-0000-7000-8000-000000000c07','01940000-0000-7000-8000-000000000204');"
    $partnerOut = Invoke-Psql 'phoenix_canonical_app_local' "SELECT auth.redeem_context_ticket('$partnerTicket','01940000-0000-7000-8000-000000000204'); SELECT string_agg(display_name,' | ' ORDER BY display_name) FROM core.people; SELECT count(*) FROM core.family_memberships; SELECT count(*) FROM core.families; SELECT auth.clear_context();"
    Assert-Contains 'T2 partner subject-only visibility' $partnerOut 'Synthetic Student B'
    Assert-Contains 'T2 partner subject membership and family name hidden' $partnerOut "1`n0"

    # F-05/T7: forged audit calls fail while the controlled API still records.
    Invoke-RegressionSql 'phoenix_canonical_app_local' @"
DO `$test`$
DECLARE blocked boolean := false;
BEGIN
  BEGIN PERFORM audit.record_access_event('READ','DOCUMENT','01940000-0000-7000-8000-000000000b01','ALLOW','FORGED_BY_APP_ROLE'); EXCEPTION WHEN insufficient_privilege THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL'; END IF;
END
`$test`$;
SELECT 'PASS';
"@ 'T7 forged audit event refused'
    $familyTicket2 = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '30 seconds','01940000-0000-7000-8000-000000000c08','01940000-0000-7000-8000-000000000201');"
    Invoke-Psql 'phoenix_canonical_app_local' "SELECT auth.redeem_context_ticket('$familyTicket2','01940000-0000-7000-8000-000000000201'); SELECT education.authorize_application_read('01940000-0000-7000-8000-000000000501'); SELECT auth.clear_context();" | Out-Null
    Assert-Contains 'T7 controlled authorization audit' (Invoke-Psql 'phoenix_bootstrap' "SELECT count(*)::text FROM audit.access_events WHERE resource_id='01940000-0000-7000-8000-000000000501';") '1'

    # F-06/T6: regrant creates a new active row; historical row cannot reactivate.
    Invoke-RegressionSql 'phoenix_bootstrap' @"
DO `$test`$
DECLARE blocked boolean := false; active_count integer;
BEGIN
  UPDATE consent.grants SET status='WITHDRAWN', withdrawn_at=clock_timestamp() WHERE consent_id='01940000-0000-7000-8000-000000000901';
  INSERT INTO consent.grants(consent_id,family_id,grantor_person_id,grantee_person_id,subject_person_id,purpose,data_class,status,granted_at,expires_at)
  VALUES ('01940000-0000-7000-8000-000000000903','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','01940000-0000-7000-8000-000000000106','01940000-0000-7000-8000-000000000102','EDUCATION_CASE','EDUCATION','ACTIVE',clock_timestamp(),'2035-01-01 UTC');
  SELECT count(*) INTO active_count FROM consent.grants WHERE family_id='01940000-0000-7000-8000-000000000001' AND grantee_person_id='01940000-0000-7000-8000-000000000106' AND subject_person_id='01940000-0000-7000-8000-000000000102' AND purpose='EDUCATION_CASE' AND data_class='EDUCATION' AND status='ACTIVE';
  IF active_count <> 1 THEN RAISE EXCEPTION 'FAIL active regrant count'; END IF;
  BEGIN UPDATE consent.grants SET status='ACTIVE',withdrawn_at=NULL WHERE consent_id='01940000-0000-7000-8000-000000000901'; EXCEPTION WHEN others THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL reactivation accepted'; END IF;
END
`$test`$;
SELECT 'PASS';
"@ 'T6 consent regrant and reactivation rules'

    # F-07/T8/T8b: target existence and family/subject consistency.
    Invoke-RegressionSql 'phoenix_bootstrap' @"
DO `$test`$
DECLARE blocked boolean := false;
BEGIN
  BEGIN INSERT INTO docs.submission_manifests(submission_id,family_id,subject_person_id,target_kind,target_id,status,prepared_by)
    VALUES ('01940000-0000-7000-8000-000000000b05','01940000-0000-7000-8000-000000000001','01940000-0000-7000-8000-000000000102','EDUCATION_APPLICATION','01940000-0000-7000-8000-000000000502','PREPARING','01940000-0000-7000-8000-000000000101');
  EXCEPTION WHEN others THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL cross-family manifest accepted'; END IF;
  blocked := false;
  BEGIN INSERT INTO docs.submission_manifests(submission_id,family_id,subject_person_id,target_kind,target_id,status,prepared_by)
    VALUES ('01940000-0000-7000-8000-000000000b06','01940000-0000-7000-8000-000000000001','01940000-0000-0000-0000-000000000999','IDENTITY_CASE','01940000-0000-7000-8000-000000009999','PREPARING','01940000-0000-7000-8000-000000000101');
  EXCEPTION WHEN others THEN blocked := true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL nonexistent manifest accepted'; END IF;
END
`$test`$;
SELECT 'PASS';
"@ 'T8/T8b manifest target validation'

    # F-09/T13: EDUCATION guardian scope is accepted; GENERAL does not cover IDENTITY.
    $familyTicket3 = Invoke-Psql 'phoenix_canonical_context_binder_local' "SELECT auth.issue_context_ticket('01940000-0000-7000-8000-000000000201','01940000-0000-7000-8000-000000000101','01940000-0000-7000-8000-000000000001','FAMILY',clock_timestamp()+interval '30 seconds','01940000-0000-7000-8000-000000000c09','01940000-0000-7000-8000-000000000201');"
    $docOut = Invoke-Psql 'phoenix_canonical_app_local' "SELECT auth.redeem_context_ticket('$familyTicket3','01940000-0000-7000-8000-000000000201'); SELECT count(*) FROM docs.documents; SELECT docs.authorize_document_read('01940000-0000-7000-8000-000000000b01'); SELECT auth.clear_context();"
    Assert-Contains 'T13 EDUCATION guardian scope' $docOut "1`nt"
    Invoke-RegressionSql 'phoenix_bootstrap' @"
DO `$test`$
DECLARE blocked boolean := false;
BEGIN
  BEGIN DELETE FROM docs.document_versions WHERE version_id='01940000-0000-7000-8000-000000000b04'; EXCEPTION WHEN others THEN blocked := true; END;
  IF NOT blocked OR NOT docs.can_purge_document('01940000-0000-7000-8000-000000000b03') THEN RAISE EXCEPTION 'FAIL purge guard'; END IF;
END
`$test`$;
SELECT 'PASS';
"@ 'T12 purge decision remains guarded'

    Write-Output "PASS PostgreSQL $Version defect regression using separate LOGIN connections"
}
finally {
    try { & pwsh -NoLogo -NoProfile -File (Join-Path $root 'scripts/db.ps1') -Action reset-test -Version $Version | Out-Host } catch { Write-Error $_ }
    & docker @compose exec -T $service sh -c "rm -f '$containerPgpass'" | Out-Null
}
