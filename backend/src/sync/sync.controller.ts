import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import { RateLimit } from '../common/rate-limit';
import { type AuthedUser, CurrentUser } from '../common/request';
import { SyncService } from './sync.service';

@Controller('v1/sync')
@RateLimit('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Post('push')
  @HttpCode(200)
  push(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    return this.sync.push(user.id, body);
  }

  @Get()
  pull(@CurrentUser() user: AuthedUser, @Query('since') since?: string, @Query('limit') limit?: string) {
    return this.sync.pull(user.id, since, limit);
  }
}
