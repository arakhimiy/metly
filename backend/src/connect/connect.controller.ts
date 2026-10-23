import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { RateLimit } from '../common/rate-limit';
import { type AuthedUser, CurrentUser } from '../common/request';
import { BlocksService } from './blocks.service';
import { ConnectService } from './connect.service';
import { PublicProfilesService } from './public-profiles.service';

@Controller('v1/connect')
export class ConnectController {
  constructor(private readonly connect: ConnectService) {}

  @Post('sessions')
  startSession(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    return this.connect.startSession(user.id, body);
  }

  @Delete('sessions/:sessionId')
  @HttpCode(204)
  async endSession(@CurrentUser() user: AuthedUser, @Param('sessionId') sessionId: string) {
    await this.connect.endSession(user.id, sessionId);
  }

  @Get('peers')
  peers(@CurrentUser() user: AuthedUser, @Query('tokens') tokens?: string) {
    return this.connect.resolvePeers(user.id, tokens);
  }

  @Post('requests')
  @RateLimit('connect')
  send(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    return this.connect.send(user.id, body);
  }

  @Get('requests')
  list(
    @CurrentUser() user: AuthedUser,
    @Query('status') status?: string,
    @Query('direction') direction?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    return this.connect.list(user.id, { status: status || undefined, direction: direction || undefined }, cursor, limit);
  }

  @Get('requests/:requestId')
  get(@CurrentUser() user: AuthedUser, @Param('requestId') requestId: string) {
    return this.connect.get(user.id, requestId);
  }

  @Post('requests/:requestId/accept')
  @HttpCode(200)
  accept(@CurrentUser() user: AuthedUser, @Param('requestId') requestId: string, @Body() body: unknown) {
    return this.connect.accept(user.id, requestId, body);
  }

  @Post('requests/:requestId/decline')
  @HttpCode(200)
  decline(@CurrentUser() user: AuthedUser, @Param('requestId') requestId: string) {
    return this.connect.decline(user.id, requestId);
  }

  @Post('requests/:requestId/cancel')
  @HttpCode(200)
  cancel(@CurrentUser() user: AuthedUser, @Param('requestId') requestId: string) {
    return this.connect.cancel(user.id, requestId);
  }
}

@Controller('v1/me/blocks')
export class BlocksController {
  constructor(private readonly blocks: BlocksService) {}

  @Get()
  list(@CurrentUser() user: AuthedUser) {
    return this.blocks.list(user.id);
  }

  @Post()
  @HttpCode(200)
  block(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    return this.blocks.block(user.id, body);
  }

  @Delete(':userId')
  @HttpCode(204)
  async unblock(@CurrentUser() user: AuthedUser, @Param('userId') userId: string) {
    await this.blocks.unblock(user.id, userId);
  }
}

@Controller('v1/connections')
export class ConnectionBlockController {
  constructor(private readonly blocks: BlocksService) {}

  @Post(':connectionId/block')
  @HttpCode(200)
  async block(@CurrentUser() user: AuthedUser, @Param('connectionId') connectionId: string) {
    return (await this.blocks.blockConnection(user.id, connectionId)).connection;
  }
}

@Controller('v1/public-profiles')
export class PublicProfilesController {
  constructor(private readonly profiles: PublicProfilesService) {}

  @Get(':slug')
  get(@CurrentUser() user: AuthedUser, @Param('slug') slug: string) {
    return this.profiles.get(user.id, slug);
  }
}
