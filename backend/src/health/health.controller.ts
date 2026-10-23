import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { NoRateLimit } from '../common/rate-limit';
import { Public } from '../common/request';
import { PrismaService } from '../prisma/prisma.service';

/** Liveness (process is up) and readiness (database answers) for the platform's probes. */
@Controller('health')
@Public()
@NoRateLimit()
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Get(['', 'live'])
  live() {
    return { status: 'ok' };
  }

  @Get('ready')
  async ready() {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return { status: 'ok' };
    } catch {
      throw new ServiceUnavailableException('database unavailable');
    }
  }
}
