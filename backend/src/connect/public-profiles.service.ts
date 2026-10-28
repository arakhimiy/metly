import { Inject, Injectable } from '@nestjs/common';
import { ApiError } from '../common/api-error';
import { ENV, type Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { cardContactsView } from '../records/contacts';
import { cardUrl, designToWire } from '../records/mappers';
import { firstName } from '../records/snapshot';
import { hasBlocked } from './blocks';

const SLUG = /^[a-z0-9-]{1,100}$/;

/**
 * GET /v1/public-profiles/{slug} — a scanned Tanishly QR as the signed-in viewer sees it (SCANNED_CARD).
 * Connections-level fields only for an accepted, mutual connect: the owner holds a live, unblocked
 * connection to the viewer with `isMutual` (README § Privacy rule). A one-sided "Add to People" never
 * unlocks them.
 */
@Injectable()
export class PublicProfilesService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async get(viewerId: string, rawSlug: string) {
    const slug = rawSlug.trim().toLowerCase();
    if (!SLUG.test(slug)) throw ApiError.notFound('Card not found.');
    const card = await this.prisma.card.findUnique({ where: { slug } });
    if (!card) {
      // Issued once, card since purged: retired forever.
      if (await this.prisma.slug.findUnique({ where: { slug } })) return { slug, status: 'deleted' };
      throw ApiError.notFound('Card not found.');
    }
    const ownerId = card.userId;
    const isSelf = ownerId === viewerId;
    // The owner blocked the viewer: indistinguishable from an unknown slug.
    if (!isSelf && (await hasBlocked(this.prisma, ownerId, viewerId))) throw ApiError.notFound('Card not found.');

    const profile = await this.prisma.profile.findUnique({ where: { userId: ownerId } });
    if (card.deletedAt || !profile || profile.deletedAt) return { slug, status: 'deleted' };
    if (profile.linksPaused) return { slug, status: 'paused' };

    const [ownerSide, viewerSide] = isSelf
      ? [null, null]
      : await Promise.all([
          this.prisma.connection.findFirst({
            where: { userId: ownerId, remoteUserId: viewerId, deletedAt: null, isMutual: true, isBlocked: false },
            select: { id: true },
          }),
          this.prisma.connection.findFirst({
            where: { userId: viewerId, remoteUserId: ownerId, deletedAt: null },
            orderBy: { createdAt: 'asc' },
            select: { id: true },
          }),
        ]);
    const connected = ownerSide !== null;
    const design = designToWire(card.design);
    const audience = isSelf || connected ? 'connections' : 'public';
    const { contacts, fields, phoneLabel, additionalPhones } = cardContactsView(profile, design, audience);
    return {
      slug,
      status: 'available',
      url: cardUrl(this.env.WEB_BASE_URL, slug),
      cardName: card.name,
      owner: {
        userId: ownerId,
        fullName: profile.fullName,
        firstName: firstName(profile.fullName),
        jobTitle: profile.jobTitle,
        company: profile.company,
        ...(profile.photoUrl ? { photoUrl: profile.photoUrl } : {}),
      },
      design,
      fields,
      phoneLabel,
      additionalPhones,
      contacts,
      // isConnected: the server-side accepted connect (their Connections fields are visible).
      // connectionId: the viewer's own live connection to the owner, so the app finds it in People.
      viewer: { isSelf, isConnected: connected, ...(viewerSide ? { connectionId: viewerSide.id } : {}) },
    };
  }
}
