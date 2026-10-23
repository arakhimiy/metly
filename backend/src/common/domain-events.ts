import { Injectable, Logger } from '@nestjs/common';

/** In-process domain events, emitted after the writing transaction committed. */
export interface DomainEventMap {
  /** A user's synced data changed server-side (their other devices should pull). */
  'user.changed': { userId: string; originDeviceId?: string | null };
  /** What a card's public surfaces show changed (web page, vCard, Wallet pass). */
  'cards.content.changed': { cardIds: string[] };
  /** A user's account is being deleted (hooks clean up external state: Apple, storage, devices). */
  'account.deleting': { userId: string };
}

type Handler<K extends keyof DomainEventMap> = (payload: DomainEventMap[K]) => Promise<void> | void;

@Injectable()
export class DomainEvents {
  private readonly logger = new Logger(DomainEvents.name);
  private readonly handlers = new Map<keyof DomainEventMap, Handler<never>[]>();

  on<K extends keyof DomainEventMap>(event: K, handler: Handler<K>): void {
    const list = this.handlers.get(event) ?? [];
    list.push(handler as Handler<never>);
    this.handlers.set(event, list);
  }

  /** Fire-and-forget; a failing subscriber is logged and never breaks the request. */
  emit<K extends keyof DomainEventMap>(event: K, payload: DomainEventMap[K]): void {
    for (const handler of this.handlers.get(event) ?? []) {
      Promise.resolve()
        .then(() => (handler as Handler<K>)(payload))
        .catch((error: unknown) => this.logger.error({ err: error, event }, 'domain event handler failed'));
    }
  }

  /** Awaits every subscriber (account deletion must finish its clean-up before answering). */
  async emitAndWait<K extends keyof DomainEventMap>(event: K, payload: DomainEventMap[K]): Promise<void> {
    for (const handler of this.handlers.get(event) ?? []) {
      try {
        await (handler as Handler<K>)(payload);
      } catch (error) {
        this.logger.error({ err: error, event }, 'domain event handler failed');
      }
    }
  }
}
