import { Body, Controller, Get, Patch, Put } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { type AuthedUser, CurrentUser } from '../common/request';
import { iso } from '../common/time';
import { parse } from '../common/validate';
import type { Profile } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { profileToWire } from './mappers';
import { RecordsService } from './records.service';
import { restRecord } from './rest';
import {
  DEFAULT_NOTIFICATION_PREFS,
  DEFAULT_PRIVACY,
  NotificationPrefs,
  nullableUuid,
  PrivacySettings,
  ProfileIn,
  timestamp,
} from './wire';

const SettingsPatch = z.object({
  notificationPrefs: NotificationPrefs.nullish(),
  privacySettings: PrivacySettings.nullish(),
  linksPaused: z.boolean().nullish(),
  defaultCardId: nullableUuid.optional(),
  updatedAt: timestamp,
});

function settingsWire(p: Profile) {
  const wire = profileToWire(p);
  return {
    notificationPrefs: wire.notificationPrefs,
    privacySettings: wire.privacySettings,
    linksPaused: p.linksPaused,
    ...(p.defaultCardId ? { defaultCardId: p.defaultCardId } : {}),
    updatedAt: iso(p.updatedAt),
  };
}

@Controller('v1/me')
export class ProfileController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
  ) {}

  private async liveProfile(userId: string) {
    const profile = await this.prisma.profile.findUnique({ where: { userId } });
    return profile && !profile.deletedAt ? profile : null;
  }

  @Get('profile')
  async get(@CurrentUser() user: AuthedUser) {
    const profile = await this.liveProfile(user.id);
    if (!profile) throw ApiError.notFound('Set up your profile first.');
    return profileToWire(profile);
  }

  @Put('profile')
  async put(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    const incoming = parse(ProfileIn, body);
    const { result, out } = await this.records.write(user.id, (ctx) => this.records.upsertProfile(ctx, incoming));
    return restRecord('profile', incoming.id, result, out);
  }

  @Get('settings')
  async settings(@CurrentUser() user: AuthedUser) {
    const profile = await this.liveProfile(user.id);
    if (!profile) {
      return {
        notificationPrefs: DEFAULT_NOTIFICATION_PREFS,
        privacySettings: DEFAULT_PRIVACY,
        linksPaused: false,
        updatedAt: iso(new Date(0)),
      };
    }
    return settingsWire(profile);
  }

  /** Partial update applied as a profile write, so LWW and the Pause All Links cascade still hold. */
  @Patch('settings')
  async patchSettings(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    const patch = parse(SettingsPatch, body);
    const profile = await this.liveProfile(user.id);
    if (!profile) throw ApiError.notFound('Set up your profile first.');
    const merged = ProfileIn.parse({
      ...profileToWire(profile),
      ...(patch.notificationPrefs ? { notificationPrefs: patch.notificationPrefs } : {}),
      ...(patch.privacySettings ? { privacySettings: patch.privacySettings } : {}),
      ...(patch.linksPaused !== null && patch.linksPaused !== undefined ? { linksPaused: patch.linksPaused } : {}),
      ...(patch.defaultCardId !== undefined ? { defaultCardId: patch.defaultCardId } : {}),
      updatedAt: patch.updatedAt.toISOString(),
    });
    await this.records.write(user.id, (ctx) => this.records.upsertProfile(ctx, merged));
    const stored = await this.liveProfile(user.id);
    return settingsWire(stored ?? profile);
  }
}
