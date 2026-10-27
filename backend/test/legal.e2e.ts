import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createApp, request } from './helpers';

describe('legal pages (App Store Privacy Policy and Support URLs)', () => {
  let app: NestExpressApplication;
  beforeAll(async () => {
    app = await createApp();
  });
  afterAll(() => app.close());

  it('serves the privacy policy in Uzbek by default, without scripts', async () => {
    const res = await request(app.getHttpServer()).get('/privacy').expect(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.headers['content-security-policy']).toContain("default-src 'none'");
    expect(res.text).toContain('Maxfiylik siyosati');
  });

  it('follows ?lang= and Accept-Language', async () => {
    const ru = await request(app.getHttpServer()).get('/terms?lang=ru').expect(200);
    expect(ru.text).toContain('Условия использования');
    const en = await request(app.getHttpServer()).get('/help').set('Accept-Language', 'en-GB,en;q=0.9').expect(200);
    expect(en.text).toContain('How do I share my card?');
  });

  it('serves /support as the help page and a home page at /', async () => {
    const support = await request(app.getHttpServer()).get('/support?lang=en').expect(200);
    expect(support.text).toContain('<h1>Help</h1>');
    const home = await request(app.getHttpServer()).get('/?lang=en').expect(200);
    expect(home.text).toContain('Coming soon to the App Store');
  });
});
