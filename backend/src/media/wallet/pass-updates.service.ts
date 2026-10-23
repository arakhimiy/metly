import { Inject, Injectable, Logger, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import { DomainEvents } from '../../common/domain-events';
import { ENV, type Env } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { UUID_PARAM } from '../../records/rest';
import { ApnsPassPushSender, type PassPushSender, TestPassPushSink } from './pass-push';

export function createPassPushSender(env: Env): PassPushSender | null {
  if (env.NODE_ENV === 'test') return new TestPassPushSink(env.PASS_TYPE_IDENTIFIER);
  if (!env.PASS_CERT_PEM || !env.PASS_KEY_PEM) return null;
  return new ApnsPassPushSender({
    cert: env.PASS_CERT_PEM,
    key: env.PASS_KEY_PEM,
    ...(env.PASS_KEY_PASSPHRASE ? { passphrase: env.PASS_KEY_PASSPHRASE } : {}),
    topic: env.PASS_TYPE_IDENTIFIER,
  });
}

/** On `cards.content.changed`, pushes every Wallet device holding one of those passes. */
@Injectable()
export class PassUpdatesService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PassUpdatesService.name);
  private readonly sender: PassPushSender | null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly events: DomainEvents,
    @Inject(ENV) env: Env,
  ) {
    this.sender = createPassPushSender(env);
  }

  onModuleInit() {
    this.events.on('cards.content.changed', async ({ cardIds }) => {
      await this.cardsChanged(cardIds);
    });
  }

  onModuleDestroy() {
    this.sender?.close();
  }

  /** Returns how many pushes were sent (skips silently without certificates). */
  async cardsChanged(cardIds: string[]): Promise<number> {
    const ids = [...new Set(cardIds.filter((id) => UUID_PARAM.test(id)).map((id) => id.toLowerCase()))];
    if (ids.length === 0) return 0;
    // A tombstone does not touch contentUpdatedAt; move it so Wallet sees the (voided) pass as updated.
    await this.prisma.card.updateMany({ where: { id: { in: ids }, deletedAt: { not: null } }, data: { contentUpdatedAt: new Date() } });
    if (!this.sender) return 0;
    const registrations = await this.prisma.passRegistration.findMany({ where: { serialNumber: { in: ids } }, select: { pushToken: true } });
    const tokens = [...new Set(registrations.map((r) => r.pushToken))];
    let sent = 0;
    for (const token of tokens) {
      const result = await this.sender.send(token);
      if (result === 'sent') sent += 1;
      else if (result === 'unregistered') await this.prisma.passRegistration.deleteMany({ where: { pushToken: token } });
      else this.logger.warn({ cardIds: ids }, 'wallet pass push failed');
    }
    return sent;
  }
}
