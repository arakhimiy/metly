// Small pieces the connect services share: reachability rules, the error responses and the own-card check.
import { ApiError } from '../common/api-error';
import type { Card, Profile } from '../generated/prisma/client';
import type { Tx } from '../prisma/prisma.service';
import type { PrivacySettings } from '../records/wire';

export const present = (v: string | null | undefined) => v !== null && v !== undefined && v.trim().length > 0;

export const peerUnavailable = () => new ApiError(404, 'peer_unavailable', "This person isn't available to connect right now.");
export const requestExpired = () => new ApiError(409, 'request_expired', 'This request is no longer pending.');
export const requestNotFound = () => ApiError.notFound('Connect request not found.');

/** A profile someone can connect with: live and not paused ("Pause All Links"). */
export const reachable = (p: Profile | null | undefined): p is Profile => !!p && !p.deletedAt && !p.linksPaused;
export const showsInNearby = (p: Profile) => (p.privacySettings as Partial<PrivacySettings> | null)?.showInNearby !== false;

export async function ownCard(tx: Tx, userId: string, cardId: string): Promise<Card> {
  const card = await tx.card.findFirst({ where: { id: cardId, userId, deletedAt: null } });
  if (!card) throw ApiError.validation({ cardId: 'must be one of your cards' });
  return card;
}
