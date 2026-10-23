import { Global, Module } from '@nestjs/common';
import { DomainEvents } from './domain-events';
import { RateLimitStore } from './rate-limit';

@Global()
@Module({ providers: [DomainEvents, RateLimitStore], exports: [DomainEvents, RateLimitStore] })
export class CommonModule {}
