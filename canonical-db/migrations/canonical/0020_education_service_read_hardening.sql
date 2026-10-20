BEGIN;

CREATE OR REPLACE FUNCTION education.can_read_student_record(p_family_id uuid,p_student_person_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, education
RETURN coalesce(
  auth.write_context_is_live() AND auth.current_family_id()=p_family_id
  AND (
    core.actor_can_manage_subject(p_student_person_id,'EDUCATION')
    OR (auth.current_channel()='ADVISOR'
        AND core.can_read_subject_basics(p_student_person_id)
        AND consent.has_active_consent(p_student_person_id,'EDUCATION_CASE','EDUCATION'))
  ),false);

CREATE OR REPLACE FUNCTION education.can_write_student_record(p_family_id uuid,p_student_person_id uuid)
RETURNS boolean
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, auth, core, consent, education
RETURN coalesce(
  education.can_read_student_record(p_family_id,p_student_person_id)
  OR (auth.is_internal_service() AND auth.current_family_id()=p_family_id
      AND core.person_in_current_family(p_student_person_id)),false);

REVOKE EXECUTE ON FUNCTION education.can_read_student_record(uuid,uuid),
  education.can_write_student_record(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION education.can_read_student_record(uuid,uuid),
  education.can_write_student_record(uuid,uuid) TO phoenix_canonical_app;
GRANT EXECUTE ON FUNCTION education.can_read_student_record(uuid,uuid)
  TO phoenix_canonical_reader;

COMMIT;
