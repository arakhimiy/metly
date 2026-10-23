import { Module } from '@nestjs/common';
import { ConnectViewModule } from '../connect/connect-view.module';
import { RecordsModule } from '../records/records.module';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

@Module({
  imports: [RecordsModule, ConnectViewModule],
  controllers: [SyncController],
  providers: [SyncService],
})
export class SyncModule {}
