import { Controller, Delete, Get, HttpCode, Post } from '@nestjs/common';
import { userWire } from '../auth/auth.controller';
import { DomainEvents } from '../common/domain-events';
import { RateLimit } from '../common/rate-limit';
import { type AuthedUser, CurrentUser } from '../common/request';
import { iso } from '../common/time';
import { PrismaService } from '../prisma/prisma.service';
import { profileToWire } from '../records/mappers';
import { EntitlementsService } from '../subscriptions/entitlements.service';

@Controller('v1/me')
export class AccountController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
    private readonly events: DomainEvents,
  ) {}

  @Get()
  async me(@CurrentUser() user: AuthedUser) {
    const [wireUser, profile, entitlement] = await Promise.all([
      userWire(this.prisma, user.id),
      this.prisma.profile.findUnique({ where: { userId: user.id } }),
      this.entitlements.wire(user.id),
    ]);
    return { user: wireUser, profile: profile && !profile.deletedAt ? profileToWire(profile) : null, entitlement };
  }

  @Get('entitlements')
  entitlement(@CurrentUser() user: AuthedUser) {
    return this.entitlements.wire(user.id);
  }

  /**
   * Irreversible. External clean-up first (Apple token revocation, stored images, Wallet and push
   * registrations, open sockets), then every row of the account. Slugs stay registered so the user's
   * links answer `deleted` and are never reissued. Other people keep the snapshot they have of this
   * person; their remoteUserId simply stops resolving.
   */
  @Delete()
  @HttpCode(204)
  async deleteAccount(@CurrentUser() user: AuthedUser) {
    await this.events.emitAndWait('account.deleting', { userId: user.id });
    await this.prisma.write(async (tx) => {
      const cards = await tx.card.findMany({ where: { userId: user.id }, select: { id: true } });
      const cardIds = cards.map((c) => c.id);
      await tx.passRegistration.deleteMany({ where: { serialNumber: { in: cardIds } } });
      await tx.connectRequest.deleteMany({ where: { OR: [{ fromUserId: user.id }, { toUserId: user.id }] } });
      await tx.shareBack.deleteMany({ where: { ownerId: user.id } });
      await tx.cardVisit.deleteMany({ where: { cardId: { in: cardIds } } });
      await tx.deferredClick.deleteMany({ where: { ownerId: user.id } });
      await tx.connectionAlias.deleteMany({ where: { userId: user.id } });
      await tx.upload.deleteMany({ where: { userId: user.id } });
      await tx.dataExportRequest.deleteMany({ where: { userId: user.id } });
      await tx.idempotencyRecord.deleteMany({ where: { scope: `u:${user.id}` } });
      await tx.block.deleteMany({ where: { blockedUserId: user.id } });
      // Cascades: identities, sessions, profile, cards, events, connections, follow-ups, devices,
      // entitlement, blocks made, connect sessions.
      await tx.user.delete({ where: { id: user.id } });
    });
  }

  /**
   * "Download My Data": queued; the export job builds the ZIP (JSON + CSV + images) and emails a
   * link within 24 h once mail delivery is configured.
   */
  @Post('export')
  @HttpCode(202)
  @RateLimit('export')
  async requestExport(@CurrentUser() user: AuthedUser) {
    const account = await this.prisma.user.findUniqueOrThrow({ where: { id: user.id }, select: { email: true } });
    const request = await this.prisma.dataExportRequest.create({ data: { userId: user.id, email: account.email } });
    return { status: 'queued', requestedAt: iso(request.requestedAt), ...(account.email ? { email: account.email } : {}) };
  }
}
