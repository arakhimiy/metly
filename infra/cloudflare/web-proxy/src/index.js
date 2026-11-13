/**
 * Serves the public web origin (nameshake.app: card pages, legal pages, apple-app-site-association) by
 * proxying every request to the API, which renders them. The URL stays on nameshake.app, so printed QR
 * codes and Universal Links keep working; www.nameshake.app redirects to the apex.
 *
 * The API sees this Worker's IP, so the visitor's IP travels in `x-edge-client-ip`, trusted by the API
 * only together with the shared EDGE_PROXY_SECRET (backend/src/common/edge-proxy.ts).
 */
export default {
  async fetch(request, env) {
    const incoming = new URL(request.url);

    if (incoming.hostname.startsWith('www.')) {
      incoming.hostname = incoming.hostname.slice(4);
      return Response.redirect(incoming.toString(), 301);
    }

    const target = new URL(incoming.pathname + incoming.search, env.ORIGIN);
    const headers = new Headers(request.headers);
    headers.delete('x-edge-secret');
    headers.delete('x-edge-client-ip');
    const visitorIp = request.headers.get('cf-connecting-ip');
    if (env.EDGE_PROXY_SECRET && visitorIp) {
      headers.set('x-edge-secret', env.EDGE_PROXY_SECRET);
      headers.set('x-edge-client-ip', visitorIp);
    }
    headers.set('x-forwarded-host', incoming.host);
    headers.set('x-forwarded-proto', 'https');

    return fetch(target, {
      method: request.method,
      headers,
      body: request.method === 'GET' || request.method === 'HEAD' ? undefined : request.body,
      redirect: 'manual',
    });
  },
};
