import type { Tx } from '../prisma/prisma.service';

// "Blocked" is either an explicit row in `blocks` (POST /v1/me/blocks) or a connection the owner
// marked `isBlocked` on a device (synced, possibly without a block row) — the mock treats both alike.

/** `ownerId` blocked `otherId` (one direction). */
export async function hasBlocked(tx: Tx, ownerId: string, otherId: string): Promise<boolean> {
  const [block, connection] = await Promise.all([
    tx.block.findFirst({ where: { userId: ownerId, blockedUserId: otherId }, select: { id: true } }),
    tx.connection.findFirst({ where: { userId: ownerId, remoteUserId: otherId, isBlocked: true, deletedAt: null }, select: { id: true } }),
  ]);
  return block !== null || connection !== null;
}

/** Either user blocked the other. */
export async function blockedBetween(tx: Tx, a: string, b: string): Promise<boolean> {
  return (await blockedAmong(tx, a, [b])).size > 0;
}

/** The users in `others` that `userId` blocked or that blocked `userId`. */
export async function blockedAmong(tx: Tx, userId: string, others: string[]): Promise<Set<string>> {
  if (others.length === 0) return new Set();
  const [blocks, connections] = await Promise.all([
    tx.block.findMany({
      where: {
        OR: [
          { userId, blockedUserId: { in: others } },
          { userId: { in: others }, blockedUserId: userId },
        ],
      },
      select: { userId: true, blockedUserId: true },
    }),
    tx.connection.findMany({
      where: {
        isBlocked: true,
        deletedAt: null,
        OR: [
          { userId, remoteUserId: { in: others } },
          { userId: { in: others }, remoteUserId: userId },
        ],
      },
      select: { userId: true, remoteUserId: true },
    }),
  ]);
  const blocked = new Set<string>();
  for (const b of blocks) blocked.add(b.userId === userId ? b.blockedUserId! : b.userId);
  for (const c of connections) blocked.add(c.userId === userId ? c.remoteUserId! : c.userId);
  return blocked;
}
