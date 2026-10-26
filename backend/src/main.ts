import 'reflect-metadata';
import 'dotenv/config';
import type { Server } from 'node:http';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';
import { configureApp } from './bootstrap';
import { loadEnv } from './config/env';
import { RealtimeService } from './realtime/realtime.service';

async function bootstrap() {
  const env = loadEnv();
  const app = await NestFactory.create<NestExpressApplication>(AppModule.forRoot(env), { bufferLogs: true, bodyParser: false });
  app.useLogger(app.get(Logger));
  configureApp(app);
  await app.listen(env.PORT, '0.0.0.0');
  await app.get(RealtimeService).attach(app.getHttpServer() as Server);
  app.get(Logger).log(`Tanishly API listening on :${env.PORT}`);
}

void bootstrap();
