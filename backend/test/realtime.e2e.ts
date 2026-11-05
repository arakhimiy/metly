import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { WebSocket } from 'ws';
import { RealtimeService } from '../src/realtime/realtime.service';
import { createApp, signIn } from './helpers';

describe('realtime socket', () => {
  let app: NestExpressApplication;
  let url: string;

  beforeAll(async () => {
    app = await createApp();
    await app.listen(0, '127.0.0.1');
    await app.get(RealtimeService).attach(app.getHttpServer() as Server);
    const { port } = (app.getHttpServer() as Server).address() as AddressInfo;
    url = `ws://127.0.0.1:${port}/v1/realtime`;
  });
  afterAll(() => app.close());

  const open = (token: string) => new WebSocket(url, { headers: { authorization: `Bearer ${token}` } });

  it('closes a socket without a valid token with 4401', async () => {
    const ws = open('not-a-token');
    const code = await new Promise<number>((resolve) => ws.on('close', (c) => resolve(c)));
    expect(code).toBe(4401);
  });

  it('delivers a published event to the signed-in user', async () => {
    const me = await signIn(app);
    const ws = open(me.accessToken);
    const messages: { type: string; data: unknown }[] = [];
    ws.on('message', (raw) => messages.push(JSON.parse(raw.toString())));
    await new Promise((resolve) => ws.on('open', resolve));
    // The socket is registered once its token is checked.
    await expect.poll(async () => {
      await app.get(RealtimeService).publish(me.userId, 'sync.available', { n: 1 });
      return messages.some((m) => m.type === 'sync.available');
    }).toBe(true);
    ws.close();
  });
});
