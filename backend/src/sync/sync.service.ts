import { Inject, Injectable } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { decodeCursor, encodeCursor } from '../common/cursor';
import { iso } from '../common/time';
import { zodDetails } from '../common/validate';
import { ENV, type Env } from '../config/env';
import { ConnectRequestView } from '../connect/connect-request.view';
import { Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { type ApplyResult, ChangeSet } from '../records/changes';
import { cardToWire, connectionToWire, eventToWire, followUpToWire, profileToWire } from '../records/mappers';
import { RecordsService } from '../records/records.service';
import { CardIn, ConnectionIn, EventIn, FollowUpIn, ProfileIn, type SyncRecordType, TombstoneIn } from '../records/wire';
import { EntitlementsService } from '../subscriptions/entitlements.service';

export const MAX_PUSH_CHANGES = 500;

/** Push body: records stay raw so one invalid record is rejected alone instead of failing the batch. */
const PushBody = z.object({
  deviceId: z.string().max(200).nullish(),
  changes: z.object({
    profile: z.unknown().nullish(),
    cards: z.array(z.unknown()).nullish(),
    events: z.array(z.unknown()).nullish(),
    connections: z.array(z.unknown()).nullish(),
    followUps: z.array(z.unknown()).nullish(),
    connectRequests: z.array(z.unknown()).nullish(),
    tombstones: z.array(z.unknown()).nullish(),
  }),
});

interface SyncResult {
  type: SyncRecordType;
  id: string;
  status: ApplyResult['status'];
  error?: ReturnType<ApiError['toBody']>;
}

const TOMBSTONE_ORDER: SyncRecordType[] = ['followUp', 'connection', 'event', 'card', 'profile', 'connectRequest'];

function rawId(value: unknown): string {
  const id = (value as { id?: unknown } | null)?.id;
  return typeof id === 'string' ? id.toLowerCase() : '00000000-0000-0000-0000-000000000000';
}

@Injectable()
export class SyncService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    private readonly requests: ConnectRequestView,
    private readonly entitlements: EntitlementsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /**
   * POST /v1/sync/push. Upserts in dependency order (profile → cards → events → connections →
   * follow-ups), then tombstones children-first. Each change is independent: it gets its own
   * savepoint-free mini transaction, so a rejected record never rolls back the others.
   */
  async push(userId: string, body: unknown) {
    const parsed = PushBody.safeParse(body);
    if (!parsed.success) throw ApiError.validation(zodDetails(parsed.error));
    const { changes, deviceId } = parsed.data;
    const total =
      (changes.profile ? 1 : 0) +
      (changes.cards?.length ?? 0) +
      (changes.events?.length ?? 0) +
      (changes.connections?.length ?? 0) +
      (changes.followUps?.length ?? 0) +
      (changes.tombstones?.length ?? 0);
    if (total > MAX_PUSH_CHANGES) {
      throw new ApiError(413, 'payload_too_large', `Push at most ${MAX_PUSH_CHANGES} changes per call.`);
    }

    const out = new ChangeSet();
    const results: SyncResult[] = [];
    const apply = async <S extends z.ZodType>(type: SyncRecordType, schema: S, raw: unknown, fn: (value: z.infer<S>) => Promise<ApplyResult>) => {
      const value = schema.safeParse(raw);
      const id = value.success ? (value.data as { id: string }).id : rawId(raw);
      if (!value.success) {
        results.push({ type, id, status: 'rejected', error: ApiError.validation(zodDetails(value.error)).toBody() });
        return;
      }
      const result = await fn(value.data);
      results.push({ type, id, status: result.status, ...(result.error ? { error: result.error.toBody() } : {}) });
    };
    const run = (fn: (ctx: Parameters<Parameters<RecordsService['write']>[1]>[0]) => Promise<ApplyResult>) =>
      this.records.write(userId, fn, deviceId).then(({ result, out: changeSet }) => {
        merge(out, changeSet);
        return result;
      });

    if (changes.profile) await apply('profile', ProfileIn, changes.profile, (p) => run((ctx) => this.records.upsertProfile(ctx, p)));
    for (const raw of changes.cards ?? []) await apply('card', CardIn, raw, (c) => run((ctx) => this.records.upsertCard(ctx, c)));
    for (const raw of changes.events ?? []) await apply('event', EventIn, raw, (e) => run((ctx) => this.records.upsertEvent(ctx, e)));
    for (const raw of changes.connections ?? [])
      await apply('connection', ConnectionIn, raw, (c) => run((ctx) => this.records.upsertConnection(ctx, c)));
    for (const raw of changes.followUps ?? [])
      await apply('followUp', FollowUpIn, raw, (f) => run((ctx) => this.records.upsertFollowUp(ctx, f)));

    const tombstones = [...(changes.tombstones ?? [])].sort((a, b) => {
      const ta = TOMBSTONE_ORDER.indexOf((a as { type?: SyncRecordType })?.type ?? 'profile');
      const tb = TOMBSTONE_ORDER.indexOf((b as { type?: SyncRecordType })?.type ?? 'profile');
      return ta - tb;
    });
    for (const raw of tombstones) {
      const type = ((raw as { type?: unknown })?.type as SyncRecordType) ?? 'profile';
      await apply(type, TombstoneIn, raw, (t) => run((ctx) => this.records.applyTombstone(ctx, t)));
    }

    return { results, records: out.toWire(), serverTime: iso(new Date()) };
  }

  /**
   * GET /v1/sync. Every record with seq > cursor, ordered by seq, `limit` per page. Read in one
   * repeatable-read snapshot so the returned cursor matches exactly what the page contains.
   */
  async pull(userId: string, since: string | undefined, limitRaw: string | undefined) {
    const limit = Math.min(1000, Math.max(1, Number.parseInt(limitRaw ?? '500', 10) || 500));
    const fullSnapshot = since === undefined || since === '';
    const now = new Date();

    return this.prisma.$transaction(
      async (tx) => {
        const user = await tx.user.findUnique({ where: { id: userId }, select: { seq: true, tombstoneFloorSeq: true } });
        if (!user) throw ApiError.unauthorized('This account no longer exists.');
        const after = fullSnapshot ? 0n : decodeCursor(since);
        if (!fullSnapshot && (after > user.seq || after < user.tombstoneFloorSeq)) {
          throw new ApiError(410, 'cursor_expired', 'The sync cursor is no longer valid. Pull again without `since`.');
        }
        const take = limit + 1;
        const where = { userId, seq: { gt: after } };
        const live = fullSnapshot ? { deletedAt: null } : {};
        const order = { seq: 'asc' } as const;
        const [profiles, cards, events, connections, followUps, outgoing, incoming] = await Promise.all([
          tx.profile.findMany({ where: { ...where, ...live }, orderBy: order, take }),
          tx.card.findMany({ where: { ...where, ...live }, orderBy: order, take }),
          tx.event.findMany({ where: { ...where, ...live }, orderBy: order, take }),
          tx.connection.findMany({ where: { ...where, ...live }, orderBy: order, take }),
          tx.followUp.findMany({ where: { ...where, ...live }, orderBy: order, take }),
          tx.connectRequest.findMany({ where: { fromUserId: userId, fromSeq: { gt: after } }, orderBy: { fromSeq: 'asc' }, take }),
          tx.connectRequest.findMany({
            where: { toUserId: userId, toSeq: { gt: after }, isSuppressed: false },
            orderBy: { toSeq: 'asc' },
            take,
          }),
        ]);

        type Item = { seq: bigint; emit: (out: ChangeSet) => unknown };
        const linksPaused = profiles[0]
          ? profiles[0].linksPaused && !profiles[0].deletedAt
          : ((await tx.profile.findUnique({ where: { userId }, select: { linksPaused: true } }))?.linksPaused ?? false);
        const cardCtx = { webBaseUrl: this.env.WEB_BASE_URL, linksPaused };
        const tomb = (out: ChangeSet, type: SyncRecordType, row: { id: string; deletedAt: Date | null }) =>
          out.tombstone(type, row.id, row.deletedAt!);
        const items: Item[] = [
          ...profiles.map((r) => ({ seq: r.seq, emit: (o: ChangeSet) => (r.deletedAt ? tomb(o, 'profile', r) : o.record('profile', profileToWire(r))) })),
          ...cards.map((r) => ({ seq: r.seq, emit: (o: ChangeSet) => (r.deletedAt ? tomb(o, 'card', r) : o.record('card', cardToWire(r, cardCtx))) })),
          ...events.map((r) => ({ seq: r.seq, emit: (o: ChangeSet) => (r.deletedAt ? tomb(o, 'event', r) : o.record('event', eventToWire(r))) })),
          ...connections.map((r) => ({
            seq: r.seq,
            emit: (o: ChangeSet) => (r.deletedAt ? tomb(o, 'connection', r) : o.record('connection', connectionToWire(r))),
          })),
          ...followUps.map((r) => ({
            seq: r.seq,
            emit: (o: ChangeSet) => (r.deletedAt ? tomb(o, 'followUp', r) : o.record('followUp', followUpToWire(r))),
          })),
        ];
        // A request appears once per side; a user who is both sides cannot exist (no self-requests).
        const requestRows = [...outgoing.map((r) => ({ r, seq: r.fromSeq })), ...incoming.map((r) => ({ r, seq: r.toSeq }))];
        const requestWire = await this.requests.toWire(
          requestRows.map((x) => x.r),
          userId,
          tx,
          now,
        );
        requestRows.forEach((x, i) => items.push({ seq: x.seq, emit: (o) => void o.record('connectRequest', requestWire[i]!) }));

        items.sort((a, b) => (a.seq < b.seq ? -1 : a.seq > b.seq ? 1 : 0));
        const page = items.slice(0, limit);
        const hasMore = items.length > limit;
        const out = new ChangeSet();
        for (const item of page) await item.emit(out);
        const cursorSeq = hasMore ? page[page.length - 1]!.seq : user.seq;

        const firstPage = fullSnapshot || after === 0n;
        return {
          changes: out.toWire(),
          cursor: encodeCursor(cursorSeq),
          hasMore,
          serverTime: iso(now),
          ...(firstPage || !hasMore ? { entitlement: await this.entitlements.wire(userId, tx) } : {}),
        };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead, timeout: 30_000 },
    );
  }
}

/** Adds every record and tombstone of `from` to `into` (later writes win). */
function merge(into: ChangeSet, from: ChangeSet) {
  const wire = from.toWire() as Record<string, unknown>;
  if (wire.profile) into.record('profile', wire.profile as Record<string, unknown>);
  const lists: [string, SyncRecordType][] = [
    ['cards', 'card'],
    ['events', 'event'],
    ['connections', 'connection'],
    ['followUps', 'followUp'],
    ['connectRequests', 'connectRequest'],
  ];
  for (const [key, type] of lists) for (const record of (wire[key] as Record<string, unknown>[]) ?? []) into.record(type, record);
  for (const t of (wire.tombstones as { type: SyncRecordType; id: string; deletedAt: string }[]) ?? []) {
    into.tombstone(t.type, t.id, t.deletedAt);
  }
}
