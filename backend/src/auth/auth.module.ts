import { Global, Module } from '@nestjs/common';
import { AppleService } from './apple.service';
import { AuthController } from './auth.controller';
import { GoogleService } from './google.service';
import { TelegramLoginService } from './telegram.service';
import { TokensService } from './tokens.service';

@Global()
@Module({
  controllers: [AuthController],
  providers: [TokensService, AppleService, GoogleService, TelegramLoginService],
  exports: [TokensService, AppleService],
})
export class AuthModule {}
