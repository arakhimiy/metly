// The connect facade the controllers call: Nearby sessions/peers (ConnectSessionsService), the
// request lifecycle (ConnectRequestsService) and accepting on both sides (ConnectAcceptService).
import { Injectable } from '@nestjs/common';
import type { ConnectRequest } from '../generated/prisma/client';
import type { Tx } from '../prisma/prisma.service';
import type { Effects } from '../records/write-context';
import { type AcceptResult, ConnectAcceptService } from './connect-accept.service';
import { ConnectRequestsService } from './connect-requests.service';
import { ConnectSessionsService } from './connect-sessions.service';

export { MAX_PEER_TOKENS, SESSION_LIFETIME_MS } from './connect-sessions.service';
export type { AcceptResult } from './connect-accept.service';

/** Connect sessions, Nearby peers and connect requests (docs/api/README.md § Connect requests). */
@Injectable()
export class ConnectService {
  constructor(
    private readonly sessions: ConnectSessionsService,
    private readonly requests: ConnectRequestsService,
    private readonly acceptor: ConnectAcceptService,
  ) {}

  // ───────────────────────────── Sessions & peers ─────────────────────────────

  /**
   * The token is what the phone advertises — never the user id. Hidden users (showInNearby = false)
   * still get one; it just never resolves.
   */
  startSession(userId: string, body: unknown) {
    return this.sessions.startSession(userId, body);
  }

  endSession(userId: string, sessionId: string) {
    return this.sessions.endSession(userId, sessionId);
  }

  resolvePeers(userId: string, tokensRaw: string | undefined) {
    return this.sessions.resolvePeers(userId, tokensRaw);
  }

  // ───────────────────────────── Requests ─────────────────────────────

  send(userId: string, body: unknown) {
    return this.requests.send(userId, body);
  }

  list(userId: string, query: unknown, cursor?: string, limitRaw?: string) {
    return this.requests.list(userId, query, cursor, limitRaw);
  }

  get(userId: string, requestId: string) {
    return this.requests.get(userId, requestId);
  }

  accept(userId: string, requestId: string, body: unknown) {
    return this.requests.accept(userId, requestId, body);
  }

  /** Quiet: only the recipient's side changes; the requester keeps seeing pending until expiresAt. */
  decline(userId: string, requestId: string) {
    return this.requests.decline(userId, requestId);
  }

  /** The requester withdraws; the recipient's overlay disappears (realtime) and its list drops it. */
  cancel(userId: string, requestId: string) {
    return this.requests.cancel(userId, requestId);
  }

  // ───────────────────────────── Accept (both sides) ─────────────────────────────

  /**
   * Accepts `request` inside the caller's transaction (both users already locked): a mutual
   * connection on each side (reused when one exists for the same Nameshake user), the request settled,
   * and every other pending request between the two settled as accepted too (README rule).
   */
  applyAccept(tx: Tx, request: ConnectRequest, toCardId: string | null, now: Date, effects: Effects): Promise<AcceptResult> {
    return this.acceptor.applyAccept(tx, request, toCardId, now, effects);
  }
}
