import { randomUUID } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import { errors as joseErrors, jwtVerify, SignJWT } from 'jose';
import { ApiError } from '../common/api-error';
import { hmac, randomToken, sha256 } from '../common/crypto';
import { days, iso } from '../common/time';
import { ENV, type Env } from '../config/env';
import type { RefreshToken } from '../generated/prisma/client';
import { PrismaService, type Tx } from '../prisma/prisma.service';

/** Reuse of a rotated refresh token inside this window returns the same pair (client retries). */
const REUSE_GRACE_MS = 30_000;
const ISSUER = 'metly';
const AUDIENCE = 'metly-app';

export interface AccessClaims {
  userId: string;
  familyId: string;
}

export interface SessionTokens {
  accessToken: string;
  refreshToken: string;
  tokenType: 'Bearer';
  accessTokenExpiresAt: string;
  refreshTokenExpiresAt: string;
}

@Injectable()
export class TokensService {
  private readonly key: Uint8Array;

  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {
    this.key = new TextEncoder().encode(env.JWT_SECRET);
  }

  /** New session (sign-in): a new refresh-token family. */
  async issue(userId: string, tx: Tx = this.prisma): Promise<SessionTokens> {
    const familyId = randomUUID();
    const refreshToken = randomToken(32);
    const now = new Date();
    const row = await tx.refreshToken.create({
      data: {
        id: randomUUID(),
        userId,
        familyId,
        tokenHash: sha256(refreshToken),
        createdAt: now,
        expiresAt: new Date(now.getTime() + days(this.env.REFRESH_TOKEN_TTL_DAYS)),
      },
    });
    return this.pair(row, refreshToken, now);
  }

  /**
   * Rotates a refresh token. Single use: the child is derived from the parent's hash, so a retry of
   * the same rotation inside the grace window yields byte-identical tokens. A replay after that window
   * means the token leaked — the whole family is revoked.
   */
  async refresh(refreshToken: string): Promise<SessionTokens> {
    const invalid = () => ApiError.unauthorized('Your session ended. Sign in again.', 'invalid_grant');
    // A detected replay revokes the family and must commit before the 401 goes out.
    const REVOKED = Symbol('revoked');
    const result = await this.prisma.write(async (tx): Promise<SessionTokens | typeof REVOKED> => {
      const parentHash = sha256(refreshToken);
      const rows = await tx.$queryRaw<RefreshToken[]>`
        SELECT id, user_id AS "userId", family_id AS "familyId", token_hash AS "tokenHash", created_at AS "createdAt",
               expires_at AS "expiresAt", rotated_at AS "rotatedAt", revoked_at AS "revokedAt"
        FROM refresh_tokens WHERE token_hash = ${parentHash} FOR UPDATE`;
      const parent = rows[0];
      if (!parent || parent.revokedAt) throw invalid();
      const now = new Date();
      if (parent.expiresAt <= now) throw invalid();

      const childToken = hmac(this.env.JWT_SECRET, `refresh:${parentHash}`);
      if (parent.rotatedAt) {
        if (now.getTime() - parent.rotatedAt.getTime() > REUSE_GRACE_MS) {
          await tx.refreshToken.updateMany({ where: { familyId: parent.familyId, revokedAt: null }, data: { revokedAt: now } });
          return REVOKED;
        }
        const child = await tx.refreshToken.findUnique({ where: { tokenHash: sha256(childToken) } });
        if (!child || child.revokedAt) throw invalid();
        return this.pair(child, childToken, parent.rotatedAt);
      }

      await tx.refreshToken.update({ where: { id: parent.id }, data: { rotatedAt: now } });
      const child = await tx.refreshToken.create({
        data: {
          id: randomUUID(),
          userId: parent.userId,
          familyId: parent.familyId,
          tokenHash: sha256(childToken),
          createdAt: now,
          expiresAt: new Date(now.getTime() + days(this.env.REFRESH_TOKEN_TTL_DAYS)),
        },
      });
      return this.pair(child, childToken, now);
    });
    if (result === REVOKED) throw invalid();
    return result;
  }

  /** Revokes one refresh token's family (this device) or every session of the user. */
  async revoke(userId: string, opts: { refreshToken?: string | null; allDevices: boolean }): Promise<void> {
    const now = new Date();
    if (opts.allDevices) {
      await this.prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: now } });
      return;
    }
    if (!opts.refreshToken) return;
    const row = await this.prisma.refreshToken.findUnique({ where: { tokenHash: sha256(opts.refreshToken) } });
    if (row && row.userId === userId) {
      await this.prisma.refreshToken.updateMany({ where: { familyId: row.familyId, revokedAt: null }, data: { revokedAt: now } });
    }
  }

  async verifyAccess(token: string): Promise<AccessClaims> {
    try {
      const { payload } = await jwtVerify(token, this.key, { issuer: ISSUER, audience: AUDIENCE, algorithms: ['HS256'] });
      if (typeof payload.sub !== 'string' || typeof payload.fam !== 'string') throw ApiError.unauthorized();
      return { userId: payload.sub, familyId: payload.fam };
    } catch (error) {
      if (error instanceof joseErrors.JWTExpired) throw ApiError.unauthorized('The access token expired.', 'token_expired');
      if (error instanceof ApiError) throw error;
      throw ApiError.unauthorized();
    }
  }

  /** True while the session's family is not revoked (checked on WebSocket connect and sensitive calls). */
  async isFamilyActive(familyId: string): Promise<boolean> {
    const live = await this.prisma.refreshToken.findFirst({ where: { familyId, revokedAt: null }, select: { id: true } });
    return live !== null;
  }

  /** Access token issued at `issuedAt` — deterministic for a given child token (HS256). */
  private async pair(row: RefreshToken, refreshToken: string, issuedAt: Date): Promise<SessionTokens> {
    const iat = Math.floor(issuedAt.getTime() / 1000);
    const exp = iat + this.env.ACCESS_TOKEN_TTL_SECONDS;
    const accessToken = await new SignJWT({ fam: row.familyId })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setSubject(row.userId)
      .setIssuer(ISSUER)
      .setAudience(AUDIENCE)
      .setJti(row.id)
      .setIssuedAt(iat)
      .setExpirationTime(exp)
      .sign(this.key);
    return {
      accessToken,
      refreshToken,
      tokenType: 'Bearer',
      accessTokenExpiresAt: iso(new Date(exp * 1000)),
      refreshTokenExpiresAt: iso(row.expiresAt),
    };
  }
}
