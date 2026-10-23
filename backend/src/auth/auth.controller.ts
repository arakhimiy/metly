import { randomUUID } from 'node:crypto';
import { Body, Controller, HttpCode, Inject, NotFoundException, Post } from '@nestjs/common';
import { z } from 'zod';
import { RateLimit } from '../common/rate-limit';
import { type AuthedUser, CurrentUser, Public } from '../common/request';
import { iso } from '../common/time';
import { parse } from '../common/validate';
import { ENV, type Env } from '../config/env';
import type { AuthProvider } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AppleService } from './apple.service';
import { GoogleService } from './google.service';
import { TokensService } from './tokens.service';

const nullableString = z.string().nullish().transform((v) => v ?? null);

const AppleBody = z.object({
  identityToken: z.string().min(1),
  authorizationCode: nullableString,
  userIdentifier: z.string().min(1),
  fullName: z.object({ givenName: nullableString, familyName: nullableString }).nullish(),
  email: nullableString,
  nonce: nullableString,
});
const GoogleBody = z.object({ idToken: z.string().min(1), nonce: nullableString });
const RefreshBody = z.object({ refreshToken: z.string().min(1) });
const LogoutBody = z.object({ refreshToken: nullableString, allDevices: z.boolean().default(false) });
const DevBody = z.object({ subject: z.string().min(1).max(100), email: nullableString, fullName: nullableString });

interface Resolved {
  userId: string;
  isNewUser: boolean;
}

/** The openapi `User`. */
export async function userWire(prisma: PrismaService, userId: string) {
  const user = await prisma.user.findUniqueOrThrow({
    where: { id: userId },
    include: { identities: { select: { provider: true } }, profile: { select: { isSetupComplete: true, deletedAt: true } } },
  });
  return {
    id: user.id,
    ...(user.email ? { email: user.email } : {}),
    authProviders: [...new Set(user.identities.map((i) => i.provider))],
    createdAt: iso(user.createdAt),
    profileComplete: Boolean(user.profile && !user.profile.deletedAt && user.profile.isSetupComplete),
  };
}

@Controller('v1/auth')
export class AuthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TokensService,
    private readonly apple: AppleService,
    private readonly google: GoogleService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  @Public()
  @RateLimit('auth')
  @Post('apple')
  @HttpCode(200)
  async signInWithApple(@Body() body: unknown) {
    const input = parse(AppleBody, body);
    const identity = await this.apple.verify(input.identityToken, input.userIdentifier, input.nonce);
    const email = identity.email ?? input.email;
    // Apple sends the name only on the first authorization; it prefills SETUP_PROFILE.
    const given = [input.fullName?.givenName, input.fullName?.familyName].filter(Boolean).join(' ').trim();
    const appleRefreshToken = input.authorizationCode ? await this.apple.exchangeCode(input.authorizationCode, identity.audience) : null;
    const resolved = await this.resolveUser('apple', identity.subject, email, appleRefreshToken);
    return this.respond(resolved, given || null);
  }

  @Public()
  @RateLimit('auth')
  @Post('google')
  @HttpCode(200)
  async signInWithGoogle(@Body() body: unknown) {
    const input = parse(GoogleBody, body);
    const identity = await this.google.verify(input.idToken, input.nonce);
    const resolved = await this.resolveUser('google', identity.subject, identity.email, null);
    return this.respond(resolved, identity.name);
  }

  /** Local development and automated tests only; 404 everywhere else. */
  @Public()
  @RateLimit('auth')
  @Post('dev')
  @HttpCode(200)
  async signInForDevelopment(@Body() body: unknown) {
    if (!this.env.DEV_AUTH_ENABLED || this.env.NODE_ENV === 'production') throw new NotFoundException();
    const input = parse(DevBody, body);
    const resolved = await this.resolveUser('apple', `dev:${input.subject}`, input.email ?? `${input.subject}@dev.metly.test`, null);
    return this.respond(resolved, input.fullName);
  }

  @Public()
  @RateLimit('auth')
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() body: unknown) {
    const { refreshToken } = parse(RefreshBody, body);
    return this.tokens.refresh(refreshToken);
  }

  @Post('logout')
  @HttpCode(204)
  async logout(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    const input = parse(LogoutBody, body ?? {});
    await this.tokens.revoke(user.id, { refreshToken: input.refreshToken, allDevices: input.allDevices });
  }

  /** Accounts are keyed by provider subject; identities with the same email are not merged in v1. */
  private async resolveUser(provider: AuthProvider, subject: string, email: string | null, appleRefreshToken: string | null): Promise<Resolved> {
    return this.prisma.write(async (tx) => {
      const identity = await tx.authIdentity.findUnique({ where: { provider_subject: { provider, subject } } });
      if (identity) {
        if (appleRefreshToken || (email && !identity.email)) {
          await tx.authIdentity.update({
            where: { id: identity.id },
            data: { ...(appleRefreshToken ? { appleRefreshToken } : {}), ...(email && !identity.email ? { email } : {}) },
          });
        }
        return { userId: identity.userId, isNewUser: false };
      }
      const userId = randomUUID();
      await tx.user.create({ data: { id: userId, email } });
      await tx.authIdentity.create({ data: { userId, provider, subject, email, appleRefreshToken } });
      await tx.entitlement.create({ data: { userId } });
      return { userId, isNewUser: true };
    });
  }

  private async respond(resolved: Resolved, suggestedName: string | null) {
    const [session, user, profile] = await Promise.all([
      this.tokens.issue(resolved.userId),
      userWire(this.prisma, resolved.userId),
      this.prisma.profile.findUnique({ where: { userId: resolved.userId }, select: { fullName: true } }),
    ]);
    const name = suggestedName ?? profile?.fullName ?? null;
    return { session, user, isNewUser: resolved.isNewUser, ...(name ? { suggestedName: name } : {}) };
  }
}
