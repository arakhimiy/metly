import { createPrivateKey } from 'node:crypto';
import { Inject, Injectable, Logger, type OnModuleInit } from '@nestjs/common';
import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';
import { ApiError } from '../common/api-error';
import { sha256 } from '../common/crypto';
import { DomainEvents } from '../common/domain-events';
import { ENV, type Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';

const APPLE_ISSUER = 'https://appleid.apple.com';
const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export interface AppleIdentity {
  subject: string;
  email: string | null;
  audience: string;
}

/** Sign in with Apple: identity token verification, code exchange and token revocation. */
@Injectable()
export class AppleService implements OnModuleInit {
  private readonly logger = new Logger(AppleService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly events: DomainEvents,
    @Inject(ENV) private readonly env: Env,
  ) {}

  onModuleInit() {
    // App Store rule: deleting the account revokes the Sign in with Apple token.
    this.events.on('account.deleting', ({ userId }) => this.revokeAll(userId));
  }

  async verify(identityToken: string, expectedSubject: string, rawNonce: string | null | undefined): Promise<AppleIdentity> {
    if (this.env.APPLE_BUNDLE_IDS.length === 0) throw ApiError.unavailable('Sign in with Apple is not configured.');
    let payload;
    try {
      ({ payload } = await jwtVerify(identityToken, appleKeys, { issuer: APPLE_ISSUER, audience: this.env.APPLE_BUNDLE_IDS }));
    } catch {
      throw ApiError.unauthorized('The Apple identity token is invalid.');
    }
    if (payload.sub !== expectedSubject) throw ApiError.unauthorized('The Apple identity token does not match this user.');
    if (rawNonce && payload.nonce !== sha256(rawNonce)) throw ApiError.unauthorized('The Apple sign-in nonce does not match.');
    const audience = Array.isArray(payload.aud) ? payload.aud[0]! : (payload.aud as string);
    return { subject: payload.sub, email: typeof payload.email === 'string' ? payload.email : null, audience };
  }

  private get canTalkToApple() {
    return Boolean(this.env.APPLE_TEAM_ID && this.env.APPLE_SIGNIN_KEY_ID && this.env.APPLE_SIGNIN_PRIVATE_KEY);
  }

  /** Client secret for Apple's REST endpoints (ES256, valid 5 minutes). */
  private async clientSecret(clientId: string): Promise<string> {
    const key = createPrivateKey(this.env.APPLE_SIGNIN_PRIVATE_KEY!);
    const now = Math.floor(Date.now() / 1000);
    return new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: this.env.APPLE_SIGNIN_KEY_ID! })
      .setIssuer(this.env.APPLE_TEAM_ID!)
      .setSubject(clientId)
      .setAudience(APPLE_ISSUER)
      .setIssuedAt(now)
      .setExpirationTime(now + 300)
      .sign(key);
  }

  /** Exchanges the authorization code for a refresh token (needed to revoke later). Best effort. */
  async exchangeCode(code: string, clientId: string): Promise<string | null> {
    if (!this.canTalkToApple) {
      this.logger.warn('Apple sign-in key not configured; skipping code exchange (revocation on deletion will not work).');
      return null;
    }
    try {
      const response = await fetch(`${APPLE_ISSUER}/auth/token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: await this.clientSecret(clientId),
          code,
          grant_type: 'authorization_code',
        }),
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) {
        this.logger.warn({ status: response.status }, 'Apple code exchange failed');
        return null;
      }
      const body = (await response.json()) as { refresh_token?: string };
      return body.refresh_token ?? null;
    } catch (error) {
      this.logger.warn({ err: error }, 'Apple code exchange failed');
      return null;
    }
  }

  async revokeAll(userId: string): Promise<void> {
    const identities = await this.prisma.authIdentity.findMany({
      where: { userId, provider: 'apple', appleRefreshToken: { not: null } },
    });
    if (identities.length === 0 || !this.canTalkToApple) return;
    for (const identity of identities) {
      for (const clientId of this.env.APPLE_BUNDLE_IDS) {
        const response = await fetch(`${APPLE_ISSUER}/auth/revoke`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            client_id: clientId,
            client_secret: await this.clientSecret(clientId),
            token: identity.appleRefreshToken!,
            token_type_hint: 'refresh_token',
          }),
          signal: AbortSignal.timeout(10_000),
        }).catch(() => null);
        if (response?.ok) break;
      }
    }
  }
}
