import { isIP } from 'node:net';
import type { NextFunction, Request, Response } from 'express';
import { safeEqual } from './crypto';

export const EDGE_SECRET_HEADER = 'x-edge-secret';
export const EDGE_CLIENT_IP_HEADER = 'x-edge-client-ip';

/**
 * The public web origin (WEB_BASE_URL) can be served by an edge proxy (a Cloudflare Worker) that forwards
 * to this API. The platform proxy then sees the edge's IP, not the visitor's, so the edge sends the
 * visitor's IP in `x-edge-client-ip` together with a shared secret. Only a request carrying the secret
 * gets its IP replaced; every other request keeps the IP Express derives from `trust proxy`. Both
 * headers are removed before anything else (logging included) sees the request.
 */
export function edgeProxyClientIp(secret: string | undefined) {
  return (req: Request, _res: Response, next: NextFunction) => {
    const given = req.headers[EDGE_SECRET_HEADER];
    const ip = req.headers[EDGE_CLIENT_IP_HEADER];
    delete req.headers[EDGE_SECRET_HEADER];
    delete req.headers[EDGE_CLIENT_IP_HEADER];
    if (secret && typeof given === 'string' && typeof ip === 'string' && isIP(ip) && safeEqual(given, secret)) {
      Object.defineProperty(req, 'ip', { value: ip, configurable: true, enumerable: true });
    }
    next();
  };
}
