import { createServer, type Http2Server, type IncomingHttpHeaders } from 'node:http2';
import type { AddressInfo } from 'node:net';
import { decodeProtectedHeader, exportPKCS8, generateKeyPair, jwtVerify } from 'jose';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ApnsTransport } from './apns.transport';

describe('ApnsTransport', () => {
  let server: Http2Server;
  let base: string;
  let publicKey: Awaited<ReturnType<typeof generateKeyPair>>['publicKey'];
  let privatePem: string;
  const seen: { headers: IncomingHttpHeaders; body: string }[] = [];
  let respond: (headers: IncomingHttpHeaders) => { status: number; body?: unknown } = () => ({ status: 200 });

  beforeAll(async () => {
    const pair = await generateKeyPair('ES256', { extractable: true });
    publicKey = pair.publicKey;
    privatePem = await exportPKCS8(pair.privateKey);
    server = createServer((req, res) => {
      let body = '';
      req.setEncoding('utf8');
      req.on('data', (c: string) => (body += c));
      req.on('end', () => {
        seen.push({ headers: req.headers, body });
        const answer = respond(req.headers);
        res.writeHead(answer.status, { 'apns-id': 'x' });
        if (answer.body) res.end(JSON.stringify(answer.body));
        else res.end();
      });
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  afterAll(() => new Promise<void>((resolve) => server.close(() => resolve())));

  const transport = () => new ApnsTransport({ keyId: 'KEY123', teamId: 'TEAM456', privateKey: privatePem }, { sandbox: base, production: base });

  it('posts the payload over HTTP/2 with an ES256 provider token and APNs headers', async () => {
    seen.length = 0;
    const t = transport();
    const result = await t.send(
      {
        token: 'abcd',
        environment: 'sandbox',
        headers: { 'apns-topic': 'app.nameshake.ios', 'apns-push-type': 'alert', 'apns-priority': '10', 'apns-collapse-id': 'c1' },
        payload: { aps: { alert: { title: 'T', body: 'B' } }, type: 'followup_due' },
      },
      { userId: 'u', deviceId: 'd' },
    );
    expect(result).toEqual({ status: 200 });
    const req = seen[0]!;
    expect(req.headers[':method']).toBe('POST');
    expect(req.headers[':path']).toBe('/3/device/abcd');
    expect(req.headers['apns-topic']).toBe('app.nameshake.ios');
    expect(req.headers['apns-collapse-id']).toBe('c1');
    expect(JSON.parse(req.body)).toEqual({ aps: { alert: { title: 'T', body: 'B' } }, type: 'followup_due' });
    const jwt = String(req.headers.authorization).replace(/^bearer /, '');
    expect(decodeProtectedHeader(jwt)).toMatchObject({ alg: 'ES256', kid: 'KEY123' });
    const { payload } = await jwtVerify(jwt, publicKey);
    expect(payload.iss).toBe('TEAM456');
    // The token is cached between requests.
    await t.send({ token: 'abcd', environment: 'production', headers: seen[0]!.headers as never, payload: {} }, { userId: 'u', deviceId: 'd' });
    expect(seen[1]!.headers.authorization).toBe(req.headers.authorization);
    await t.close();
  });

  it('reports APNs errors with their reason and refreshes an expired provider token once', async () => {
    seen.length = 0;
    const t = transport();
    const headers = { 'apns-topic': 'app.nameshake.ios', 'apns-push-type': 'alert', 'apns-priority': '10' } as const;
    respond = () => ({ status: 410, body: { reason: 'Unregistered', timestamp: 1 } });
    expect(await t.send({ token: 'dead', environment: 'sandbox', headers, payload: {} }, { userId: 'u', deviceId: 'd' })).toEqual({
      status: 410,
      reason: 'Unregistered',
    });
    let calls = 0;
    respond = () => (++calls === 1 ? { status: 403, body: { reason: 'ExpiredProviderToken' } } : { status: 200 });
    expect(await t.send({ token: 'abcd', environment: 'sandbox', headers, payload: {} }, { userId: 'u', deviceId: 'd' })).toEqual({ status: 200 });
    expect(calls).toBe(2);
    respond = () => ({ status: 200 });
    await t.close();
  });
});
