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
import { adminRoutes, blockRoutes, reportRoutes } from './safety.ts';
import { feedbackRoutes } from './feedback.ts';  // also adds the admin's /v1/admin/feedback
import { fcmSender, pushRoutes } from './push.ts';
import { expire, wifiRoutes } from './wifi.ts';
import { statsRoutes } from './stats.ts';
import { legacyRoutes, relayReader } from './legacy.ts';

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
  // [S19, Quin Q1] the suggestions box takes one screenshot of up to 300 KB, which is ~400 KB as base64 JSON
  const small = bodyLimit({ maxSize: 300 * 1024, onError: c => c.json({ error: 'too_big' }, 413) });
  const shot = bodyLimit({ maxSize: 420 * 1024, onError: c => c.json({ error: 'too_big' }, 413) });
  app.use('/v1/*', (c, next) => (c.req.path === '/v1/feedback' ? shot : small)(c, next));

  app.get('/', c => c.text('mafia-dealer-game'));
  app.get('/v1/health', c => c.json({ ok: true }));
  // The newest release for the app's update check, in GitHub's shape (tag_name, html_url, body, assets). The Release
  // workflow writes it; phones asked GitHub directly before, and GitHub allows 60 asks an hour per address (a VPN or a
  // mobile network shares one), so the check failed and the app said "latest version". 404 = not written yet.
  app.get('/v1/app/latest', async c => {
    const row = await c.env.DB.prepare("SELECT value FROM settings WHERE key = 'latest_release'").first<{ value: string }>();
    return row ? c.body(row.value, 200, { 'content-type': 'application/json', 'cache-control': 'public, max-age=60' }) : c.json({ error: 'not_found' }, 404);
  });
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
  const routes = [['/v1/me', me], ['/v1/me/push', pushRoutes], ['/v1/wifi-requests', wifiRoutes], ['/v1/stats', statsRoutes], ['/v1/legacy', legacyRoutes], ['/v1/users', users], ['/v1/friends', friends], ['/v1/friend-requests', requests],
    ['/v1/blocks', blockRoutes], ['/v1/reports', reportRoutes], ['/v1/feedback', feedbackRoutes], ['/v1/admin', adminRoutes],
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

const deps: Deps = { now: () => Date.now(), sendCode: resendCode, verifyGoogle: googleVerifier(googleKeys), push: fcmSender, readOldGroup: relayReader };
const app = createApp(deps);
export default {
  fetch: (req, env, ctx) => app.fetch(req, env, ctx),
  // hourly: Wi-Fi requests whose confirmation window ran out become 'expired', and their hosts are told
  scheduled: async (_e, env) => { await expire(env, deps, Date.now()); },
} satisfies ExportedHandler<Env>;
