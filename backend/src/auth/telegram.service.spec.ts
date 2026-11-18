import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { exportJWK, generateKeyPair, SignJWT, type JWK } from 'jose';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { Env } from '../config/env';
import { TelegramLoginService } from './telegram.service';

const CLIENT_ID = '9114739181';
const APP_REDIRECT = 'https://app9114739181-login.tg.dev';
const API_BASE_URL = 'https://api.example.test';
const VERIFIER = 'v'.repeat(43);
const NONCE = 'nonce-nonce-nonce-1';

/** A local stand-in for oauth.telegram.org: JWKS, /token and /crossapp. */
let server: Server;
let issuer: string;
let privateKey: Awaited<ReturnType<typeof generateKeyPair>>["privateKey"];
let jwk: JWK;
let tokenNonce: string | undefined;
let crossappReply: { status: number; body: unknown };
let lastToken: URLSearchParams | undefined;
let lastCrossapp: URLSearchParams | undefined;

beforeAll(async () => {
  const pair = await generateKeyPair('RS256');
  privateKey = pair.privateKey;
  jwk = { ...(await exportJWK(pair.publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
  server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const json = (status: number, body: unknown) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    if (url.pathname === '/.well-known/jwks.json') return json(200, { keys: [jwk] });
    if (url.pathname === '/crossapp') {
      lastCrossapp = url.searchParams;
      return json(crossappReply.status, crossappReply.body);
    }
    if (url.pathname === '/token') {
      let raw = '';
      req.on('data', (chunk) => (raw += chunk));
      req.on('end', async () => {
        lastToken = new URLSearchParams(raw);
        const claims: Record<string, unknown> = { name: 'Kamola' };
        if (tokenNonce !== undefined) claims.nonce = tokenNonce;
        const idToken = await new SignJWT(claims)
          .setProtectedHeader({ alg: 'RS256', kid: 'k1' })
          .setIssuer(issuer)
          .setAudience(CLIENT_ID)
          .setSubject('tg-subject-1')
          .setIssuedAt()
          .setExpirationTime('5m')
          .sign(privateKey);
        json(200, { id_token: idToken });
      });
      return;
    }
    json(404, {});
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  issuer = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

afterAll(() => new Promise<void>((resolve) => server.close(() => resolve())));

beforeEach(() => {
  tokenNonce = NONCE;
  crossappReply = { status: 200, body: { url: 'tg://oauth?token=abc' } };
  lastToken = undefined;
  lastCrossapp = undefined;
});

function service(overrides: Partial<Env> = {}) {
  const env = {
    API_BASE_URL,
    TELEGRAM_LOGIN_CLIENT_ID: CLIENT_ID,
    TELEGRAM_LOGIN_CLIENT_SECRET: 'secret',
    TELEGRAM_OIDC_ISSUER: issuer,
    TELEGRAM_APP_REDIRECT_URI: APP_REDIRECT,
    APP_URL_SCHEME: 'nameshake',
    ...overrides,
  } as Env;
  return new TelegramLoginService(env);
}

const params = { codeChallenge: 'c'.repeat(43), state: 'state-state-state-1', nonce: NONCE };

describe('TelegramLoginService.appLink', () => {
  it('asks Telegram for a link that returns through the app redirect', async () => {
    await expect(service().appLink(params)).resolves.toBe('tg://oauth?token=abc');
    expect(lastCrossapp?.get('redirect_uri')).toBe(APP_REDIRECT);
    expect(lastCrossapp?.get('client_id')).toBe(CLIENT_ID);
    expect(lastCrossapp?.get('code_challenge')).toBe(params.codeChallenge);
    expect(lastCrossapp?.get('code_challenge_method')).toBe('S256');
    expect(lastCrossapp?.get('state')).toBe(params.state);
    expect(lastCrossapp?.get('nonce')).toBe(NONCE);
  });

  it('is null without an app redirect, so the app uses the browser', async () => {
    await expect(service({ TELEGRAM_APP_REDIRECT_URI: undefined }).appLink(params)).resolves.toBeNull();
    expect(lastCrossapp).toBeUndefined();
  });

  it('is null when Telegram refuses or answers with an unexpected link', async () => {
    crossappReply = { status: 400, body: { error: 'invalid_request' } };
    await expect(service().appLink(params)).resolves.toBeNull();
    crossappReply = { status: 200, body: { url: 'javascript:alert(1)' } };
    await expect(service().appLink(params)).resolves.toBeNull();
  });
});

describe('TelegramLoginService.signIn', () => {
  it('redeems a web-flow code against the backend callback', async () => {
    await expect(service().signIn('code', VERIFIER, NONCE)).resolves.toEqual({ subject: 'tg-subject-1', name: 'Kamola' });
    expect(lastToken?.get('redirect_uri')).toBe(`${API_BASE_URL}/v1/auth/telegram/callback`);
    expect(lastToken?.get('code_verifier')).toBe(VERIFIER);
  });

  it('redeems an app-flow code against the app redirect', async () => {
    await expect(service().signIn('code', VERIFIER, NONCE, 'app')).resolves.toMatchObject({ subject: 'tg-subject-1' });
    expect(lastToken?.get('redirect_uri')).toBe(APP_REDIRECT);
  });

  it('accepts an app-flow token without a nonce but never a different one', async () => {
    tokenNonce = undefined;
    await expect(service().signIn('code', VERIFIER, NONCE, 'app')).resolves.toMatchObject({ subject: 'tg-subject-1' });
    tokenNonce = 'someone-elses-nonce';
    await expect(service().signIn('code', VERIFIER, NONCE, 'app')).rejects.toMatchObject({ status: 401 });
  });

  it('requires the nonce on the web flow', async () => {
    tokenNonce = undefined;
    await expect(service().signIn('code', VERIFIER, NONCE)).rejects.toMatchObject({ status: 401 });
  });

  it('refuses the app flow when no app redirect is configured', async () => {
    await expect(service({ TELEGRAM_APP_REDIRECT_URI: undefined }).signIn('code', VERIFIER, NONCE, 'app')).rejects.toMatchObject({
      status: 503,
    });
    expect(lastToken).toBeUndefined();
  });
});
