#!/usr/bin/env bash
# Permanent E-R6 regression. Runs inside the disposable PG container after migrations 0001-0018 are installed.
# Synthetic data only: families F1 and F2; students S1 (F1) and S2 (F2); guardians G1 (F1) and G2 (F2);
# advisor A1 assigned to one case in each family.
# PASS = behaviour the access contract requires. FINDING = behaviour that contradicts it.
# OBSERVE = behaviour correct by the current code that needs a Founder decision.
set -uo pipefail
umask 077
export PGPASSFILE=/tmp/f10-bootstrap.pgpass
OUT=/tmp/v19-out; rm -rf "$OUT"; mkdir -p "$OUT"
FIND=0

APP_PW="$(openssl rand -hex 32)"; BIND_PW="$(openssl rand -hex 32)"
printf '127.0.0.1:5432:*:phoenix_canonical_app_v19:%s\n' "$APP_PW" > /tmp/v19-app.pgpass
printf '127.0.0.1:5432:*:phoenix_canonical_binder_v19:%s\n' "$BIND_PW" > /tmp/v19-binder.pgpass
chmod 600 /tmp/v19-app.pgpass /tmp/v19-binder.pgpass

boot()   { psql -X -q -At -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
app()    { PGPASSFILE=/tmp/v19-app.pgpass psql -X -q -At -h 127.0.0.1 -U phoenix_canonical_app_v19 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder() { PGPASSFILE=/tmp/v19-binder.pgpass psql -X -q -At -h 127.0.0.1 -U phoenix_canonical_binder_v19 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }

U() { printf '018f0000-0000-7000-8000-0000000e%s' "$1"; }
SVC=$(U 0001)
F1=$(U 0101); F2=$(U 0102)
S1=$(U 0201); S2=$(U 0202)
G1=$(U 0301); G2=$(U 0302)
A1=$(U 0401)
M_G1=$(U 0501); M_S1=$(U 0502); M_G2=$(U 0503); M_S2=$(U 0504)
P_G1=$(U 0601); P_G2=$(U 0602); P_A1=$(U 0603)
GA1=$(U 0701); GA2=$(U 0702)
APP1=$(U 0801); APP2=$(U 0802)
C1=$(U 0901); C2=$(U 0902); C3=$(U 0903)
AS1=$(U 0a01); AS2=$(U 0a02); AS3=$(U 0a03)
CN1=$(U 0b01); CN2=$(U 0b02)

boot -c "CREATE ROLE phoenix_canonical_app_v19 LOGIN INHERIT NOSUPERUSER PASSWORD '$APP_PW';
CREATE ROLE phoenix_canonical_binder_v19 LOGIN INHERIT NOSUPERUSER PASSWORD '$BIND_PW';
GRANT phoenix_canonical_app TO phoenix_canonical_app_v19 WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_binder_v19 WITH INHERIT TRUE, SET FALSE;
GRANT CONNECT ON DATABASE phoenix_canonical_dev TO phoenix_canonical_app_v19, phoenix_canonical_binder_v19;" > /dev/null
boot -Atqc "SELECT auth.install_service_principal('$SVC','Synthetic R1 service')" > /dev/null
unset APP_PW BIND_PW

# issue a one-use ticket: principal, actor (or NULL), family (or NULL), channel
ticket() {
  local a=NULL f=NULL
  [ "$2" = NULL ] || a="'$2'"
  [ "$3" = NULL ] || f="'$3'"
  binder -c "SELECT auth.issue_context_ticket('$1',$a,$f,'$4',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$1')"
}
# run SQL from stdin inside a freshly bound session; a refused binding prints BIND_REFUSED <code>
bound() {
  local t
  t="$(ticket "$1" "$2" "$3" "$4" 2>&1)" || { echo "BIND_REFUSED $(grep -oE 'CONTEXT_[A-Z_]+' <<<"$t" | head -1)"; cat > /dev/null; return 0; }
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$1"; cat; printf "SELECT auth.clear_context();\n"; } | app -f -
}
svc() { # family or NULL; SQL from stdin
  local t
  t="$(ticket "$SVC" NULL "$1" INTERNAL 2>&1)" || { echo "SVC_BIND_FAILED $t"; cat > /dev/null; return 1; }
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$SVC"; cat; printf "SELECT auth.clear_context();\n"; } | app -f -
}
val() { grep -oE "$1=[A-Za-z0-9_]+" "$2" | tail -1 | cut -d= -f2; }
check() { if [ "$2" = "$3" ]; then echo "PASS $1 got=[$2]"; else echo "FINDING $1 got=[$2] expected=[$3]"; FIND=$((FIND+1)); fi; }
observe() { echo "OBSERVE $1 got=[$2]"; }

echo "== setup: two families, two students, two guardians, one advisor, one case per family"
svc NULL > "$OUT/s0" 2>&1 <<SQL
SELECT 'F1='||core.create_family('$F1','Synthetic Family One');
SELECT 'F2='||core.create_family('$F2','Synthetic Family Two');
SELECT 'A1='||core.register_external_person('$A1','Synthetic Advisor One');
SELECT 'PA1='||auth.create_login_principal('$P_A1','$A1','ADVISOR');
SQL
svc "$F1" > "$OUT/s1" 2>&1 <<SQL
SELECT 'G1='||core.create_person('$G1','Synthetic Guardian One','$F1','$M_G1','PRIMARY');
SELECT 'S1='||core.create_person('$S1','Synthetic Student One','$F1','$M_S1','MEMBER');
SELECT 'S1PROFILE='||core.create_student_profile('$S1');
SELECT 'PG1='||auth.create_login_principal('$P_G1','$G1','FAMILY');
SELECT 'GA1='||core.create_guardian_authority('$GA1','$F1','$G1','$S1','VERIFIED','EDUCATION',clock_timestamp()+interval '1 day','synthetic/v19/education-f1');
SQL
svc "$F2" > "$OUT/s2" 2>&1 <<SQL
SELECT 'G2='||core.create_person('$G2','Synthetic Guardian Two','$F2','$M_G2','PRIMARY');
SELECT 'S2='||core.create_person('$S2','Synthetic Student Two','$F2','$M_S2','MEMBER');
SELECT 'S2PROFILE='||core.create_student_profile('$S2');
SELECT 'PG2='||auth.create_login_principal('$P_G2','$G2','FAMILY');
SELECT 'GA2='||core.create_guardian_authority('$GA2','$F2','$G2','$S2','VERIFIED','EDUCATION',clock_timestamp()+interval '1 day','synthetic/v19/education-f2');
SQL
bound "$P_G1" "$G1" "$F1" FAMILY > "$OUT/s3" 2>&1 <<SQL
SELECT 'CN1='||consent.create_grant('$CN1','$F1','$A1','$S1','EDUCATION_CASE','EDUCATION',clock_timestamp()+interval '2 days');
SELECT 'APP1='||education.create_application('$APP1','$F1','$S1','Synthetic Institution A','Synthetic Program A','2026 Fall');
SQL
bound "$P_G2" "$G2" "$F2" FAMILY > "$OUT/s4" 2>&1 <<SQL
SELECT 'APP2='||education.create_application('$APP2','$F2','$S2','Synthetic Institution B','Synthetic Program B','2026 Fall');
SQL
svc "$F1" > "$OUT/s5" 2>&1 <<SQL
SELECT 'C1='||casework.create_case('$C1','$F1','$S1','Synthetic Case One','EDUCATION_APPLICATION','$APP1');
SELECT 'AS1='||casework.create_advisor_assignment('$AS1','$C1','$A1',clock_timestamp()+interval '1 day');
SQL
svc "$F2" > "$OUT/s6" 2>&1 <<SQL
SELECT 'C2='||casework.create_case('$C2','$F2','$S2','Synthetic Case Two','EDUCATION_APPLICATION','$APP2');
SELECT 'AS2='||casework.create_advisor_assignment('$AS2','$C2','$A1',clock_timestamp()+interval '1 day');
SELECT 'C3='||casework.create_case('$C3','$F2','$S2','Synthetic Case Three',NULL,NULL);
SQL
setup_err="$(cat "$OUT"/s* | grep -c 'ERROR' || true)"
check "setup has no ERROR lines" "$setup_err" 0
[ "$setup_err" = 0 ] || { cat "$OUT"/s*; exit 1; }

echo "== T-A baseline: case open, assignment active, consent active"
bound "$P_A1" "$A1" "$F1" ADVISOR > "$OUT/tA" <<SQL
SELECT 'BASICS_S1='||count(*) FROM core.people WHERE person_id='$S1';
SELECT 'APP1='||count(*) FROM education.applications WHERE application_id='$APP1';
SQL
check "T-A advisor reads S1 basics (case open)" "$(val BASICS_S1 "$OUT/tA")" 1
check "T-A advisor reads APP1 (consent active)" "$(val APP1 "$OUT/tA")" 1
bound "$P_A1" "$A1" "$F1" ADVISOR > "$OUT/tA2" <<SQL
SELECT 'CASE_C1='||count(*) FROM casework.cases WHERE case_id='$C1';
SELECT 'ASSIGN_AS1='||count(*) FROM casework.advisor_assignments WHERE assignment_id='$AS1';
SELECT 'PROFILE_S1='||count(*) FROM core.student_profiles WHERE person_id='$S1';
SELECT 'MEMBERSHIP_S1='||count(*) FROM core.family_memberships WHERE person_id='$S1';
SQL
check "T-A positive: advisor reads C1 case row while open" "$(val CASE_C1 "$OUT/tA2")" 1
check "T-A positive: advisor reads AS1 assignment row while active" "$(val ASSIGN_AS1 "$OUT/tA2")" 1
check "T-A positive: advisor reads S1 student profile" "$(val PROFILE_S1 "$OUT/tA2")" 1
check "T-A positive: advisor reads S1 membership row" "$(val MEMBERSHIP_S1 "$OUT/tA2")" 1

echo "== T-B cross-family isolation"
bound "$P_A1" "$A1" "$F1" ADVISOR > "$OUT/tB1" <<SQL
SELECT 'BASICS_S2='||count(*) FROM core.people WHERE person_id='$S2';
SQL
check "T-B advisor bound F1 reads S2 (F2) basics" "$(val BASICS_S2 "$OUT/tB1")" 0
bound "$P_A1" "$A1" "$F2" ADVISOR > "$OUT/tB2" <<SQL
SELECT 'BASICS_S1='||count(*) FROM core.people WHERE person_id='$S1';
SELECT 'APP1='||count(*) FROM education.applications WHERE application_id='$APP1';
SQL
check "T-B advisor bound F2 reads S1 (F1) basics" "$(val BASICS_S1 "$OUT/tB2")" 0
check "T-B advisor bound F2 reads APP1 (F1)" "$(val APP1 "$OUT/tB2")" 0
bound "$P_A1" "$A1" "$F2" ADVISOR > "$OUT/tB3" <<SQL
SELECT 'BASICS_S2='||count(*) FROM core.people WHERE person_id='$S2';
SQL
check "T-B advisor bound F2 reads its own S2 basics (control)" "$(val BASICS_S2 "$OUT/tB3")" 1

echo "== T-C consent withdrawal (guardian G1 withdraws EDUCATION_CASE consent)"
bound "$P_G1" "$G1" "$F1" FAMILY > "$OUT/tC0" <<SQL
SELECT 'WITHDRAW_CN1='||consent.withdraw_grant('$CN1');
SQL
check "T-C withdraw_grant returns true" "$(val WITHDRAW_CN1 "$OUT/tC0")" true
bound "$P_A1" "$A1" "$F1" ADVISOR > "$OUT/tC1" <<SQL
SELECT 'APP1='||count(*) FROM education.applications WHERE application_id='$APP1';
SELECT 'BASICS_S1='||count(*) FROM core.people WHERE person_id='$S1';
SQL
check "T-C advisor reads APP1 after consent withdrawn" "$(val APP1 "$OUT/tC1")" 0
observe "T-C advisor reads S1 basics after consent withdrawn (basics are not consent-gated in can_read_subject_basics)" "$(val BASICS_S1 "$OUT/tC1")"
bound "$P_G1" "$G1" "$F1" FAMILY > "$OUT/tC2" <<SQL
SELECT 'CN2='||consent.create_grant('$CN2','$F1','$A1','$S1','EDUCATION_CASE','EDUCATION',clock_timestamp()+interval '2 days');
SQL
check "T-C consent re-granted for the closure test" "$(val CN2 "$OUT/tC2")" true

echo "== T-E assignment revoked while the advisor session is bound (F2)"
t="$(ticket "$P_A1" "$A1" "$F2" ADVISOR 2>&1)"
{ printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$P_A1"; printf "SELECT pg_sleep(4);\n"
  printf "SELECT 'BASICS_S2_AFTER_REVOKE='||count(*) FROM core.people WHERE person_id='%s';\n" "$S2"
  printf "SELECT auth.clear_context();\n"; } | app -f - > "$OUT/tE" 2>&1 &
sleep 1
svc "$F2" > "$OUT/tE_rev" 2>&1 <<SQL
SELECT 'REVOKE_AS2='||casework.revoke_advisor_assignment('$AS2');
SQL
wait
check "T-E revoke_advisor_assignment returns true" "$(val REVOKE_AS2 "$OUT/tE_rev")" true
check "T-E bound session reads S2 basics after assignment revoked" "$(val BASICS_S2_AFTER_REVOKE "$OUT/tE")" 0

echo "== T-F assignment expires while the advisor session is bound (F2, only AS3 active)"
svc "$F2" > "$OUT/tF_setup" 2>&1 <<SQL
SELECT 'AS3='||casework.create_advisor_assignment('$AS3','$C3','$A1',clock_timestamp()+interval '6 seconds');
SQL
check "T-F short assignment created" "$(val AS3 "$OUT/tF_setup")" true
t="$(ticket "$P_A1" "$A1" "$F2" ADVISOR 2>&1)"
{ printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$P_A1"
  printf "SELECT 'BASICS_S2_BEFORE_EXPIRY='||count(*) FROM core.people WHERE person_id='%s';\n" "$S2"
  printf "SELECT pg_sleep(8);\n"
  printf "SELECT 'BASICS_S2_AFTER_EXPIRY='||count(*) FROM core.people WHERE person_id='%s';\n" "$S2"
  printf "SELECT auth.clear_context();\n"; } | app -f - > "$OUT/tF" 2>&1
check "T-F bound session reads S2 basics before valid_until" "$(val BASICS_S2_BEFORE_EXPIRY "$OUT/tF")" 1
check "T-F bound session reads S2 basics after valid_until" "$(val BASICS_S2_AFTER_EXPIRY "$OUT/tF")" 0

echo "== T-D E-R6: case closed while the advisor session is bound (F1)"
t="$(ticket "$P_A1" "$A1" "$F1" ADVISOR 2>&1)"
{ printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$t" "$P_A1"; printf "SELECT pg_sleep(4);\n"
  printf "SELECT 'BASICS_S1_AFTER_CLOSE='||count(*) FROM core.people WHERE person_id='%s';\n" "$S1"
  printf "SELECT 'APP1_AFTER_CLOSE='||count(*) FROM education.applications WHERE application_id='%s';\n" "$APP1"
  printf "SELECT 'CASE_AFTER_CLOSE='||count(*) FROM casework.cases WHERE case_id='%s';\n" "$C1"
  printf "SELECT 'ASSIGN_AFTER_CLOSE='||count(*) FROM casework.advisor_assignments WHERE assignment_id='%s';\n" "$AS1"
  printf "SELECT 'PROFILE_AFTER_CLOSE='||count(*) FROM core.student_profiles WHERE person_id='%s';\n" "$S1"
  printf "SELECT 'MEMBERSHIP_AFTER_CLOSE='||count(*) FROM core.family_memberships WHERE person_id='%s';\n" "$S1"
  printf "SELECT pg_sleep(46);\n"
  printf "SELECT 'BASICS_S1_AFTER_CONTEXT_TTL='||count(*) FROM core.people WHERE person_id='%s';\n" "$S1"
  printf "SELECT auth.clear_context();\n"; } | app -f - > "$OUT/tD" 2>&1 &
sleep 1
svc "$F1" > "$OUT/tD_close" 2>&1 <<SQL
SELECT 'CLOSE_C1='||casework.close_case('$C1');
SQL
wait
check "T-D close_case returns true" "$(val CLOSE_C1 "$OUT/tD_close")" true
check "T-D bound session reads APP1 after case closed (0016 protects applications)" "$(val APP1_AFTER_CLOSE "$OUT/tD")" 0
check "T-D bound session reads the C1 case row after closure (cases_read)" "$(val CASE_AFTER_CLOSE "$OUT/tD")" 0
check "T-D bound session reads the AS1 assignment row after closure (assignments_read)" "$(val ASSIGN_AFTER_CLOSE "$OUT/tD")" 0
check "T-D bound session reads S1 student profile after closure" "$(val PROFILE_AFTER_CLOSE "$OUT/tD")" 0
check "T-D bound session reads S1 membership row after closure" "$(val MEMBERSHIP_AFTER_CLOSE "$OUT/tD")" 0
check "T-D bound session reads S1 basics after case closed (E-R6)" "$(val BASICS_S1_AFTER_CLOSE "$OUT/tD")" 0
check "T-D bound session reads S1 basics after the context TTL (expired context)" "$(val BASICS_S1_AFTER_CONTEXT_TTL "$OUT/tD")" 0
bound "$P_A1" "$A1" "$F1" ADVISOR > "$OUT/tD_rebind" <<SQL
SELECT 1;
SQL
check "T-D a new binding after closure is refused" "$(grep -oE 'BIND_REFUSED [A-Z_]+' "$OUT/tD_rebind")" "BIND_REFUSED CONTEXT_ADVISOR_ASSIGNMENT_INVALID"
boot -At -c "SELECT 'ASSIGN='||lifecycle_status||'|revoked='||(revoked_at IS NOT NULL)||'|valid_now='||(valid_until > clock_timestamp()) FROM casework.advisor_assignments WHERE assignment_id='$AS1'" > "$OUT/tD_state"
boot -At -c "SELECT 'CASE_STATUS='||status FROM casework.cases WHERE case_id='$C1'" >> "$OUT/tD_state"
observe "T-D assignment row after case closure (close_case does not end assignments)" "$(grep -oE 'ASSIGN=.*' "$OUT/tD_state" | cut -d= -f2-)"
observe "T-D case row after closure" "$(grep -oE 'CASE_STATUS=[A-Z]+' "$OUT/tD_state" | cut -d= -f2)"
boot -At -c "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='auth' AND table_name='session_contexts'" > "$OUT/cols"
observe "auth.session_contexts columns (expires_at is copied from the ticket, at most 60 s, and enforced by the current_* helpers)" "$(cat "$OUT/cols")"

echo "SUMMARY findings=$FIND"
[ "$FIND" = 0 ]
