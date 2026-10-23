import { Body, Controller, Delete, Get, Headers, HttpCode, Logger, Param, Post, Query, Res } from '@nestjs/common';
import type { Response } from 'express';
import { z } from 'zod';
import { ApiError } from '../../common/api-error';
import { safeEqual } from '../../common/crypto';
import { Public } from '../../common/request';
import { parse } from '../../common/validate';
import type { Card } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { UUID_PARAM } from '../../records/rest';
import { PUSH_TOKEN } from './pass-push';
import { PKPASS_CONTENT_TYPE, WalletService } from './wallet.service';

const RegisterBody = z.object({ pushToken: z.string().regex(PUSH_TOKEN, 'must be an APNs device token') });
const LogBody = z.object({ logs: z.array(z.string()).max(100).default([]) });
const DEVICE_ID = /^[A-Za-z0-9._-]{1,128}$/;

/** Wallet's update tag: epoch milliseconds of the card's last public change. */
const updateTag = (card: Pick<Card, 'contentUpdatedAt'>) => card.contentUpdatedAt.getTime();

/**
 * Apple PassKit web service (https://developer.apple.com/documentation/walletpasses/adding-a-web-service-to-update-passes),
 * called by Wallet at `webServiceURL` = `${API_BASE_URL}/passkit`. Pass-scoped calls authenticate with
 * `Authorization: ApplePass <authenticationToken>` (= card.passAuthToken). Default public rate limit.
 */
@Public()
@Controller('passkit/v1')
export class PassKitController {
  private readonly logger = new Logger('PassKit');

  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
  ) {}

  private assertPassType(passTypeIdentifier: string) {
    if (passTypeIdentifier !== this.wallet.passTypeIdentifier) throw ApiError.notFound('Unknown pass type.');
  }

  private assertDevice(deviceLibraryIdentifier: string) {
    if (!DEVICE_ID.test(deviceLibraryIdentifier)) throw ApiError.notFound('Unknown device.');
  }

  /** The card behind a serial number, if the ApplePass token matches; otherwise 401. */
  private async authorizedCard(serialNumber: string, authorization: string | undefined): Promise<Card> {
    const token = /^ApplePass\s+(\S+)$/i.exec(authorization ?? '')?.[1];
    const card = token && UUID_PARAM.test(serialNumber) ? await this.prisma.card.findUnique({ where: { id: serialNumber.toLowerCase() } }) : null;
    if (!card || !token || !safeEqual(token, card.passAuthToken)) throw ApiError.unauthorized('Invalid pass authentication token.');
    return card;
  }

  @Post('devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier/:serialNumber')
  async register(
    @Param('deviceLibraryIdentifier') deviceLibraryIdentifier: string,
    @Param('passTypeIdentifier') passTypeIdentifier: string,
    @Param('serialNumber') serialNumber: string,
    @Headers('authorization') authorization: string | undefined,
    @Body() body: unknown,
    @Res({ passthrough: true }) res: Response,
  ): Promise<void> {
    this.assertPassType(passTypeIdentifier);
    this.assertDevice(deviceLibraryIdentifier);
    const card = await this.authorizedCard(serialNumber, authorization);
    const { pushToken } = parse(RegisterBody, body);
    const key = { deviceLibraryIdentifier, serialNumber: card.id };
    const existing = await this.prisma.passRegistration.findUnique({ where: { deviceLibraryIdentifier_serialNumber: key } });
    if (existing) {
      if (existing.pushToken !== pushToken) {
        await this.prisma.passRegistration.update({ where: { deviceLibraryIdentifier_serialNumber: key }, data: { pushToken } });
      }
      res.status(200);
      return;
    }
    await this.prisma.passRegistration.upsert({
      where: { deviceLibraryIdentifier_serialNumber: key },
      create: { ...key, pushToken },
      update: { pushToken },
    });
    res.status(201);
  }

  @Delete('devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier/:serialNumber')
  @HttpCode(200)
  async unregister(
    @Param('deviceLibraryIdentifier') deviceLibraryIdentifier: string,
    @Param('passTypeIdentifier') passTypeIdentifier: string,
    @Param('serialNumber') serialNumber: string,
    @Headers('authorization') authorization: string | undefined,
  ): Promise<void> {
    this.assertPassType(passTypeIdentifier);
    this.assertDevice(deviceLibraryIdentifier);
    const card = await this.authorizedCard(serialNumber, authorization);
    await this.prisma.passRegistration.deleteMany({ where: { deviceLibraryIdentifier, serialNumber: card.id } });
  }

  /** Serials registered on a device whose pass changed after `passesUpdatedSince` (204 when none). */
  @Get('devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier')
  async updatedSerials(
    @Param('deviceLibraryIdentifier') deviceLibraryIdentifier: string,
    @Param('passTypeIdentifier') passTypeIdentifier: string,
    @Query('passesUpdatedSince') passesUpdatedSince: string | undefined,
    @Res({ passthrough: true }) res: Response,
  ) {
    this.assertPassType(passTypeIdentifier);
    this.assertDevice(deviceLibraryIdentifier);
    const registrations = await this.prisma.passRegistration.findMany({ where: { deviceLibraryIdentifier }, select: { serialNumber: true } });
    const since = passesUpdatedSince && /^\d{1,16}$/.test(passesUpdatedSince) ? Number(passesUpdatedSince) : null;
    const cards =
      registrations.length > 0
        ? await this.prisma.card.findMany({
            where: { id: { in: registrations.map((r) => r.serialNumber) } },
            select: { id: true, contentUpdatedAt: true },
          })
        : [];
    const updated = cards.filter((c) => since === null || updateTag(c) > since);
    if (updated.length === 0) {
      res.status(204);
      return undefined;
    }
    return {
      serialNumbers: updated.map((c) => c.id),
      lastUpdated: String(Math.max(...updated.map(updateTag))),
    };
  }

  /** The latest pass; honours `If-Modified-Since` (HTTP dates have second precision). */
  @Get('passes/:passTypeIdentifier/:serialNumber')
  async latest(
    @Param('passTypeIdentifier') passTypeIdentifier: string,
    @Param('serialNumber') serialNumber: string,
    @Headers('authorization') authorization: string | undefined,
    @Headers('if-modified-since') ifModifiedSince: string | undefined,
    @Res() res: Response,
  ) {
    this.assertPassType(passTypeIdentifier);
    const card = await this.authorizedCard(serialNumber, authorization);
    const lastModified = card.contentUpdatedAt.toUTCString();
    const since = ifModifiedSince ? Date.parse(ifModifiedSince) : Number.NaN;
    if (!Number.isNaN(since) && Math.floor(card.contentUpdatedAt.getTime() / 1000) * 1000 <= since) {
      res.status(304).setHeader('Last-Modified', lastModified);
      res.end();
      return;
    }
    const profile = await this.prisma.profile.findUnique({ where: { userId: card.userId } });
    if (!profile) throw ApiError.notFound('Pass not found.');
    this.wallet.assertConfigured();
    const body = await this.wallet.render(card, profile);
    res.status(200);
    res.setHeader('Content-Type', PKPASS_CONTENT_TYPE);
    res.setHeader('Last-Modified', lastModified);
    res.setHeader('Cache-Control', 'no-cache');
    res.send(body);
  }

  /** Wallet reports web-service problems here. */
  @Post('log')
  @HttpCode(200)
  log(@Body() body: unknown): void {
    const { logs } = parse(LogBody, body ?? {});
    for (const message of logs.slice(0, 20)) this.logger.warn({ message: message.slice(0, 500) }, 'wallet log');
  }
}
