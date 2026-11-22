// Mafia Dealer: Party Game, the Cloudflare Worker. REST API under /v1, plus two sockets:
// /v1/rooms/:code/ws (a live room, Room Durable Object) and /v1/hub/ws (presence + live notifications, Hub).
import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { cors } from 'hono/cors';
import { SUBPROTOCOL } from '@mafia/protocol';
import { auth, googleKeys, googleVerifier, lastCodes, requireUser, resendCode, sessions } from './auth.ts';
import { ApiErr, userFromToken, type AppEnv, type Ctx, type Deps, type Env } from './lib.ts';
import { games, invites, joinRequests, notes, rooms } from './social.ts';
import { avatars, friends, me, requests, users } from './users.ts';

export { Room } from './room.ts';
export { Hub } from './hub.ts';

/** Sockets can't send headers: the session token comes as the second subprotocol, ['mafia.v1', token]. */
async function socketUser(c: Ctx) {
  if (c.req.header('upgrade')?.toLowerCase() !== 'websocket') throw new ApiErr(400, 'bad_request');
  const [proto, tok] = (c.req.header('sec-websocket-protocol') || '').split(',').map(s => s.trim());
  const s = proto === SUBPROTOCOL && tok ? await userFromToken(c.env.DB, tok, c.var.deps.now()) : null;
  if (!s) throw new ApiErr(401, 'auth');
  return s.user;
}
function forward(c: Ctx, ns: DurableObjectNamespace, name: string, extra: Record<string, string>) {
  const h = new Headers(c.req.raw.headers);
  for (const [k, v] of Object.entries(extra)) h.set(k, v);
  return ns.get(ns.idFromName(name)).fetch(c.req.raw.url, { headers: h });
}

export function createApp(deps: Deps) {
  const app = new Hono<AppEnv>();
  app.use('*', async (c, next) => { c.set('deps', deps); await next(); });
  // bearer tokens, no cookies: any origin may call (the app runs from https://localhost inside Capacitor)
  app.use('/v1/*', cors({ origin: '*', allowHeaders: ['content-type', 'authorization'], allowMethods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'] }));
  app.use('/v1/*', bodyLimit({ maxSize: 300 * 1024, onError: c => c.json({ error: 'too_big' }, 413) }));

  app.get('/', c => c.text('mafia-dealer-game'));
  app.get('/v1/health', c => c.json({ ok: true }));
  // local test mode only (`wrangler dev --var MAIL_LOG:1`, never in wrangler.jsonc): the emulator test reads its code here
  app.get('/v1/test/last-code/:email', c => (c.env.MAIL_LOG === '1'
    ? c.json({ code: lastCodes.get(c.req.param('email').toLowerCase()) ?? null }) : c.json({ error: 'not_found' }, 404)));
  app.get('/v1/rooms/:code/ws', async c => {
    const code = c.req.param('code');
    if (!/^\d{6}$/.test(code)) throw new ApiErr(404, 'no_room');
    const u = await socketUser(c);
    return forward(c, c.env.ROOM, code, { 'x-user': JSON.stringify(u), 'x-code': code });
  });
  app.get('/v1/hub/ws', async c => {
    const u = await socketUser(c);
    return forward(c, c.env.HUB, u.id, { 'x-uid': u.id });
  });
  app.route('/v1/auth', auth);
  app.route('/v1/sessions', sessions);
  app.route('/v1/avatars', avatars);
  const routes = [['/v1/me', me], ['/v1/users', users], ['/v1/friends', friends], ['/v1/friend-requests', requests],
    ['/v1/rooms', rooms], ['/v1/invites', invites], ['/v1/join-requests', joinRequests], ['/v1/notifications', notes], ['/v1/games', games]] as const;
  for (const [path, r] of routes) { app.use(path, requireUser); app.use(path + '/*', requireUser); app.route(path, r); }

  app.notFound(c => c.json({ error: 'not_found' }, 404));
  app.onError((e, c) => {
    if (e instanceof ApiErr) return c.json({ error: e.code }, e.status);
    console.error(e);
    return c.json({ error: 'server' }, 500);
  });
  return app;
}

const app = createApp({ now: () => Date.now(), sendCode: resendCode, verifyGoogle: googleVerifier(googleKeys) });
export default { fetch: (req, env, ctx) => app.fetch(req, env, ctx) } satisfies ExportedHandler<Env>;
