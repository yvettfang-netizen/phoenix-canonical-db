#!/usr/bin/env bash
set -euo pipefail
app_psql() { PGPASSFILE=/tmp/f10-app.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_app_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
binder_psql() { PGPASSFILE=/tmp/f10-binder.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_binder_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
backup_psql() { PGPASSFILE=/tmp/f10-backup.pgpass psql -X -q -h 127.0.0.1 -U phoenix_canonical_backup_f10 -d phoenix_canonical_dev -v ON_ERROR_STOP=1 "$@"; }
FA=018f0000-0000-7000-8000-000000000001
SVC_P=018f0000-0000-7000-8000-000000002001
G_P=018f0000-0000-7000-8000-000000002002; G=018f0000-0000-7000-8000-000000001002
STU_P=018f0000-0000-7000-8000-000000002003; STU=018f0000-0000-7000-8000-000000001003
ADV_P=018f0000-0000-7000-8000-000000002004; ADV=018f0000-0000-7000-8000-000000001004
CH_P=018f0000-0000-7000-8000-000000002005; CH=018f0000-0000-7000-8000-000000001005
SUB_B=018f0000-0000-7000-8000-000000001011
APP_B=018f0000-0000-7000-8000-00000000b601
M1=018f0000-0000-7000-8000-00000000b701
M2=018f0000-0000-7000-8000-00000000b702
DOC_B=018f0000-0000-7000-8000-00000000b501; VER_B=018f0000-0000-7000-8000-00000000b511
DOC_SELF=018f0000-0000-7000-8000-00000000b502; VER_SELF=018f0000-0000-7000-8000-00000000b512
DOC_ID=018f0000-0000-7000-8000-00000000b503
DOC_SERVICE=018f0000-0000-7000-8000-00000000b504

session() { # principal actor family channel; SQL on stdin
  local actor="'$2'::uuid" family="'$3'::uuid" ticket
  [ "$2" = NULL ] && actor=NULL
  [ "$3" = NULL ] && family=NULL
  ticket="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('$1',$actor,$family,'$4',clock_timestamp()+interval '45 seconds',gen_random_uuid(),'$1')")"
  { printf "SELECT auth.redeem_context_ticket('%s','%s');\n" "$ticket" "$1"; cat; printf '\nSELECT auth.clear_context();\n'; } | app_psql -At -f -
}
expect_line() { grep -qx "$1" <<<"$2" || { printf 'FAIL expected [%s] in:\n%s\n' "$1" "$2"; exit 1; }; echo "PASS $1"; }

out="$(session "$SVC_P" NULL "$FA" INTERNAL <<SQL
SELECT 'T1_PERSON='||core.create_person('018f0000-0000-7000-8000-00000000b101','Synthetic Ending Member','$FA','018f0000-0000-7000-8000-00000000b201','MEMBER');
SELECT 'T1_PRINCIPAL='||auth.create_login_principal('018f0000-0000-7000-8000-00000000b301','018f0000-0000-7000-8000-00000000b101','FAMILY');
SELECT 'T1_RENAME_PERSON='||core.rename_person('018f0000-0000-7000-8000-00000000b101','Synthetic Renamed Member');
SELECT 'T1_RENAME_FAMILY='||core.rename_family('$FA','Synthetic Renamed Family A');
SELECT 'T1_CROSS_PERSON='||core.rename_person('018f0000-0000-7000-8000-000000001006','Forbidden Cross Family Name');
SELECT 'T1_CROSS_FAMILY='||core.rename_family('018f0000-0000-7000-8000-000000000002','Forbidden Cross Family');
SELECT 'T1_END='||core.end_family_membership('018f0000-0000-7000-8000-00000000b201',clock_timestamp()+interval '2 seconds');
SELECT 'T1_EXTEND='||core.end_family_membership('018f0000-0000-7000-8000-00000000b201',clock_timestamp()+interval '1 day');
SELECT 'AUTH_GENERAL='||core.create_guardian_authority('018f0000-0000-7000-8000-00000000b401','$FA','$G','$SUB_B','VERIFIED','GENERAL',clock_timestamp()+interval '1 day','synthetic/v16/general');
SELECT 'AUTH_EDUCATION='||core.create_guardian_authority('018f0000-0000-7000-8000-00000000b402','$FA','$G','$SUB_B','VERIFIED','EDUCATION',clock_timestamp()+interval '1 day','synthetic/v16/education');
SELECT 'DOC_B='||docs.create_document('$DOC_B','$FA','$SUB_B','EDUCATION','Synthetic Subject B Document',clock_timestamp()+interval '1 year');
SELECT 'VER_B='||docs.append_document_version('$VER_B','$DOC_B',1,repeat('d',64)::char(64),'mock/v16/subject-b',10);
SELECT 'DOC_SELF='||docs.create_document('$DOC_SELF','$FA','$STU','GENERAL','Synthetic Self Document',clock_timestamp()+interval '1 year');
SELECT 'VER_SELF='||docs.append_document_version('$VER_SELF','$DOC_SELF',1,repeat('e',64)::char(64),'mock/v16/self-doc',10);
SELECT 'DOC_ID='||docs.create_document('$DOC_ID','$FA','$SUB_B','IDENTITY_SENSITIVE','Synthetic Identity Document',clock_timestamp()+interval '1 year');
SELECT 'DOC_SERVICE='||docs.create_document('$DOC_SERVICE','$FA','$STU','EDUCATION','Synthetic Service Withdrawal',clock_timestamp()+interval '1 year');
SQL
)"
for key in T1_PERSON T1_PRINCIPAL T1_RENAME_PERSON T1_RENAME_FAMILY T1_END AUTH_GENERAL AUTH_EDUCATION DOC_B VER_B DOC_SELF VER_SELF DOC_ID DOC_SERVICE; do expect_line "$key=true" "$out"; done
for key in T1_CROSS_PERSON T1_CROSS_FAMILY T1_EXTEND; do expect_line "$key=false" "$out"; done

out="$(session "$G_P" "$G" "$FA" FAMILY <<SQL
SELECT 'T1_NON_SERVICE_PERSON='||core.rename_person('$G','Forbidden Family Rename');
SELECT 'T1_NON_SERVICE_FAMILY='||core.rename_family('$FA','Forbidden Family Rename');
SELECT 'T1_NON_SERVICE_END='||core.end_family_membership('018f0000-0000-7000-8000-000000003002',clock_timestamp()+interval '1 hour');
SELECT 'C_DOC_ADV='||consent.create_grant('018f0000-0000-7000-8000-00000000b411','$FA','$ADV','$SUB_B','DOCUMENT_READ','EDUCATION',clock_timestamp()+interval '1 day');
SELECT 'C_CASE_ADV='||consent.create_grant('018f0000-0000-7000-8000-00000000b412','$FA','$ADV','$SUB_B','EDUCATION_CASE','EDUCATION',clock_timestamp()+interval '1 day');
SELECT 'C_DOC_G='||consent.create_grant('018f0000-0000-7000-8000-00000000b413','$FA','$G','$SUB_B','DOCUMENT_READ','EDUCATION',clock_timestamp()+interval '1 day');
SELECT 'APP_B='||education.create_application('$APP_B','$FA','$SUB_B','Synthetic V16 Institution','Synthetic V16 Program','2030');
SELECT 'M1='||docs.create_submission_manifest('$M1','$FA','$SUB_B','EDUCATION_APPLICATION','$APP_B');
SELECT 'M2='||docs.create_submission_manifest('$M2','$FA','$SUB_B','EDUCATION_APPLICATION','$APP_B');
SELECT 'ID_DRAFT='||identity.create_case('018f0000-0000-7000-8000-00000000b801','$FA','$STU','Synthetic Draft Close');
SELECT 'ID_DRAFT_CLOSE='||identity.advance_case('018f0000-0000-7000-8000-00000000b801','CLOSED');
SELECT 'ID_CLOSED_FORWARD='||identity.advance_case('018f0000-0000-7000-8000-00000000b801','EVIDENCE_PENDING');
SELECT 'ID_PENDING='||identity.create_case('018f0000-0000-7000-8000-00000000b802','$FA','$STU','Synthetic Pending Close');
SELECT 'ID_TO_PENDING='||identity.advance_case('018f0000-0000-7000-8000-00000000b802','EVIDENCE_PENDING');
SELECT 'ID_PENDING_CLOSE='||identity.advance_case('018f0000-0000-7000-8000-00000000b802','CLOSED');
SELECT 'ID_NO_ADVISOR='||identity.create_case('018f0000-0000-7000-8000-00000000b803','$FA','$STU','Synthetic Advisor Denied');
SQL
)"
for key in C_DOC_ADV C_CASE_ADV C_DOC_G APP_B M1 M2 ID_DRAFT ID_DRAFT_CLOSE ID_PENDING ID_TO_PENDING ID_PENDING_CLOSE ID_NO_ADVISOR; do expect_line "$key=true" "$out"; done
for key in T1_NON_SERVICE_PERSON T1_NON_SERVICE_FAMILY T1_NON_SERVICE_END ID_CLOSED_FORWARD; do expect_line "$key=false" "$out"; done

out="$(session "$ADV_P" "$ADV" "$FA" ADVISOR <<SQL
SELECT 'T2_READ_BEFORE='||docs.can_read_document('$SUB_B','EDUCATION');
SELECT 'T2_ADD_BEFORE='||docs.add_submission_item('$M1',1,'$VER_B');
SELECT 'T4_ADVISOR_NO_ASSIGNMENT='||identity.advance_case('018f0000-0000-7000-8000-00000000b803','CLOSED');
SQL
)"
expect_line 'T2_READ_BEFORE=false' "$out"; expect_line 'T2_ADD_BEFORE=false' "$out"; expect_line 'T4_ADVISOR_NO_ASSIGNMENT=false' "$out"

out="$(session "$SVC_P" NULL "$FA" INTERNAL <<SQL
SELECT 'T2_CASE='||casework.create_case('018f0000-0000-7000-8000-00000000b901','$FA','$SUB_B','Synthetic Subject B Assignment','EDUCATION_APPLICATION','$APP_B');
SELECT 'T2_ASSIGN='||casework.create_advisor_assignment('018f0000-0000-7000-8000-00000000b911','018f0000-0000-7000-8000-00000000b901','$ADV',clock_timestamp()+interval '1 day');
SQL
)"
expect_line 'T2_CASE=true' "$out"; expect_line 'T2_ASSIGN=true' "$out"

out="$(session "$ADV_P" "$ADV" "$FA" ADVISOR <<SQL
SELECT 'T2_READ_ACTIVE='||docs.can_read_document('$SUB_B','EDUCATION');
SELECT 'T2_ADD_M1='||docs.add_submission_item('$M1',1,'$VER_B');
SELECT 'T2_ADD_M2='||docs.add_submission_item('$M2',1,'$VER_B');
SQL
)"
expect_line 'T2_READ_ACTIVE=true' "$out"; expect_line 'T2_ADD_M1=true' "$out"; expect_line 'T2_ADD_M2=true' "$out"

out="$(session "$G_P" "$G" "$FA" FAMILY <<SQL
SELECT 'T2_CONFIRM_M1='||docs.confirm_manifest('$M1');
SELECT 'T2_CONFIRM_M2='||docs.confirm_manifest('$M2');
SQL
)"
expect_line 'T2_CONFIRM_M1=true' "$out"; expect_line 'T2_CONFIRM_M2=true' "$out"
out="$(session "$ADV_P" "$ADV" "$FA" ADVISOR <<SQL
SELECT 'T2_SUBMIT_ACTIVE='||docs.submit_manifest('$M1');
SQL
)"; expect_line 'T2_SUBMIT_ACTIVE=true' "$out"

out="$(session "$SVC_P" NULL "$FA" INTERNAL <<SQL
SELECT 'T2_REVOKE='||casework.revoke_advisor_assignment('018f0000-0000-7000-8000-00000000b911');
SQL
)"; expect_line 'T2_REVOKE=true' "$out"
out="$(session "$ADV_P" "$ADV" "$FA" ADVISOR <<SQL
SELECT 'T2_READ_REVOKED='||docs.can_read_document('$SUB_B','EDUCATION');
SELECT 'T2_SUBMIT_REVOKED='||docs.submit_manifest('$M2');
SQL
)"
expect_line 'T2_READ_REVOKED=false' "$out"; expect_line 'T2_SUBMIT_REVOKED=false' "$out"

out="$(session "$SVC_P" NULL "$FA" INTERNAL <<SQL
SELECT 'T2_ASSIGN_SHORT='||casework.create_advisor_assignment('018f0000-0000-7000-8000-00000000b912','018f0000-0000-7000-8000-00000000b901','$ADV',clock_timestamp()+interval '2 seconds');
SQL
)"; expect_line 'T2_ASSIGN_SHORT=true' "$out"
sleep 3
out="$(session "$ADV_P" "$ADV" "$FA" ADVISOR <<SQL
SELECT 'T2_READ_EXPIRED='||docs.can_read_document('$SUB_B','EDUCATION');
SQL
)"; expect_line 'T2_READ_EXPIRED=false' "$out"

out="$(session "$SVC_P" NULL "$FA" INTERNAL <<SQL
SELECT 'T1_ENDED_IMMUTABLE='||core.end_family_membership('018f0000-0000-7000-8000-00000000b201',clock_timestamp()+interval '1 day');
SELECT 'T3_SERVICE='||docs.withdraw_document('$DOC_SERVICE');
SQL
)"
expect_line 'T1_ENDED_IMMUTABLE=false' "$out"; expect_line 'T3_SERVICE=true' "$out"
if ticket_error="$(binder_psql -Atqc "SELECT auth.issue_context_ticket('018f0000-0000-7000-8000-00000000b301','018f0000-0000-7000-8000-00000000b101','$FA','FAMILY',clock_timestamp()+interval '30 seconds',gen_random_uuid(),'018f0000-0000-7000-8000-00000000b301')" 2>&1)"; then
  echo 'FAIL T1 ended member received FAMILY ticket'; exit 1
fi
[[ "$ticket_error" == *CONTEXT_FAMILY_MEMBERSHIP_INVALID* ]] || { echo "$ticket_error"; exit 1; }
echo 'PASS T1 ended member ticket denied CONTEXT_FAMILY_MEMBERSHIP_INVALID'

out="$(session "$STU_P" "$STU" "$FA" FAMILY <<SQL
SELECT 'T3_SELF='||docs.withdraw_document('$DOC_SELF');
SELECT 'T3_REPEAT='||docs.withdraw_document('$DOC_SELF');
SQL
)"
expect_line 'T3_SELF=true' "$out"; expect_line 'T3_REPEAT=false' "$out"

out="$(session "$ADV_P" "$ADV" "$FA" ADVISOR <<SQL
SELECT 'T3_ADVISOR='||docs.withdraw_document('$DOC_ID');
SQL
)"; expect_line 'T3_ADVISOR=false' "$out"
out="$(session "$CH_P" "$CH" "$FA" PARTNER <<SQL
SELECT 'T3_CHANNEL='||docs.withdraw_document('$DOC_ID');
SQL
)"; expect_line 'T3_CHANNEL=false' "$out"

out="$(session "$G_P" "$G" "$FA" FAMILY <<SQL
SELECT 'T3_SCOPE_MISMATCH='||docs.withdraw_document('$DOC_ID');
SELECT 'T3_GUARDIAN='||docs.withdraw_document('$DOC_B');
SELECT 'T3_NEW_MANIFEST='||docs.create_submission_manifest('018f0000-0000-7000-8000-00000000b703','$FA','$STU','EDUCATION_APPLICATION','018f0000-0000-7000-8000-000000004001');
SELECT 'T3_ADD_WITHDRAWN='||docs.add_submission_item('018f0000-0000-7000-8000-00000000b703',1,'$VER_SELF');
SELECT 'T3_SUBMITTED_MANIFEST_VISIBLE='||count(*) FROM docs.submission_manifests WHERE submission_id='$M1' AND status='SUBMITTED';
SELECT 'T3_SUBMITTED_ITEM_VISIBLE='||count(*) FROM docs.submission_items WHERE submission_id='$M1';
SQL
)"
expect_line 'T3_SCOPE_MISMATCH=false' "$out"; expect_line 'T3_GUARDIAN=true' "$out"
expect_line 'T3_NEW_MANIFEST=true' "$out"; expect_line 'T3_ADD_WITHDRAWN=false' "$out"
expect_line 'T3_SUBMITTED_MANIFEST_VISIBLE=1' "$out"; expect_line 'T3_SUBMITTED_ITEM_VISIBLE=1' "$out"

out="$(session "$SVC_P" NULL "$FA" INTERNAL <<SQL
SELECT 'T3_CONFIRMED_SUBMIT_WITHDRAWN='||docs.submit_manifest('$M2');
SQL
)"; expect_line 'T3_CONFIRMED_SUBMIT_WITHDRAWN=false' "$out"

test "$(backup_psql -Atqc "SELECT status FROM identity.cases WHERE identity_case_id IN ('018f0000-0000-7000-8000-00000000b801','018f0000-0000-7000-8000-00000000b802') GROUP BY status")" = CLOSED
echo 'PASS V1.6 T1-T4 split-LOGIN one-use-ticket synthetic regression'
