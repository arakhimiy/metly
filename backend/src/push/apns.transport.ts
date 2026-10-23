import { type ClientHttp2Session, connect, constants } from 'node:http2';
import { importPKCS8, SignJWT } from 'jose';
import type { ApnsHeaders } from './push-payload';

export type ApnsEnvironment = 'sandbox' | 'production';

export interface ApnsRequest {
  token: string;
  environment: ApnsEnvironment;
  headers: ApnsHeaders;
  payload: Record<string, unknown>;
}

/** APNs answer: HTTP status and, for errors, the `reason` from the JSON body. */
export interface ApnsResult {
  status: number;
  reason?: string;
}

/** Who a request is for (logging, the test sink). */
export interface PushTarget {
  userId: string;
  deviceId: string;
}

/** Sends one notification to one device token. Swappable so tests never touch the network. */
export interface PushTransport {
  send(request: ApnsRequest, target: PushTarget): Promise<ApnsResult>;
  close(): Promise<void>;
}

export interface ApnsCredentials {
  keyId: string;
  teamId: string;
  /** Contents of the .p8 key (PKCS#8 PEM). */
  privateKey: string;
}

const HOSTS: Record<ApnsEnvironment, string> = {
  sandbox: 'https://api.sandbox.push.apple.com',
  production: 'https://api.push.apple.com',
};

/** Apple rejects provider tokens older than 60 min and throttles refreshes more often than 20 min. */
const TOKEN_TTL_MS = 50 * 60_000;
const REQUEST_TIMEOUT_MS = 10_000;

/**
 * APNs over HTTP/2 (`node:http2`, one long-lived session per host) with token-based auth: an ES256
 * JWT (kid = key id, iss = team id) reused for ~50 minutes.
 */
export class ApnsTransport implements PushTransport {
  private readonly sessions = new Map<ApnsEnvironment, ClientHttp2Session>();
  private jwt: { value: string; issuedAt: number } | undefined;
  private key: ReturnType<typeof importPKCS8> | undefined;

  constructor(
    private readonly credentials: ApnsCredentials,
    /** Overridable for tests (a local h2c server). */
    private readonly hosts: Record<ApnsEnvironment, string> = HOSTS,
  ) {}

  async send(request: ApnsRequest, _target?: PushTarget): Promise<ApnsResult> {
    const result = await this.post(request, await this.providerToken());
    if (result.status === 403 && result.reason === 'ExpiredProviderToken') {
      return this.post(request, await this.providerToken(true));
    }
    return result;
  }

  async close(): Promise<void> {
    for (const session of this.sessions.values()) session.close();
    this.sessions.clear();
  }

  private async providerToken(refresh = false): Promise<string> {
    const now = Date.now();
    if (!refresh && this.jwt && now - this.jwt.issuedAt < TOKEN_TTL_MS) return this.jwt.value;
    this.key ??= importPKCS8(this.credentials.privateKey, 'ES256');
    const value = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: this.credentials.keyId })
      .setIssuer(this.credentials.teamId)
      .setIssuedAt(Math.floor(now / 1000))
      .sign(await this.key);
    this.jwt = { value, issuedAt: now };
    return value;
  }

  private session(environment: ApnsEnvironment): ClientHttp2Session {
    const existing = this.sessions.get(environment);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const session = connect(this.hosts[environment]);
    const forget = () => {
      if (this.sessions.get(environment) === session) this.sessions.delete(environment);
    };
    session.on('error', forget);
    session.on('goaway', forget);
    session.on('close', forget);
    // Idle sessions must not keep the process alive on shutdown.
    session.unref();
    this.sessions.set(environment, session);
    return session;
  }

  private post(request: ApnsRequest, jwt: string): Promise<ApnsResult> {
    return new Promise<ApnsResult>((resolve, reject) => {
      let settled = false;
      const done = (error: Error | null, result?: ApnsResult) => {
        if (settled) return;
        settled = true;
        if (error) reject(error);
        else resolve(result!);
      };
      let stream;
      try {
        stream = this.session(request.environment).request({
          [constants.HTTP2_HEADER_METHOD]: 'POST',
          [constants.HTTP2_HEADER_PATH]: `/3/device/${request.token}`,
          [constants.HTTP2_HEADER_CONTENT_TYPE]: 'application/json',
          authorization: `bearer ${jwt}`,
          ...request.headers,
        });
      } catch (error) {
        done(error instanceof Error ? error : new Error(String(error)));
        return;
      }
      let status = 0;
      let body = '';
      stream.setEncoding('utf8');
      stream.setTimeout(REQUEST_TIMEOUT_MS, () => {
        stream.close(constants.NGHTTP2_CANCEL);
        done(new Error('APNs request timed out'));
      });
      stream.on('response', (headers) => {
        status = Number(headers[constants.HTTP2_HEADER_STATUS] ?? 0);
      });
      stream.on('data', (chunk: string) => {
        body += chunk;
      });
      stream.on('end', () => {
        let reason: string | undefined;
        try {
          reason = body ? (JSON.parse(body) as { reason?: string }).reason : undefined;
        } catch {
          reason = undefined;
        }
        if (status === 0) done(new Error('APNs request ended without a response'));
        else done(null, { status, ...(reason ? { reason } : {}) });
      });
      stream.on('error', (error) => done(error));
      stream.on('close', () => done(new Error('APNs stream closed without a response')));
      stream.end(JSON.stringify(request.payload));
    });
  }
}
