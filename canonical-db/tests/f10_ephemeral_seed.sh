#!/usr/bin/env bash
set -euo pipefail
umask 077
export PGPASSFILE=/tmp/f10-bootstrap.pgpass

app_secret="$(openssl rand -hex 32)"
binder_secret="$(openssl rand -hex 32)"
backup_secret="$(openssl rand -hex 32)"
printf '127.0.0.1:5432:*:phoenix_canonical_app_f10:%s\n' "$app_secret" > /tmp/f10-app.pgpass
printf '127.0.0.1:5432:*:phoenix_canonical_binder_f10:%s\n' "$binder_secret" > /tmp/f10-binder.pgpass
printf '127.0.0.1:5432:*:phoenix_canonical_backup_f10:%s\n' "$backup_secret" > /tmp/f10-backup.pgpass
chmod 600 /tmp/f10-app.pgpass /tmp/f10-binder.pgpass /tmp/f10-backup.pgpass

psql -q -X -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE phoenix_canonical_app_f10 LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$app_secret';
CREATE ROLE phoenix_canonical_binder_f10 LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$binder_secret';
CREATE ROLE phoenix_canonical_backup_f10 LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS PASSWORD '$backup_secret';
GRANT phoenix_canonical_app TO phoenix_canonical_app_f10 WITH INHERIT TRUE, SET FALSE;
GRANT phoenix_canonical_context_binder TO phoenix_canonical_binder_f10 WITH INHERIT TRUE, SET FALSE;
GRANT pg_read_all_data TO phoenix_canonical_backup_f10 WITH INHERIT TRUE, SET FALSE;
GRANT CONNECT ON DATABASE phoenix_canonical_dev TO phoenix_canonical_app_f10, phoenix_canonical_binder_f10, phoenix_canonical_backup_f10;
SQL
unset app_secret binder_secret backup_secret

psql -q -X -h 127.0.0.1 -U phoenix_bootstrap -d phoenix_canonical_dev -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO core.people(person_id,display_name) VALUES
 ('018f0000-0000-7000-8000-000000001001','Synthetic Service'),
 ('018f0000-0000-7000-8000-000000001002','Synthetic Guardian A'),
 ('018f0000-0000-7000-8000-000000001003','Synthetic Student A'),
 ('018f0000-0000-7000-8000-000000001004','Synthetic Advisor'),
 ('018f0000-0000-7000-8000-000000001005','Synthetic Partner'),
 ('018f0000-0000-7000-8000-000000001006','Synthetic Family B');
INSERT INTO core.families(family_id,display_name) VALUES
 ('018f0000-0000-7000-8000-000000000001','Synthetic Family A'),
 ('018f0000-0000-7000-8000-000000000002','Synthetic Family B');
INSERT INTO core.family_memberships(membership_id,family_id,person_id,membership_role,valid_from) VALUES
 ('018f0000-0000-7000-8000-000000003001','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002','PRIMARY',clock_timestamp()-interval '1 day'),
 ('018f0000-0000-7000-8000-000000003002','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003','MEMBER',clock_timestamp()-interval '1 day'),
 ('018f0000-0000-7000-8000-000000003003','018f0000-0000-7000-8000-000000000002','018f0000-0000-7000-8000-000000001006','PRIMARY',clock_timestamp()-interval '1 day');
INSERT INTO core.student_profiles(person_id) VALUES ('018f0000-0000-7000-8000-000000001003');
INSERT INTO core.guardian_authorities(authority_id,family_id,guardian_person_id,subject_person_id,evidence_level,scope,valid_from,valid_until) VALUES
 ('018f0000-0000-7000-8000-000000003011','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002','018f0000-0000-7000-8000-000000001003','VERIFIED','EDUCATION',clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day'),
 ('018f0000-0000-7000-8000-000000003012','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001002','018f0000-0000-7000-8000-000000001003','VERIFIED','IDENTITY',clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day');
INSERT INTO auth.principals(principal_id,person_id,principal_kind,status) VALUES
 ('018f0000-0000-7000-8000-000000002001','018f0000-0000-7000-8000-000000001001','SERVICE','ACTIVE'),
 ('018f0000-0000-7000-8000-000000002002','018f0000-0000-7000-8000-000000001002','FAMILY','ACTIVE'),
 ('018f0000-0000-7000-8000-000000002003','018f0000-0000-7000-8000-000000001003','FAMILY','ACTIVE'),
 ('018f0000-0000-7000-8000-000000002004','018f0000-0000-7000-8000-000000001004','ADVISOR','ACTIVE'),
 ('018f0000-0000-7000-8000-000000002005','018f0000-0000-7000-8000-000000001005','CHANNEL','ACTIVE'),
 ('018f0000-0000-7000-8000-000000002006','018f0000-0000-7000-8000-000000001006','FAMILY','ACTIVE');
INSERT INTO casework.cases(case_id,family_id,subject_person_id,title,status,resource_kind,resource_id) VALUES
 ('018f0000-0000-7000-8000-000000004011','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003','Synthetic Education Work','OPEN','EDUCATION_APPLICATION','018f0000-0000-7000-8000-000000004001'),
 ('018f0000-0000-7000-8000-000000004012','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003','Synthetic Identity Work','OPEN','IDENTITY_CASE','018f0000-0000-7000-8000-000000004002'),
 ('018f0000-0000-7000-8000-000000004013','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003','Synthetic Advisor Education Create','OPEN','EDUCATION_APPLICATION','018f0000-0000-7000-8000-000000004005'),
 ('018f0000-0000-7000-8000-000000004014','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003','Synthetic Advisor Identity Create','OPEN','IDENTITY_CASE','018f0000-0000-7000-8000-000000004006');
INSERT INTO casework.advisor_assignments(assignment_id,case_id,advisor_person_id,valid_from,valid_until) VALUES
 ('018f0000-0000-7000-8000-000000004021','018f0000-0000-7000-8000-000000004011','018f0000-0000-7000-8000-000000001004',clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day'),
 ('018f0000-0000-7000-8000-000000004022','018f0000-0000-7000-8000-000000004012','018f0000-0000-7000-8000-000000001004',clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day'),
 ('018f0000-0000-7000-8000-000000004023','018f0000-0000-7000-8000-000000004013','018f0000-0000-7000-8000-000000001004',clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day'),
 ('018f0000-0000-7000-8000-000000004024','018f0000-0000-7000-8000-000000004014','018f0000-0000-7000-8000-000000001004',clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day');
INSERT INTO integration.channel_grants(channel_grant_id,principal_id,family_id,subject_person_id,channel,valid_from,valid_until) VALUES
 ('018f0000-0000-7000-8000-000000004031','018f0000-0000-7000-8000-000000002005','018f0000-0000-7000-8000-000000000001','018f0000-0000-7000-8000-000000001003','PARTNER',clock_timestamp()-interval '1 day',clock_timestamp()+interval '1 day');
SQL

echo 'SEED synthetic actors=6 families=2 guardian_authorities=2 assignments=4'
