import { Module } from '@nestjs/common';
import { ConnectRequestView } from './connect-request.view';

@Module({ providers: [ConnectRequestView], exports: [ConnectRequestView] })
export class ConnectViewModule {}
