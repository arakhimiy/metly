import { Inject, Injectable, Logger } from '@nestjs/common';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { ApiError } from '../common/api-error';
import { ENV, type Env } from '../config/env';

export interface TelegramIdentity {
  /** OIDC `sub`: stable per bot, the account key. */
  subject: string;
  name: string | null;
}

/** What the app sends to start a sign-in (`GET /v1/auth/telegram/authorize`). */
export interface TelegramAuthorizeParams {
  codeChallenge: string;
  state: string;
  nonce: string;
}

/** Path of the redirect URI registered with @BotFather (Login Widget → Allowed URLs). */
export const TELEGRAM_CALLBACK_PATH = '/v1/auth/telegram/callback';

/**
 * Log In with Telegram — OpenID Connect Authorization Code flow with PKCE
 * (https://core.telegram.org/bots/telegram-login § OpenID Connect).
 *
 * 1. The app opens `GET /v1/auth/telegram/authorize` in ASWebAuthenticationSession; we redirect to
 *    Telegram with our client id and the registered redirect URI, so the app never needs either.
 * 2. Telegram redirects back to `/v1/auth/telegram/callback`, which hands `code` + `state` to the app
 *    through its URL scheme.
 * 3. The app posts `code`, its PKCE `codeVerifier` and `nonce` to `POST /v1/auth/telegram`; we redeem
 *    the code with the client secret (it never leaves the server) and verify the signed `id_token`.
 *
 * A code intercepted on the way back is useless without the verifier, which stays in the app.
 */
@Injectable()
export class TelegramLoginService {
  private readonly logger = new Logger(TelegramLoginService.name);
  private readonly keys: ReturnType<typeof createRemoteJWKSet>;

  constructor(@Inject(ENV) private readonly env: Env) {
    this.keys = createRemoteJWKSet(new URL('/.well-known/jwks.json', this.issuer));
  }

  get isConfigured(): boolean {
    return Boolean(this.env.TELEGRAM_LOGIN_CLIENT_ID && this.env.TELEGRAM_LOGIN_CLIENT_SECRET);
  }

  private get issuer(): string {
    return this.env.TELEGRAM_OIDC_ISSUER.replace(/\/+$/, '');
  }

  get redirectUri(): string {
    return new URL(TELEGRAM_CALLBACK_PATH, this.env.API_BASE_URL).toString();
  }

  /** Telegram's authorization URL for this sign-in attempt. */
  authorizationUrl(params: TelegramAuthorizeParams): string {
    const clientId = this.requireClientId();
    const url = new URL('/auth', this.issuer);
    url.search = new URLSearchParams({
      client_id: clientId,
      redirect_uri: this.redirectUri,
      response_type: 'code',
      scope: 'openid profile',
      state: params.state,
      nonce: params.nonce,
      code_challenge: params.codeChallenge,
      code_challenge_method: 'S256',
    }).toString();
    return url.toString();
  }

  /** Where the callback sends the browser: back into the app with Telegram's answer. */
  appRedirect(query: Record<string, string>): string {
    return `${this.env.APP_URL_SCHEME}://auth/telegram?${new URLSearchParams(query).toString()}`;
  }

  /** Redeems the authorization code and returns the verified identity. */
  async signIn(code: string, codeVerifier: string, nonce: string): Promise<TelegramIdentity> {
    const idToken = await this.exchange(code, codeVerifier);
    return this.verify(idToken, nonce);
  }

  private async exchange(code: string, codeVerifier: string): Promise<string> {
    const clientId = this.requireClientId();
    const secret = this.env.TELEGRAM_LOGIN_CLIENT_SECRET as string;
    let response: Response;
    try {
      response = await fetch(new URL('/token', this.issuer), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Authorization: `Basic ${Buffer.from(`${clientId}:${secret}`).toString('base64')}`,
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          code,
          redirect_uri: this.redirectUri,
          client_id: clientId,
          code_verifier: codeVerifier,
        }),
        signal: AbortSignal.timeout(10_000),
      });
    } catch (error) {
      this.logger.warn({ err: error }, 'Telegram token endpoint unreachable');
      throw ApiError.unavailable('Telegram sign-in is not reachable right now. Try again.');
    }
    const body = (await response.json().catch(() => ({}))) as { id_token?: unknown; error?: unknown };
    if (!response.ok || typeof body.id_token !== 'string') {
      // 4xx: an expired, reused or forged code, or a verifier that does not match.
      this.logger.warn({ status: response.status, error: body.error }, 'Telegram code exchange refused');
      if (response.status >= 500) throw ApiError.unavailable('Telegram sign-in is not reachable right now. Try again.');
      throw ApiError.unauthorized('The Telegram sign-in expired or was already used. Try again.');
    }
    return body.id_token;
  }

  private async verify(idToken: string, nonce: string): Promise<TelegramIdentity> {
    let payload: Awaited<ReturnType<typeof jwtVerify>>['payload'];
    try {
      ({ payload } = await jwtVerify(idToken, this.keys, {
        issuer: this.issuer,
        audience: this.requireClientId(),
        algorithms: ['RS256', 'ES256'],
      }));
    } catch {
      throw ApiError.unauthorized('The Telegram ID token is invalid.');
    }
    if (payload.nonce !== nonce) throw ApiError.unauthorized('The Telegram sign-in nonce does not match.');
    if (typeof payload.sub !== 'string' || payload.sub.length === 0) throw ApiError.unauthorized('The Telegram ID token is invalid.');
    const given = [payload.given_name, payload.family_name].filter((v): v is string => typeof v === 'string' && v.trim() !== '');
    const name = typeof payload.name === 'string' && payload.name.trim() ? payload.name.trim() : given.join(' ').trim() || null;
    return { subject: payload.sub, name };
  }

  private requireClientId(): string {
    if (!this.isConfigured) throw ApiError.unavailable('Sign in with Telegram is not configured.');
    return this.env.TELEGRAM_LOGIN_CLIENT_ID as string;
  }
}
