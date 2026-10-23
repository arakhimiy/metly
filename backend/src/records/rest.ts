import { ApiError } from '../common/api-error';
import type { ApplyResult, ChangeSet } from './changes';
import type { WireRecord } from './mappers';
import type { SyncRecordType } from './wire';

/**
 * Turns a write result into a REST answer: the canonical record (also when stale), `410 gone` when
 * the server holds a newer tombstone, the error when rejected.
 */
export function restRecord(type: SyncRecordType, id: string, result: ApplyResult, out: ChangeSet): WireRecord {
  if (result.status === 'rejected') throw result.error ?? ApiError.badRequest('Rejected.');
  const record = type === 'profile' ? out.getProfile() : out.get(type, id);
  if (record) return record;
  if (out.hasTombstone(type, id)) throw ApiError.gone();
  // A merged connection: the survivor is the canonical record.
  const survivor = type === 'connection' ? out.first('connection') : undefined;
  if (survivor) return survivor;
  throw ApiError.gone();
}

/** Path id and body id must agree on create-or-update by client id. */
export function assertSameId(pathId: string, body: unknown): void {
  const bodyId = (body as { id?: unknown } | null)?.id;
  if (typeof bodyId === 'string' && bodyId.toLowerCase() !== pathId.toLowerCase()) {
    throw ApiError.validation({ id: 'must match the id in the path' });
  }
}

export function withPathId(pathId: string, body: unknown): unknown {
  assertSameId(pathId, body);
  return body && typeof body === 'object' ? { ...body, id: pathId } : body;
}

export const UUID_PARAM = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export function pathUuid(value: string, name = 'id'): string {
  if (!UUID_PARAM.test(value)) throw ApiError.validation({ [name]: 'must be a UUID' });
  return value.toLowerCase();
}
