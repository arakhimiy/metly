import { Body, Controller, Delete, HttpCode, Param, Put } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../../common/api-error';
import { type AuthedUser, CurrentUser } from '../../common/request';
import { parse } from '../../common/validate';
import { PrismaService } from '../../prisma/prisma.service';
import { isValidTimeZone } from '../jobs/time-zone';

const DeviceRegistration = z.object({
  deviceId: z.string().min(1).max(200).optional(),
  apnsToken: z
    .string()
    .regex(/^[0-9a-fA-F]{32,400}$/, 'must be the hex APNs device token')
    .transform((v) => v.toLowerCase()),
  apnsEnvironment: z.enum(['sandbox', 'production']),
  platform: z.literal('ios'),
  appVersion: z.string().max(40),
  osVersion: z.string().max(40),
  locale: z.string().max(40),
  timeZone: z.string().max(64).refine(isValidTimeZone, 'must be an IANA time zone'),
});

function deviceIdParam(value: string): string {
  if (value.length === 0 || value.length > 200) throw ApiError.validation({ deviceId: 'must be 1–200 characters' });
  return value;
}

@Controller('v1/me/devices')
export class DevicesController {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Upsert by (user, deviceId). An APNs token belongs to one install: when it shows up under another
   * user (sign-out → sign-in on the same phone) or another deviceId, the older rows go, so a phone
   * never receives a previous account's pushes.
   */
  @Put(':deviceId')
  @HttpCode(204)
  async register(@CurrentUser() user: AuthedUser, @Param('deviceId') rawId: string, @Body() body: unknown) {
    const deviceId = deviceIdParam(rawId);
    const input = parse(DeviceRegistration, body);
    if (input.deviceId !== undefined && input.deviceId !== deviceId) {
      throw ApiError.validation({ deviceId: 'must match the deviceId in the path' });
    }
    const data = {
      apnsToken: input.apnsToken,
      apnsEnvironment: input.apnsEnvironment,
      appVersion: input.appVersion,
      osVersion: input.osVersion,
      locale: input.locale,
      timeZone: input.timeZone,
    };
    await this.prisma.write(async (tx) => {
      await tx.device.deleteMany({ where: { apnsToken: input.apnsToken, NOT: { userId: user.id, deviceId } } });
      await tx.device.upsert({
        where: { userId_deviceId: { userId: user.id, deviceId } },
        create: { userId: user.id, deviceId, ...data },
        update: data,
      });
    });
  }

  @Delete(':deviceId')
  @HttpCode(204)
  async unregister(@CurrentUser() user: AuthedUser, @Param('deviceId') rawId: string) {
    await this.prisma.device.deleteMany({ where: { userId: user.id, deviceId: deviceIdParam(rawId) } });
  }
}
