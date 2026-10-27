import type { PrismaService } from '../prisma/prisma.service';
import { DEFAULT_LANG, type Lang, langFromLocale } from './lang';

/**
 * A user's language when the text is not tied to one device (Telegram bot, synced record text): the
 * locale of their most recently registered device, Uzbek without one.
 */
export async function userLang(prisma: PrismaService, userId: string): Promise<Lang> {
  const device = await prisma.device.findFirst({ where: { userId }, orderBy: { updatedAt: 'desc' }, select: { locale: true } });
  return device ? langFromLocale(device.locale) : DEFAULT_LANG;
}
