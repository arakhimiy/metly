import { Module } from '@nestjs/common';
import { SubscriptionsCoreModule } from '../subscriptions/subscriptions-core.module';
import { CardsController } from './cards.controller';
import { ConnectionsController, EventsController, FollowUpsController } from './people.controller';
import { ProfileController } from './profile.controller';
import { RecordsService } from './records.service';
import { CardWriter } from './writers/card.writer';
import { ConnectionWriter } from './writers/connection.writer';
import { EventWriter } from './writers/event.writer';
import { FollowUpWriter } from './writers/follow-up.writer';
import { ProfileWriter } from './writers/profile.writer';
import { RecordCore } from './writers/record-core';
import { TombstoneWriter } from './writers/tombstones';

@Module({
  imports: [SubscriptionsCoreModule],
  controllers: [ProfileController, CardsController, ConnectionsController, FollowUpsController, EventsController],
  providers: [RecordsService, RecordCore, ProfileWriter, CardWriter, EventWriter, ConnectionWriter, FollowUpWriter, TombstoneWriter],
  exports: [RecordsService, SubscriptionsCoreModule],
})
export class RecordsModule {}
