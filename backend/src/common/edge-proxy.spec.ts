import express from 'express';
import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { clientIp } from './request';
import { EDGE_CLIENT_IP_HEADER, EDGE_SECRET_HEADER, edgeProxyClientIp } from './edge-proxy';

const SECRET = 'edge-secret-edge-secret-edge-secret-1234';

function app(secret: string | undefined) {
  const server = express();
  server.set('trust proxy', 1);
  server.use(edgeProxyClientIp(secret));
  server.get('/', (req, res) => {
    res.json({ ip: clientIp(req), leaked: Boolean(req.headers[EDGE_SECRET_HEADER] ?? req.headers[EDGE_CLIENT_IP_HEADER]) });
  });
  return server;
}

describe('edgeProxyClientIp', () => {
  it('uses the edge-supplied visitor IP when the secret matches', async () => {
    const res = await request(app(SECRET))
      .get('/')
      .set('x-forwarded-for', '104.16.0.1')
      .set(EDGE_SECRET_HEADER, SECRET)
      .set(EDGE_CLIENT_IP_HEADER, '203.0.113.7');
    expect(res.body).toEqual({ ip: '203.0.113.7', leaked: false });
  });

  it('ignores the visitor IP when the secret is wrong', async () => {
    const res = await request(app(SECRET))
      .get('/')
      .set('x-forwarded-for', '198.51.100.9')
      .set(EDGE_SECRET_HEADER, 'wrong')
      .set(EDGE_CLIENT_IP_HEADER, '203.0.113.7');
    expect(res.body).toEqual({ ip: '198.51.100.9', leaked: false });
  });

  it('ignores the headers when no secret is configured', async () => {
    const res = await request(app(undefined))
      .get('/')
      .set('x-forwarded-for', '198.51.100.9')
      .set(EDGE_SECRET_HEADER, '')
      .set(EDGE_CLIENT_IP_HEADER, '203.0.113.7');
    expect(res.body).toEqual({ ip: '198.51.100.9', leaked: false });
  });

  it('ignores a value that is not an IP address', async () => {
    const res = await request(app(SECRET))
      .get('/')
      .set('x-forwarded-for', '198.51.100.9')
      .set(EDGE_SECRET_HEADER, SECRET)
      .set(EDGE_CLIENT_IP_HEADER, 'not-an-ip');
    expect(res.body.ip).toBe('198.51.100.9');
  });
});
