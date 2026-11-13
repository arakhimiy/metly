// The write transaction primitives shared by every record writer: the side effects a transaction
// collects (`Effects`), the per-user transaction context (`WriteContext`) and the LWW conflict rule.
import type { PrismaService, Tx } from '../prisma/prisma.service';
import type { EntitlementsService, PlanLimits } from '../subscriptions/entitlements.service';
import { ChangeSet } from './changes';

/** Side effects collected during a write transaction, published after it commits. */
export class Effects {
  readonly usersChanged = new Set<string>();
  readonly cardsContentChanged = new Set<string>();
}

/** One write transaction for one user: where canonical records and side effects are collected. */
export class WriteContext {
  readonly effects = new Effects();
  private linksPausedCache: boolean | undefined;
  private plan: { pro: boolean; limits: PlanLimits } | undefined;

  constructor(
    readonly tx: Tx,
    readonly userId: string,
    readonly out: ChangeSet = new ChangeSet(),
  ) {}

  async linksPaused(): Promise<boolean> {
    if (this.linksPausedCache === undefined) {
      const profile = await this.tx.profile.findUnique({ where: { userId: this.userId }, select: { linksPaused: true, deletedAt: true } });
      this.linksPausedCache = profile && !profile.deletedAt ? profile.linksPaused : false;
    }
    return this.linksPausedCache;
  }

  setLinksPaused(value: boolean) {
    this.linksPausedCache = value;
  }

  async planFor(entitlements: EntitlementsService) {
    this.plan ??= await entitlements.limits(this.userId, this.tx);
    return this.plan;
  }
}

export type Verdict = 'apply' | 'staleTombstone' | 'staleLive';

/** README § Conflict resolution, for an incoming upsert with updatedAt = U. */
export function lww(existing: { updatedAt: Date; deletedAt: Date | null } | null, updatedAt: Date): Verdict {
  if (!existing) return 'apply';
  if (existing.deletedAt) return existing.deletedAt >= updatedAt ? 'staleTombstone' : 'apply';
  return existing.updatedAt > updatedAt ? 'staleLive' : 'apply';
}

export const sameJson = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

/** Next change sequence number for `userId`, marking that user as changed in `effects`. */
export async function bumpSeq(prisma: PrismaService, tx: Tx, effects: Effects, userId: string): Promise<bigint> {
  effects.usersChanged.add(userId);
  return prisma.nextSeq(tx, userId);
}
