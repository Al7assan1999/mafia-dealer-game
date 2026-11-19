// Mafia Dealer: Party Game, the Cloudflare Worker. REST API under /v1 (live rooms come in phase 3).
import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { cors } from 'hono/cors';
import { auth, googleKeys, googleVerifier, requireUser, resendCode, sessions } from './auth.ts';
import { ApiErr, type AppEnv, type Deps, type Env } from './lib.ts';
import { avatars, friends, me, requests, users } from './users.ts';

export function createApp(deps: Deps) {
  const app = new Hono<AppEnv>();
  app.use('*', async (c, next) => { c.set('deps', deps); await next(); });
  // bearer tokens, no cookies: any origin may call (the app runs from https://localhost inside Capacitor)
  app.use('/v1/*', cors({ origin: '*', allowHeaders: ['content-type', 'authorization'], allowMethods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'] }));
  app.use('/v1/*', bodyLimit({ maxSize: 300 * 1024, onError: c => c.json({ error: 'too_big' }, 413) }));

  app.get('/', c => c.text('mafia-dealer-game'));
  app.get('/v1/health', c => c.json({ ok: true }));
  app.route('/v1/auth', auth);
  app.route('/v1/sessions', sessions);
  app.route('/v1/avatars', avatars);
  for (const [path, r] of [['/v1/me', me], ['/v1/users', users], ['/v1/friends', friends], ['/v1/friend-requests', requests]] as const) {
    app.use(path, requireUser); app.use(path + '/*', requireUser); app.route(path, r);
  }

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
