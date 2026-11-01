import { randomBytes } from 'node:crypto';
import { Controller, Get, Inject, Param, Query, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { RateLimit } from '../common/rate-limit';
import { clientIp, Public } from '../common/request';
import { appDownloadUrl, ENV, type Env } from '../config/env';
import { pickLang } from '../i18n/lang';
import { DeferredLinksService } from './deferred-links.service';
import { renderCardPage, renderUnavailablePage, pageCsp } from './page';
import { PublicCardService } from './public-card.service';
import { buildVCard, vcardFilename } from './vcard';
import { isAndroidUserAgent, platformFromUserAgent } from './visitor';
import { WebStatsService } from './web-stats.service';

/** tanishly.app: the card page, its vCard, "Get the app" and the Apple app-site association. */
@Controller()
@Public()
export class WebController {
  constructor(
    private readonly cards: PublicCardService,
    private readonly stats: WebStatsService,
    private readonly deferred: DeferredLinksService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /** `/c/{slug}` (HTML) and `/c/{slug}.vcf` (vCard) — one route, Express matches both. */
  @Get('c/:slug')
  @RateLimit('publicCard')
  async page(@Param('slug') rawSlug: string, @Req() req: Request, @Res() res: Response) {
    if (/\.vcf$/i.test(rawSlug)) return this.vcard(rawSlug.slice(0, -4), req, res);
    const resolved = await this.cards.resolve(rawSlug);
    const nonce = randomBytes(16).toString('base64');
    // `?lang=` (uz | ru | en), then Accept-Language, then Uzbek.
    const lang = pickLang(req.query.lang, req.get('accept-language'));
    res.setHeader('Content-Security-Policy', pageCsp(nonce));
    res.vary('Accept-Language');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    res.type('html');
    if (resolved.status === 'available') {
      const userAgent = req.get('user-agent') ?? '';
      res.status(200).send(
        renderCardPage({
          view: this.cards.view(resolved),
          nonce,
          platform: platformFromUserAgent(userAgent),
          lang,
          appStoreId: this.env.APP_STORE_ID,
          appAvailable: appDownloadUrl(this.env) !== undefined,
          android: isAndroidUserAgent(userAgent),
          // The waitlist lives in the Telegram bot, so it shows only once the bot is connected.
          androidWaitlistUrl: this.env.TELEGRAM_BOT_TOKEN ? `https://t.me/${this.env.TELEGRAM_BOT_USERNAME}?start=android` : undefined,
        }),
      );
      return;
    }
    const status = resolved.status === 'paused' ? 200 : resolved.status === 'deleted' ? 410 : 404;
    res.status(status).send(renderUnavailablePage({ nonce, kind: resolved.status === 'unknown' ? 'notFound' : 'unavailable', lang }));
  }

  private async vcard(rawSlug: string, req: Request, res: Response) {
    const resolved = await this.cards.resolve(rawSlug);
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    if (resolved.status !== 'available') {
      res.status(404).type('text/plain; charset=utf-8').setHeader('Cache-Control', 'no-store');
      res.send('Not found');
      return;
    }
    const view = this.cards.view(resolved);
    const body = buildVCard({
      fullName: view.fullName,
      jobTitle: view.profile.jobTitle,
      company: view.profile.company,
      contacts: view.contacts,
      url: view.url,
      photoUrl: view.photoUrl,
    });
    await this.stats.record(view.card, { type: 'save' }, { ip: clientIp(req), userAgent: req.get('user-agent') ?? '' });
    const filename = vcardFilename(view.fullName, view.slug);
    res.status(200);
    res.setHeader('Content-Type', 'text/vcard; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Cache-Control', 'no-store');
    res.send(body);
  }

  /**
   * "Get the app": stores a deferred-link click (network prefix, user agent, locale, time zone — never
   * the full IP), counts a `get_app` event and redirects to the App Store (or the TestFlight link, or the site).
   * `?from=shareback` (the thank-you sheet) or `footer` becomes the App Store campaign token `ct`.
   */
  @Get('c/:slug/get-app')
  @RateLimit('analytics')
  async getApp(
    @Param('slug') rawSlug: string,
    @Query('tz') tz: string | undefined,
    @Query('lang') lang: string | undefined,
    @Query('from') from: string | undefined,
    @Req() req: Request,
    @Res() res: Response,
  ) {
    const resolved = await this.cards.resolve(rawSlug);
    const appStoreUrl = withCampaign(appDownloadUrl(this.env) ?? this.env.WEB_BASE_URL, from === 'shareback' ? 'shareback' : 'webcard');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    if (resolved.status === 'available') {
      const visitor = {
        ip: clientIp(req),
        userAgent: req.get('user-agent') ?? '',
        acceptLanguage: req.get('accept-language') ?? undefined,
        locale: typeof lang === 'string' ? lang : undefined,
        timeZone: typeof tz === 'string' ? tz : undefined,
      };
      await this.deferred.recordClick(resolved.card, visitor);
      await this.stats.record(resolved.card, { type: 'get_app' }, visitor);
    }
    res.redirect(302, appStoreUrl);
  }

  @Get('.well-known/apple-app-site-association')
  aasaWellKnown(@Res() res: Response) {
    this.aasa(res);
  }

  @Get('apple-app-site-association')
  aasaRoot(@Res() res: Response) {
    this.aasa(res);
  }

  /** Universal links for `/c/*` (except the `.vcf` and get-app routes) and shared web credentials. */
  private aasa(res: Response) {
    const team = this.env.APPLE_TEAM_ID;
    const appIDs = team ? this.env.APPLE_BUNDLE_IDS.map((bundleId) => `${team}.${bundleId}`) : [];
    const body = {
      applinks: {
        apps: [],
        details: appIDs.length
          ? [
              {
                appIDs,
                components: [
                  { '/': '/c/*.vcf', exclude: true, comment: 'vCard downloads stay in the browser' },
                  { '/': '/c/*/get-app', exclude: true, comment: 'App Store redirect' },
                  { '/': '/c/*', comment: 'Card pages' },
                ],
                paths: ['NOT /c/*.vcf', 'NOT /c/*/get-app', '/c/*'],
              },
            ]
          : [],
      },
      webcredentials: { apps: appIDs },
    };
    res.status(200).setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.send(JSON.stringify(body));
  }
}

/** Adds the App Store Connect campaign token; other destinations (TestFlight, the site) stay as they are. */
function withCampaign(url: string, campaign: string): string {
  if (!url.startsWith('https://apps.apple.com/')) return url;
  const target = new URL(url);
  target.searchParams.set('ct', campaign);
  return target.toString();
}
