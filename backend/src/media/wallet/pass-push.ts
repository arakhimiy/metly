import http2 from 'node:http2';

export type PassPushResult = 'sent' | 'unregistered' | 'failed';

/** Tells Wallet on one device that its passes changed (it then asks the PassKit web service). */
export interface PassPushSender {
  send(pushToken: string): Promise<PassPushResult>;
  close(): void;
}

/**
 * Test sink: with `NODE_ENV=test` every pass push lands here instead of APNs (certificates or not).
 * Tests read `TestPassPushSink.sent` and call `clear()` between cases.
 */
export class TestPassPushSink implements PassPushSender {
  static readonly sent: { pushToken: string; topic: string; payload: string }[] = [];
  /** Tokens that answer like APNs 410 Unregistered. */
  static readonly unregistered = new Set<string>();

  constructor(private readonly topic: string) {}

  static clear() {
    TestPassPushSink.sent.length = 0;
    TestPassPushSink.unregistered.clear();
  }

  async send(pushToken: string): Promise<PassPushResult> {
    TestPassPushSink.sent.push({ pushToken, topic: this.topic, payload: '{}' });
    return TestPassPushSink.unregistered.has(pushToken) ? 'unregistered' : 'sent';
  }

  close() {}
}

export const PUSH_TOKEN = /^[0-9a-fA-F]{32,200}$/;

/**
 * Wallet pass pushes: HTTP/2 to production APNs (Wallet uses production even for development passes),
 * authenticated with the Pass Type ID certificate, topic = pass type identifier, empty `{}` payload.
 */
export class ApnsPassPushSender implements PassPushSender {
  private session: http2.ClientHttp2Session | undefined;

  constructor(
    private readonly options: { cert: string; key: string; passphrase?: string; topic: string; origin?: string },
  ) {}

  private connect(): http2.ClientHttp2Session {
    if (this.session && !this.session.closed && !this.session.destroyed) return this.session;
    const session = http2.connect(this.options.origin ?? 'https://api.push.apple.com', {
      cert: this.options.cert,
      key: this.options.key,
      ...(this.options.passphrase ? { passphrase: this.options.passphrase } : {}),
    });
    session.on('error', () => {
      if (this.session === session) this.session = undefined;
    });
    session.on('goaway', () => {
      if (this.session === session) this.session = undefined;
      session.close();
    });
    session.unref();
    this.session = session;
    return session;
  }

  send(pushToken: string): Promise<PassPushResult> {
    if (!PUSH_TOKEN.test(pushToken)) return Promise.resolve('unregistered');
    return new Promise((resolve) => {
      let settled = false;
      const done = (result: PassPushResult) => {
        if (!settled) {
          settled = true;
          resolve(result);
        }
      };
      try {
        const request = this.connect().request({
          ':method': 'POST',
          ':path': `/3/device/${pushToken}`,
          'apns-topic': this.options.topic,
          'content-type': 'application/json',
        });
        request.setTimeout(10_000, () => {
          request.close(http2.constants.NGHTTP2_CANCEL);
          done('failed');
        });
        request.on('response', (headers) => {
          const status = Number(headers[':status']);
          // 410 Unregistered; 400 BadDeviceToken / DeviceTokenNotForTopic: forget the registration.
          done(status === 200 ? 'sent' : status === 410 || status === 400 ? 'unregistered' : 'failed');
        });
        request.on('error', () => done('failed'));
        request.on('close', () => done('failed'));
        request.resume();
        request.end('{}');
      } catch {
        done('failed');
      }
    });
  }

  close() {
    this.session?.close();
    this.session = undefined;
  }
}
