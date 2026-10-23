import { Module } from '@nestjs/common';
import { SubscriptionsCoreModule } from '../subscriptions/subscriptions-core.module';
import { CardsController } from './cards.controller';
import { ConnectionsController, EventsController, FollowUpsController } from './people.controller';
import { ProfileController } from './profile.controller';
import { RecordsService } from './records.service';

@Module({
  imports: [SubscriptionsCoreModule],
  controllers: [ProfileController, CardsController, ConnectionsController, FollowUpsController, EventsController],
  providers: [RecordsService],
  exports: [RecordsService, SubscriptionsCoreModule],
})
export class RecordsModule {}
