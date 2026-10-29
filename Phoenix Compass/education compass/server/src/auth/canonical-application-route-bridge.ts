import { AppError, invariant } from '../domain/errors'
import type { User } from '../domain/model'
import type { Store } from '../store/store'
import type {
  CanonicalApplicationFamilyContextRequest,
  CanonicalContextExecutor,
} from './canonical-context-gateway'

export type CanonicalFamilyReadOperation =
  | 'FAMILY_PROFILE_READ'
  | 'STUDENT_LIST_READ'
  | 'STUDENT_PROFILE_READ'

type FamilySource = 'AUTHENTICATED_USER' | 'OWNED_STUDENT'

export interface CanonicalFamilyRouteDecision {
  operation: CanonicalFamilyReadOperation
  familySource: FamilySource
  applicationStudentId: string | null
}

export interface CanonicalApplicationBroker {
  issueForApplicationUser(subject: string): { accessToken: string }
}

export interface CanonicalApplicationGateway {
  withApplicationFamilyContext<T>(
    request: CanonicalApplicationFamilyContextRequest,
    work: (client: CanonicalContextExecutor) => Promise<T>
  ): Promise<T>
}

export interface CanonicalApplicationRouteRequest {
  method: string
  pathname: string
  user: Pick<User, 'id' | 'role'>
}

const APPLICATION_USER_ID = /^usr_[A-Za-z0-9_-]{1,128}$/
const APPLICATION_FAMILY_ID = /^fam_[0-9a-f]{32}$/
const APPLICATION_STUDENT_ID = /^stu_[0-9a-f]{32}$/

function denyRoute(): never {
  throw new AppError(403, 'CANONICAL_ROUTE_NOT_APPROVED', '该应用路由未获准接入 Canonical')
}

function decodeStudentId(segment: string): string {
  let value: string
  try {
    value = decodeURIComponent(segment)
  } catch {
    denyRoute()
  }
  if (!APPLICATION_STUDENT_ID.test(value)) denyRoute()
  return value
}

export function canonicalFamilyReadRoute(method: string, pathname: string): CanonicalFamilyRouteDecision {
  if (method !== 'GET') denyRoute()
  if (pathname === '/v1/me/family') {
    return { operation: 'FAMILY_PROFILE_READ', familySource: 'AUTHENTICATED_USER', applicationStudentId: null }
  }
  if (pathname === '/v1/me/students') {
    return { operation: 'STUDENT_LIST_READ', familySource: 'AUTHENTICATED_USER', applicationStudentId: null }
  }
  const student = pathname.match(/^\/v1\/me\/students\/([^/]+)$/)
  if (student?.[1]) {
    return {
      operation: 'STUDENT_PROFILE_READ',
      familySource: 'OWNED_STUDENT',
      applicationStudentId: decodeStudentId(student[1])
    }
  }
  denyRoute()
}

export class CanonicalApplicationRouteBridge {
  constructor(
    private readonly store: Store,
    private readonly broker: CanonicalApplicationBroker,
    private readonly gateway: CanonicalApplicationGateway
  ) {}

  async withApprovedFamilyRead<T>(
    request: CanonicalApplicationRouteRequest,
    work: (client: CanonicalContextExecutor, operation: CanonicalFamilyReadOperation) => Promise<T>
  ): Promise<T> {
    invariant(request.user.role === 'family_user' && APPLICATION_USER_ID.test(request.user.id),
      403, 'CANONICAL_FAMILY_ACTOR_REQUIRED', 'Canonical family route 只接受已认证家庭用户')
    const decision = canonicalFamilyReadRoute(request.method, request.pathname)
    const applicationFamilyId = await this.resolveOwnedApplicationFamily(request.user.id, decision)
    const token = this.broker.issueForApplicationUser(request.user.id)
    return this.gateway.withApplicationFamilyContext({
      accessToken: token.accessToken,
      applicationFamilyId
    }, (client) => work(client, decision.operation))
  }

  private async resolveOwnedApplicationFamily(
    userId: string,
    decision: CanonicalFamilyRouteDecision
  ): Promise<string> {
    return this.store.read(async (tx) => {
      if (decision.familySource === 'AUTHENTICATED_USER') {
        const family = await tx.findOne('families', { userId })
        invariant(family && APPLICATION_FAMILY_ID.test(family.id), 403,
          'CANONICAL_APPLICATION_FAMILY_REQUIRED', '当前用户没有可映射的应用家庭')
        return family.id
      }
      const studentId = decision.applicationStudentId
      invariant(studentId, 403, 'CANONICAL_ROUTE_NOT_APPROVED', 'Canonical 学生路由无效')
      const student = await tx.findById('students', studentId)
      invariant(student, 404, 'STUDENT_NOT_FOUND', '孩子档案不存在')
      const family = await tx.findById('families', student.familyId)
      invariant(family?.userId === userId && APPLICATION_FAMILY_ID.test(family.id), 403,
        'CANONICAL_APPLICATION_FAMILY_FORBIDDEN', '孩子档案不属于当前家庭')
      return family.id
    })
  }
}
