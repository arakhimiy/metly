import { Module } from '@nestjs/common';
import { RecordsModule } from '../records/records.module';
import { BlocksService } from './blocks.service';
import { BlocksController, ConnectController, ConnectionBlockController, PublicProfilesController } from './connect.controller';
import { ConnectExpiryService } from './connect-expiry.service';
import { ConnectViewModule } from './connect-view.module';
import { ConnectService } from './connect.service';
import { PublicProfilesService } from './public-profiles.service';

/** Connect sessions, peers and requests; blocks; public profiles for the app (SCANNED_CARD). */
@Module({
  imports: [RecordsModule, ConnectViewModule],
  controllers: [ConnectController, BlocksController, ConnectionBlockController, PublicProfilesController],
  providers: [ConnectService, ConnectExpiryService, BlocksService, PublicProfilesService],
  exports: [ConnectService, ConnectExpiryService, BlocksService],
})
export class ConnectModule {}
