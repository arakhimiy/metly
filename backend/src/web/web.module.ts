import { Module } from '@nestjs/common';
import { RecordsModule } from '../records/records.module';
import { DeferredLinksController } from './deferred-links.controller';
import { DeferredLinksService } from './deferred-links.service';
import { LegalController } from './legal/legal.controller';
import { PublicApiController } from './public-api.controller';
import { PublicCardService } from './public-card.service';
import { ShareBackService } from './shareback.service';
import { WebController } from './web.controller';
import { WebStatsService } from './web-stats.service';

/** tanishly.app: public card page, vCard, public JSON, share-back, web analytics, AASA, deferred links, legal pages. */
@Module({
  imports: [RecordsModule],
  controllers: [WebController, PublicApiController, DeferredLinksController, LegalController],
  providers: [PublicCardService, WebStatsService, ShareBackService, DeferredLinksService],
  exports: [PublicCardService],
})
export class WebModule {}
