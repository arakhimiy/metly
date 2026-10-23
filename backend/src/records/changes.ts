import type { ApiError } from '../common/api-error';
import type { WireRecord } from './mappers';
import type { SyncRecordType } from './wire';

export type SyncStatus = 'applied' | 'stale' | 'rejected';

export interface ApplyResult {
  status: SyncStatus;
  error?: ApiError;
}

type ListType = 'card' | 'event' | 'connection' | 'followUp' | 'connectRequest';

const LIST_KEYS: Record<ListType, 'cards' | 'events' | 'connections' | 'followUps' | 'connectRequests'> = {
  card: 'cards',
  event: 'events',
  connection: 'connections',
  followUp: 'followUps',
  connectRequest: 'connectRequests',
};

/**
 * Canonical records collected while applying writes — the `records` of a push response, a pull page,
 * or what a REST call returns. Later additions of the same id replace earlier ones, and a record and
 * its tombstone never appear together.
 */
export class ChangeSet {
  private profile: WireRecord | null = null;
  private readonly lists = new Map<ListType, Map<string, WireRecord>>();
  private readonly tombstones = new Map<string, { type: SyncRecordType; id: string; deletedAt: string }>();

  record(type: SyncRecordType, record: WireRecord): this {
    const id = record.id as string;
    this.tombstones.delete(`${type}:${id}`);
    if (type === 'profile') {
      this.profile = record;
      return this;
    }
    let list = this.lists.get(type);
    if (!list) {
      list = new Map();
      this.lists.set(type, list);
    }
    list.set(id, record);
    return this;
  }

  tombstone(type: SyncRecordType, id: string, deletedAt: Date | string): this {
    if (type === 'profile') {
      if (this.profile?.id === id) this.profile = null;
    } else {
      this.lists.get(type)?.delete(id);
    }
    this.tombstones.set(`${type}:${id}`, {
      type,
      id,
      deletedAt: typeof deletedAt === 'string' ? deletedAt : deletedAt.toISOString(),
    });
    return this;
  }

  get isEmpty(): boolean {
    return !this.profile && this.tombstones.size === 0 && [...this.lists.values()].every((l) => l.size === 0);
  }

  first(type: Exclude<SyncRecordType, 'profile'>): WireRecord | undefined {
    return this.lists.get(type)?.values().next().value;
  }

  get(type: SyncRecordType, id: string): WireRecord | undefined {
    if (type === 'profile') return this.profile?.id === id ? this.profile : undefined;
    return this.lists.get(type)?.get(id);
  }

  getProfile(): WireRecord | null {
    return this.profile;
  }

  hasTombstone(type: SyncRecordType, id: string): boolean {
    return this.tombstones.has(`${type}:${id}`);
  }

  toWire(): WireRecord {
    const out: WireRecord = {};
    if (this.profile) out.profile = this.profile;
    for (const [type, key] of Object.entries(LIST_KEYS) as [ListType, string][]) {
      out[key] = [...(this.lists.get(type)?.values() ?? [])];
    }
    out.tombstones = [...this.tombstones.values()];
    return out;
  }
}
