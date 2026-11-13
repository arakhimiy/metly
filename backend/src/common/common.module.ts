import { Global, Module } from '@nestjs/common';
import { DomainEvents } from './domain-events';
import { RateLimitStore, rateLimitStoreProvider } from './rate-limit';

@Global()
@Module({ providers: [DomainEvents, rateLimitStoreProvider], exports: [DomainEvents, RateLimitStore] })
export class CommonModule {}
