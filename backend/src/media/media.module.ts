import { Module } from '@nestjs/common';
import { RecordsModule } from '../records/records.module';
import { ExportService } from './export/export.service';
import { MediaCleanupService } from './media-cleanup.service';
import { StorageService } from './storage/storage.service';
import { UploadsController } from './uploads/uploads.controller';
import { UploadsService } from './uploads/uploads.service';
import { PassKitController } from './wallet/passkit.controller';
import { PassUpdatesService } from './wallet/pass-updates.service';
import { WalletController } from './wallet/wallet.controller';
import { WalletService } from './wallet/wallet.service';

/** Profile photo/logo uploads, Apple Wallet passes + PassKit web service, data export. */
@Module({
  imports: [RecordsModule],
  controllers: [UploadsController, WalletController, PassKitController],
  providers: [StorageService, UploadsService, WalletService, PassUpdatesService, ExportService, MediaCleanupService],
  exports: [StorageService],
})
export class MediaModule {}
