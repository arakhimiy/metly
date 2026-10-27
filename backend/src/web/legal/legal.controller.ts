import { Controller, Get, Inject, Query, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { Public } from '../../common/request';
import { appDownloadUrl, ENV, type Env } from '../../config/env';
import type { LegalDocKind } from './legal-content';
import { pickLang, renderHomePage, renderLegalPage, STATIC_PAGE_CSP } from './legal-page';

/** tanishly.app home, Privacy Policy, Terms of Use and Help (the App Store's Support URL). */
@Controller()
@Public()
export class LegalController {
  constructor(@Inject(ENV) private readonly env: Env) {}

  @Get()
  home(@Query('lang') lang: unknown, @Req() req: Request, @Res() res: Response) {
    const url = appDownloadUrl(this.env);
    const download = url ? { url, beta: !this.env.APP_STORE_ID } : undefined;
    this.send(res, renderHomePage(pickLang(lang, req.get('accept-language')), download));
  }

  @Get('privacy')
  privacy(@Query('lang') lang: unknown, @Req() req: Request, @Res() res: Response) {
    this.doc('privacy', lang, req, res);
  }

  @Get('terms')
  terms(@Query('lang') lang: unknown, @Req() req: Request, @Res() res: Response) {
    this.doc('terms', lang, req, res);
  }

  @Get(['help', 'support'])
  help(@Query('lang') lang: unknown, @Req() req: Request, @Res() res: Response) {
    this.doc('help', lang, req, res);
  }

  private doc(kind: LegalDocKind, lang: unknown, req: Request, res: Response) {
    this.send(res, renderLegalPage(kind, pickLang(lang, req.get('accept-language'))));
  }

  private send(res: Response, body: string) {
    res.setHeader('Content-Security-Policy', STATIC_PAGE_CSP);
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.setHeader('Vary', 'Accept-Language');
    res.type('html').status(200).send(body);
  }
}
