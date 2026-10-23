import type { ApnsRequest, ApnsResult, PushTarget, PushTransport } from './apns.transport';

export interface CapturedPush extends ApnsRequest, PushTarget {}

/**
 * Test hook. With `NODE_ENV=test` PushService never opens a network connection: every push it
 * would send to APNs is appended to `pushTestSink.sent` (whether or not APNs is configured). Tests
 * can make a token fail with `pushTestSink.respond(token, { status: 410, reason: 'Unregistered' })`.
 *
 * ```ts
 * import { pushTestSink } from '../src/push/push-test-sink';
 * pushTestSink.clear();
 * await jobs.runOnce();
 * expect(pushTestSink.sent.filter((p) => p.userId === s.userId)).toHaveLength(1);
 * ```
 */
export const pushTestSink = {
  sent: [] as CapturedPush[],
  responses: new Map<string, ApnsResult>(),
  respond(token: string, result: ApnsResult) {
    this.responses.set(token.toLowerCase(), result);
  },
  forUser(userId: string): CapturedPush[] {
    return this.sent.filter((p) => p.userId === userId);
  },
  clear() {
    this.sent.length = 0;
    this.responses.clear();
  },
};

export class TestSinkTransport implements PushTransport {
  async send(request: ApnsRequest, target: PushTarget): Promise<ApnsResult> {
    pushTestSink.sent.push({ ...request, ...target });
    return pushTestSink.responses.get(request.token.toLowerCase()) ?? { status: 200 };
  }

  async close(): Promise<void> {}
}
