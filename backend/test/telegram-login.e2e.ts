import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { exportJWK, generateKeyPair, type JWK, SignJWT } from 'jose';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { expectSchema } from './contract';
import { createApp, request, resetRateLimits } from './helpers';

const CLIENT_ID = '7654321';
const CLIENT_SECRET = 'test-client-secret';
const base64url = (buf: Buffer) => buf.toString('base64url');

/**
 * A stand-in for https://oauth.telegram.org: `/auth` approves at once (as if the user tapped
 * "Accept"), `/token` checks client auth + PKCE and returns a signed id_token, JWKS serves the key.
 */
async function startTelegramStandIn() {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  const jwk: JWK = { ...(await exportJWK(publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
  const codes = new Map<string, { challenge: string; nonce: string; redirectUri: string; sub: string }>();
  const state = { sub: '1234123412341234123', name: 'Kamola Yusupova' as string | undefined };
  let issuer = '';

  const server: Server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', issuer);
    if (req.method === 'GET' && url.pathname === '/.well-known/jwks.json') {
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ keys: [jwk] }));
      return;
    }
    if (req.method === 'GET' && url.pathname === '/auth') {
      const code = base64url(randomBytes(16));
      const q = url.searchParams;
      codes.set(code, { challenge: q.get('code_challenge') ?? '', nonce: q.get('nonce') ?? '', redirectUri: q.get('redirect_uri') ?? '', sub: state.sub });
      const back = new URL(q.get('redirect_uri') ?? '');
      back.search = new URLSearchParams({ code, state: q.get('state') ?? '' }).toString();
      res.writeHead(302, { location: back.toString() }).end();
      return;
    }
    if (req.method === 'POST' && url.pathname === '/token') {
      let raw = '';
      req.on('data', (chunk) => (raw += chunk));
      req.on('end', async () => {
        const form = new URLSearchParams(raw);
        const auth = Buffer.from((req.headers.authorization ?? '').replace(/^Basic /, ''), 'base64').toString();
        const grant = codes.get(form.get('code') ?? '');
        codes.delete(form.get('code') ?? '');
        const verifierOk = grant && base64url(createHash('sha256').update(form.get('code_verifier') ?? '').digest()) === grant.challenge;
        if (auth !== `${CLIENT_ID}:${CLIENT_SECRET}` || !grant || !verifierOk || form.get('redirect_uri') !== grant.redirectUri) {
          res.writeHead(400, { 'content-type': 'application/json' }).end(JSON.stringify({ error: 'invalid_grant' }));
          return;
        }
        const idToken = await new SignJWT({ id: 987654321, nonce: grant.nonce, ...(state.name ? { name: state.name } : {}), preferred_username: 'kamola' })
          .setProtectedHeader({ alg: 'RS256', kid: 'k1' })
          .setIssuer(issuer)
          .setAudience(CLIENT_ID)
          .setSubject(grant.sub)
          .setIssuedAt()
          .setExpirationTime('1h')
          .sign(privateKey);
        res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ access_token: 'x', token_type: 'Bearer', expires_in: 3600, id_token: idToken }));
      });
      return;
    }
    res.writeHead(404).end();
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  issuer = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return { issuer, server, state };
}

function pkce() {
  const verifier = base64url(randomBytes(32));
  return { verifier, challenge: base64url(createHash('sha256').update(verifier).digest()), state: base64url(randomBytes(16)), nonce: base64url(randomBytes(16)) };
}

describe('Log In with Telegram', () => {
  let app: NestExpressApplication;
  let standIn: Awaited<ReturnType<typeof startTelegramStandIn>>;
  const saved = { ...process.env };

  beforeAll(async () => {
    standIn = await startTelegramStandIn();
    process.env.TELEGRAM_LOGIN_CLIENT_ID = CLIENT_ID;
    process.env.TELEGRAM_LOGIN_CLIENT_SECRET = CLIENT_SECRET;
    process.env.TELEGRAM_OIDC_ISSUER = standIn.issuer;
    process.env.APP_URL_SCHEME = 'nameshake-test';
    app = await createApp();
  });
  afterAll(async () => {
    await app.close();
    standIn.server.close();
    process.env = saved;
  });
  beforeEach(() => resetRateLimits(app));

  const http = () => request(app.getHttpServer());

  /** Walks the browser part of the flow and returns the code the app receives. */
  async function authorize(p = pkce()) {
    const start = await http().get('/v1/auth/telegram/authorize').query({ code_challenge: p.challenge, state: p.state, nonce: p.nonce }).expect(302);
    const consent = await fetch(start.headers.location as string, { redirect: 'manual' });
    const callback = new URL(consent.headers.get('location') as string);
    const toApp = await http().get(callback.pathname + callback.search).expect(302);
    const appUrl = new URL(toApp.headers.location as string);
    return { p, start: new URL(start.headers.location as string), callback, appUrl, toApp };
  }

  it('redirects to Telegram with the registered redirect URI and PKCE', async () => {
    const { p, start, callback } = await authorize();
    expect(start.origin).toBe(standIn.issuer);
    expect(start.pathname).toBe('/auth');
    expect(Object.fromEntries(start.searchParams)).toEqual({
      client_id: CLIENT_ID,
      redirect_uri: 'https://api.metly.test/v1/auth/telegram/callback',
      response_type: 'code',
      scope: 'openid profile',
      state: p.state,
      nonce: p.nonce,
      code_challenge: p.challenge,
      code_challenge_method: 'S256',
    });
    expect(callback.toString().startsWith('https://api.metly.test/v1/auth/telegram/callback?')).toBe(true);
  });

  it('hands code and state back to the app, then signs in and finds the same account again', async () => {
    const { p, appUrl, toApp } = await authorize();
    expect(appUrl.protocol).toBe('nameshake-test:');
    expect(appUrl.host + appUrl.pathname).toBe('auth/telegram');
    expect(appUrl.searchParams.get('state')).toBe(p.state);
    expect(toApp.headers['cache-control']).toBe('no-store');

    const first = await http()
      .post('/v1/auth/telegram')
      .send({ code: appUrl.searchParams.get('code'), codeVerifier: p.verifier, nonce: p.nonce })
      .expect(200);
    expectSchema('AuthResponse', first.body);
    expect(first.body.isNewUser).toBe(true);
    expect(first.body.suggestedName).toBe('Kamola Yusupova');
    expect(first.body.user.authProviders).toEqual(['telegram']);
    expect(first.body.user).not.toHaveProperty('email');

    const again = await authorize();
    const second = await http()
      .post('/v1/auth/telegram')
      .send({ code: again.appUrl.searchParams.get('code'), codeVerifier: again.p.verifier, nonce: again.p.nonce })
      .expect(200);
    expect(second.body.isNewUser).toBe(false);
    expect(second.body.user.id).toBe(first.body.user.id);
  });

  it('refuses a wrong PKCE verifier, a reused code and a mismatched nonce', async () => {
    const wrongVerifier = await authorize();
    await http()
      .post('/v1/auth/telegram')
      .send({ code: wrongVerifier.appUrl.searchParams.get('code'), codeVerifier: pkce().verifier, nonce: wrongVerifier.p.nonce })
      .expect(401);

    const ok = await authorize();
    const body = { code: ok.appUrl.searchParams.get('code'), codeVerifier: ok.p.verifier, nonce: ok.p.nonce };
    await http().post('/v1/auth/telegram').send(body).expect(200);
    await http().post('/v1/auth/telegram').send(body).expect(401);

    const nonce = await authorize();
    const res = await http()
      .post('/v1/auth/telegram')
      .send({ code: nonce.appUrl.searchParams.get('code'), codeVerifier: nonce.p.verifier, nonce: pkce().nonce })
      .expect(401);
    expect(res.body.message).toMatch(/nonce/);
  });

  it('keys accounts by Telegram subject and works without a display name', async () => {
    standIn.state.sub = `sub-${randomUUID()}`;
    standIn.state.name = undefined;
    const { p, appUrl } = await authorize();
    const res = await http()
      .post('/v1/auth/telegram')
      .send({ code: appUrl.searchParams.get('code'), codeVerifier: p.verifier, nonce: p.nonce })
      .expect(200);
    expect(res.body.isNewUser).toBe(true);
    expect(res.body).not.toHaveProperty('suggestedName');
  });

  it('passes a cancelled consent back to the app as an error', async () => {
    const res = await http().get('/v1/auth/telegram/callback').query({ error: 'access_denied', state: 'abcdefghijklmnop' }).expect(302);
    const appUrl = new URL(res.headers.location as string);
    expect(Object.fromEntries(appUrl.searchParams)).toEqual({ error: 'access_denied', state: 'abcdefghijklmnop' });
  });

  it('validates the authorize parameters', async () => {
    await http().get('/v1/auth/telegram/authorize').query({ code_challenge: 'short', state: 'abcdefghijklmnop', nonce: 'abcdefghijklmnop' }).expect(422);
    await http().post('/v1/auth/telegram').send({ code: 'x', codeVerifier: 'short', nonce: 'abcdefghijklmnop' }).expect(422);
  });
});

describe('Log In with Telegram (not configured)', () => {
  let app: NestExpressApplication;
  beforeAll(async () => {
    delete process.env.TELEGRAM_LOGIN_CLIENT_ID;
    delete process.env.TELEGRAM_LOGIN_CLIENT_SECRET;
    app = await createApp();
  });
  afterAll(() => app.close());

  it('sends the app sheet back with temporarily_unavailable, and refuses codes with 503', async () => {
    const p = pkce();
    const res = await request(app.getHttpServer()).get('/v1/auth/telegram/authorize').query({ code_challenge: p.challenge, state: p.state, nonce: p.nonce }).expect(302);
    const appUrl = new URL(res.headers.location as string);
    expect(appUrl.host + appUrl.pathname).toBe('auth/telegram');
    expect(Object.fromEntries(appUrl.searchParams)).toEqual({ error: 'temporarily_unavailable', state: p.state });
    await request(app.getHttpServer()).post('/v1/auth/telegram').send({ code: 'abc', codeVerifier: p.verifier, nonce: p.nonce }).expect(503);
  });
});
