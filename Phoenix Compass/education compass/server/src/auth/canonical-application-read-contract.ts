import type { QueryResultRow } from 'pg'
import { invariant } from '../domain/errors'
import type { Family, Student } from '../domain/model'
import type { CanonicalContextExecutor } from './canonical-context-gateway'
import type { CanonicalFamilyReadOperation } from './canonical-application-route-bridge'

const UUID_V7 = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

interface CanonicalFamilyRlsEvidence extends QueryResultRow {
  family_id: string
  channel: string
}

/**
 * Canonical is an authorization gate for the first three approved reads. The
 * application Store remains the response source until student/person mapping
 * authority is approved. This query deliberately returns no business fields.
 */
export async function requireCanonicalFamilyRls(
  client: CanonicalContextExecutor,
  _operation: CanonicalFamilyReadOperation
): Promise<void> {
  const result = await client.query<CanonicalFamilyRlsEvidence>(
    `SELECT family_id::text, auth.current_channel() AS channel
       FROM core.families
      WHERE family_id = auth.current_family_id()`
  )
  const row = result.rows[0]
  invariant(result.rowCount === 1 && row && UUID_V7.test(row.family_id) && row.channel === 'FAMILY',
    403, 'CANONICAL_RLS_FAMILY_DENIED', 'Canonical 家庭访问被拒绝')
}

export function familyReadDto(family: Family | null): Family | null {
  if (!family) return null
  return {
    id: family.id,
    userId: family.userId,
    familyName: family.familyName,
    parentName: family.parentName,
    phone: family.phone,
    location: family.location,
    goal: family.goal,
    ...(family.profileStatus !== undefined ? { profileStatus: family.profileStatus } : {}),
    ...(family.profileSchemaVersion !== undefined ? { profileSchemaVersion: family.profileSchemaVersion } : {}),
    createdAt: family.createdAt,
    updatedAt: family.updatedAt
  }
}

export function studentReadDto(student: Student): Student {
  return {
    id: student.id,
    familyId: student.familyId,
    name: student.name,
    ...(student.age !== undefined ? { age: student.age } : {}),
    ...(student.gender !== undefined ? { gender: student.gender } : {}),
    ...(student.school !== undefined ? { school: student.school } : {}),
    ...(student.educationSystem !== undefined ? { educationSystem: student.educationSystem } : {}),
    ...(student.grade !== undefined ? { grade: student.grade } : {}),
    ...(student.interest !== undefined ? { interest: student.interest } : {}),
    ...(student.goal !== undefined ? { goal: student.goal } : {}),
    studentVersion: student.studentVersion,
    ...(student.profileStatus !== undefined ? { profileStatus: student.profileStatus } : {}),
    ...(student.profileSchemaVersion !== undefined ? { profileSchemaVersion: student.profileSchemaVersion } : {}),
    ...(student.gradeStage !== undefined ? { gradeStage: student.gradeStage } : {}),
    createdAt: student.createdAt,
    updatedAt: student.updatedAt
  }
}
