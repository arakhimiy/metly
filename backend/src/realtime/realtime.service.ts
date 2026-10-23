import { randomUUID } from 'node:crypto';
import type { IncomingMessage, Server } from 'node:http';
import type { Duplex } from 'node:stream';
import { Inject, Injectable, Logger, type OnApplicationShutdown, type OnModuleInit } from '@nestjs/common';
import { Client } from 'pg';
import { type WebSocket, WebSocketServer } from 'ws';
import { TokensService } from '../auth/tokens.service';
import { DomainEvents } from '../common/domain-events';
import { iso } from '../common/time';
import { ENV, type Env } from '../config/env';

export type RealtimeType = 'connect.request.received' | 'connect.request.updated' | 'shareback.received' | 'sync.available';

const CHANNEL = 'metly_realtime';
const PING_EVERY_MS = 25_000;
const PONG_TIMEOUT_MS = 10_000;
const SYNC_DEBOUNCE_MS = 2_000;
/** Postgres NOTIFY payloads are limited to 8000 bytes. */
const MAX_NOTIFY_BYTES = 7_900;

interface Socket {
  ws: WebSocket;
  userId: string;
  awaitingPongSince: number | null;
}

/**
 * `GET /v1/realtime` (WebSocket). Delivery is at-most-once and best-effort; clients pull after every
 * (re)connect. Messages fan out across instances through Postgres LISTEN/NOTIFY, so several API
 * instances need no extra broker.
 */
@Injectable()
export class RealtimeService implements OnModuleInit, OnApplicationShutdown {
  private readonly logger = new Logger(RealtimeService.name);
  private readonly instanceId = randomUUID();
  private readonly sockets = new Map<string, Set<Socket>>();
  private readonly syncTimers = new Map<string, NodeJS.Timeout>();
  private wss: WebSocketServer | undefined;
  private listener: Client | undefined;
  private pingTimer: NodeJS.Timeout | undefined;
  private shuttingDown = false;

  constructor(
    private readonly tokens: TokensService,
    private readonly events: DomainEvents,
    @Inject(ENV) private readonly env: Env,
  ) {}

  onModuleInit() {
    this.events.on('user.changed', ({ userId }) => this.scheduleSyncAvailable(userId));
    this.events.on('account.deleting', ({ userId }) => this.disconnectUser(userId));
  }

  /** Called from main.ts with the HTTP server once the app listens. */
  async attach(server: Server): Promise<void> {
    this.wss = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024 });
    server.on('upgrade', (request: IncomingMessage, socket: Duplex, head: Buffer) => {
      const path = (request.url ?? '').split('?')[0];
      if (path !== '/v1/realtime') {
        socket.destroy();
        return;
      }
      this.wss!.handleUpgrade(request, socket, head, (ws) => void this.accept(ws, request));
    });
    this.pingTimer = setInterval(() => this.heartbeat(), PING_EVERY_MS);
    this.pingTimer.unref();
    await this.listen();
  }

  private async accept(ws: WebSocket, request: IncomingMessage) {
    const header = request.headers.authorization ?? '';
    const token = /^Bearer\s+(.+)$/i.exec(header)?.[1];
    let userId: string;
    try {
      if (!token) throw new Error('missing token');
      const claims = await this.tokens.verifyAccess(token);
      if (!(await this.tokens.isFamilyActive(claims.familyId))) throw new Error('revoked');
      userId = claims.userId;
    } catch {
      ws.close(4401, 'unauthorized');
      return;
    }
    const entry: Socket = { ws, userId, awaitingPongSince: null };
    const set = this.sockets.get(userId) ?? new Set<Socket>();
    set.add(entry);
    this.sockets.set(userId, set);

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString()) as { type?: string };
        if (message.type === 'pong') entry.awaitingPongSince = null;
        else if (message.type === 'ping') ws.send(JSON.stringify({ type: 'pong' }));
      } catch {
        // Unknown or malformed client messages are ignored.
      }
    });
    ws.on('pong', () => (entry.awaitingPongSince = null));
    ws.on('close', () => {
      set.delete(entry);
      if (set.size === 0) this.sockets.delete(userId);
    });
    ws.on('error', () => ws.terminate());
  }

  private heartbeat() {
    const now = Date.now();
    for (const set of this.sockets.values()) {
      for (const entry of set) {
        if (entry.awaitingPongSince !== null && now - entry.awaitingPongSince > PONG_TIMEOUT_MS) {
          entry.ws.terminate();
          continue;
        }
        if (entry.awaitingPongSince === null) {
          entry.awaitingPongSince = now;
          entry.ws.send(JSON.stringify({ type: 'ping' }));
          entry.ws.ping();
        }
      }
    }
  }

  /** Sends a message to every socket of the user, on every instance. */
  async publish(userId: string, type: RealtimeType, data: unknown): Promise<void> {
    const message = { type, id: `evt_${randomUUID()}`, sentAt: iso(new Date()), data };
    this.deliver(userId, message);
    if (!this.listener) return;
    let payload = JSON.stringify({ origin: this.instanceId, userId, message });
    if (Buffer.byteLength(payload) > MAX_NOTIFY_BYTES) {
      // Too big to fan out: other instances fall back to a pull hint; the data arrives through sync.
      payload = JSON.stringify({ origin: this.instanceId, userId, message: { type: 'sync.available', id: message.id, sentAt: message.sentAt, data: {} } });
    }
    try {
      await this.listener.query('SELECT pg_notify($1, $2)', [CHANNEL, payload]);
    } catch (error) {
      this.logger.warn({ err: error }, 'realtime fan-out failed');
    }
  }

  /** `sync.available`, debounced per user (≥ 2 s, as the contract asks). */
  scheduleSyncAvailable(userId: string) {
    if (this.syncTimers.has(userId)) return;
    const timer = setTimeout(() => {
      this.syncTimers.delete(userId);
      void this.publish(userId, 'sync.available', {});
    }, SYNC_DEBOUNCE_MS);
    timer.unref();
    this.syncTimers.set(userId, timer);
  }

  isOnline(userId: string): boolean {
    return (this.sockets.get(userId)?.size ?? 0) > 0;
  }

  disconnectUser(userId: string) {
    for (const entry of this.sockets.get(userId) ?? []) entry.ws.close(4401, 'account deleted');
  }

  private deliver(userId: string, message: unknown) {
    const text = JSON.stringify(message);
    for (const entry of this.sockets.get(userId) ?? []) {
      if (entry.ws.readyState === entry.ws.OPEN) entry.ws.send(text);
    }
  }

  private async listen() {
    const client = new Client({ connectionString: this.env.DATABASE_URL });
    client.on('error', (error) => {
      this.logger.warn({ err: error }, 'realtime listener lost its connection; reconnecting');
      this.listener = undefined;
      if (!this.shuttingDown) setTimeout(() => void this.listen().catch(() => undefined), 2_000).unref();
    });
    client.on('notification', (n) => {
      if (n.channel !== CHANNEL || !n.payload) return;
      try {
        const { origin, userId, message } = JSON.parse(n.payload) as { origin: string; userId: string; message: unknown };
        if (origin !== this.instanceId) this.deliver(userId, message);
      } catch {
        // ignore malformed payloads
      }
    });
    await client.connect();
    await client.query(`LISTEN ${CHANNEL}`);
    this.listener = client;
  }

  async onApplicationShutdown() {
    this.shuttingDown = true;
    if (this.pingTimer) clearInterval(this.pingTimer);
    for (const timer of this.syncTimers.values()) clearTimeout(timer);
    for (const set of this.sockets.values()) for (const entry of set) entry.ws.close(1001, 'server shutting down');
    this.wss?.close();
    await this.listener?.end().catch(() => undefined);
  }
}
