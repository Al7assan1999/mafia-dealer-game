// Sprint 19 (1.2.0): the suggestions box (docs/sprint-19-prd.md, S19-1..S19-3, P1-P3), migration 0012.
import { describe, expect, it } from 'vitest';
import { DAY } from '../src/lib.ts';
import { setup } from './helpers.ts';
import { DB } from './live.ts';

const info = { app: '1.2.0', build: 100021, lang: 'ar', os: 'Android 14' };
const jpeg = (bytes = 64) => 'data:image/jpeg;base64,' + btoa(String.fromCharCode(0xff, 0xd8, 0xff) + ''.repeat(bytes));
const send = (t: Awaited<ReturnType<typeof setup>>, token: string, extra: Record<string, unknown> = {}) =>
  t.call('POST', '/v1/feedback', { token, body: { kind: 'idea', text: 'Please add a Medium role', info, ...extra } });

async function two() {
  const t = await setup(), admin = await t.user('Boss'), sami = await t.user('Sami');
  t.env.ADMIN_IDS = admin.id;
  return { t, admin, sami };
}

describe('sending (S19-1, P3)', () => {
  it('a suggestion with one screenshot: kept with the phone details; "My messages" shows it', async () => {
    const { t, sami } = await two();
    expect((await send(t, sami.token, { kind: 'problem', image: jpeg() })).status).toBe(200);
    const r = await t.call('GET', '/v1/feedback', { token: sami.token });
    expect(r.json.mine).toHaveLength(1);
    expect(r.json.mine[0]).toMatchObject({ kind: 'problem', text: 'Please add a Medium role', status: 'new', shot: true, info });
    expect(r.json.blocked).toBeNull();
  });

  it('signed out: refused; a text under 10 or over 1000 characters: refused', async () => {
    const { t, sami } = await two();
    expect((await t.call('POST', '/v1/feedback', { body: { kind: 'idea', text: 'Please add a Medium role', info } })).status).toBe(401);
    expect((await send(t, sami.token, { text: 'too short' })).status).toBe(400);
    expect((await send(t, sami.token, { text: 'x'.repeat(1001) })).status).toBe(400);
  });

  it('a screenshot that is not a picture, or over 300 KB: refused (S19-2 AC2)', async () => {
    const { t, sami } = await two();
    expect((await send(t, sami.token, { image: 'data:image/jpeg;base64,' + btoa('<script>alert(1)</script>') })).status).toBe(400);
    expect((await send(t, sami.token, { image: jpeg(300_001) })).json).toEqual({ error: 'too_big' });
    expect((await t.call('GET', '/v1/feedback', { token: sami.token })).json.mine).toEqual([]);
  });

  it('[Quin Q1, Q6, Q10] a 299 KB JPEG goes through the request limit; a PNG, a fake JPEG or broken base64 do not', async () => {
    const { t, sami } = await two();
    expect((await send(t, sami.token, { image: jpeg(299_000) })).status).toBe(200);
    expect((await send(t, sami.token, { image: 'data:image/png;base64,' + btoa('PNG-bytes') })).status).toBe(400);
    expect((await send(t, sami.token, { image: 'data:image/jpeg;base64,' + btoa('<html>not a picture</html>') })).status).toBe(400);
    expect((await send(t, sami.token, { image: 'data:image/jpeg;base64,A=A=' })).status).toBe(400);
  });

  it('a banned account cannot send (S19-2 AC4)', async () => {
    const { t, sami } = await two();
    await DB().prepare('UPDATE users SET banned_at = 1 WHERE id = ?').bind(sami.id).run();
    expect((await send(t, sami.token)).status).toBe(401);
  });

  it('P2: a game the sender played in can be attached; someone else\'s cannot', async () => {
    const { t, admin, sami } = await two();
    await DB().batch([
      DB().prepare("INSERT INTO games (id, host_id, winner, days, rules, log, stats, played_at) VALUES ('g1', ?, 'citizens', 1, '{}', '[]', '{}', 1)").bind(sami.id),
      DB().prepare("INSERT INTO game_players (game_id, seat, user_id, name, role, alive) VALUES ('g1', 0, ?, 'Sami', 'citizen', 1)").bind(sami.id),
    ]);
    expect((await send(t, admin.token, { gameId: 'g1' })).status).toBe(404);
    expect((await send(t, sami.token, { kind: 'problem', gameId: 'g1' })).status).toBe(200);
    // the admin can open that game, though he didn't play it
    expect((await t.call('GET', '/v1/games/g1', { token: admin.token })).status).toBe(200);
  });
});

describe('limits (S19-2)', () => {
  it('3 a day; the form knows before typing; a day later it opens again', async () => {
    const { t, sami } = await two();
    for (let i = 0; i < 3; i++) expect((await send(t, sami.token)).status).toBe(200);
    expect((await t.call('GET', '/v1/feedback', { token: sami.token })).json.blocked).toBe('day');
    expect((await send(t, sami.token)).json).toEqual({ error: 'slow_down' });
    t.clock.t += DAY + 1000;
    expect((await t.call('GET', '/v1/feedback', { token: sami.token })).json.blocked).toBeNull();
    expect((await send(t, sami.token)).status).toBe(200);
  });

  it('5 waiting at most; deleting them in the box frees the player again', async () => {
    const { t, admin, sami } = await two();
    for (let i = 0; i < 5; i++) { expect((await send(t, sami.token)).status).toBe(200); if (i === 2) t.clock.t += DAY + 1000; }
    t.clock.t += DAY + 1000;
    expect((await t.call('GET', '/v1/feedback', { token: sami.token })).json.blocked).toBe('waiting');
    expect((await send(t, sami.token)).status).toBe(429);
    // Empty takes what the admin saw: one that came in after stays
    const seen = (await t.call('GET', '/v1/admin/feedback', { token: admin.token })).json.items[0].at;
    await DB().prepare("INSERT INTO feedback (id, user_id, kind, text, info, created_at, updated_at) VALUES ('late', ?, 'idea', 'arrived after', '{}', ?, 1)").bind(admin.id, seen + 5).run();
    expect((await t.call('DELETE', '/v1/admin/feedback?upto=' + seen, { token: admin.token })).json).toEqual({ deleted: 5 });
    expect((await t.call('GET', '/v1/admin/feedback', { token: admin.token })).json.items.map((x: any) => x.id)).toEqual(['late']);
    expect((await t.call('GET', '/v1/feedback', { token: sami.token })).json.blocked).toBeNull();
  });

  it('the whole box holds 300: then "the box is full", and nothing is stored', async () => {
    const { t, admin, sami } = await two();
    await DB().batch(Array.from({ length: 300 }, (_, i) =>
      DB().prepare("INSERT INTO feedback (id, user_id, kind, text, info, created_at, updated_at) VALUES (?, ?, 'idea', 'filling the box', '{}', 1, 1)").bind('f' + i, admin.id)));
    expect((await t.call('GET', '/v1/feedback', { token: sami.token })).json.blocked).toBe('full');
    expect((await send(t, sami.token)).json).toEqual({ error: 'box_full' });
  });

  it('the database refuses an oversized screenshot even if the app were bypassed (migration 0012)', async () => {
    const { admin } = await two();
    await expect(DB().prepare("INSERT INTO feedback (id, user_id, kind, text, info, image, created_at, updated_at) VALUES ('x', ?, 'idea', 'a long enough text', '{}', ?, 1, 1)")
      .bind(admin.id, new Uint8Array(300_001)).run()).rejects.toThrow();
  });
});

describe('the box (S19-3, P1)', () => {
  it('only the admin lists, opens, marks and deletes', async () => {
    const { t, sami } = await two();
    await send(t, sami.token);
    const id = (await t.call('GET', '/v1/feedback', { token: sami.token })).json.mine[0].id;
    for (const [m, p] of [['GET', '/v1/admin/feedback'], ['GET', '/v1/admin/feedback/' + id], ['DELETE', '/v1/admin/feedback/' + id], ['DELETE', '/v1/admin/feedback']] as const) {
      expect((await t.call(m, p, { token: sami.token })).status, m + ' ' + p).toBe(403);
    }
    expect((await t.call('POST', '/v1/admin/feedback/' + id, { token: sami.token, body: { status: 'done' } })).status).toBe(403);
  });

  it('newest first with the sender; opening one shows the screenshot and marks it read; Done pushes the player', async () => {
    const { t, admin, sami } = await two();
    await t.call('PUT', '/v1/me/push', { token: sami.token, body: { token: 'tok-sami-0123456789abcdef', lang: 'ar' } });
    await send(t, sami.token, { kind: 'problem', image: jpeg(), text: 'The vote screen froze' });
    t.clock.t += 1000;
    await send(t, sami.token, { text: 'Add a Medium role please' });
    const box = (await t.call('GET', '/v1/admin/feedback', { token: admin.token })).json;
    expect(box.unread).toBe(2);
    expect(box.items.map((x: any) => x.text)).toEqual(['Add a Medium role please', 'The vote screen froze']);
    expect(box.items[1].from).toMatchObject({ handle: 'Sami' });
    const one = (await t.call('GET', '/v1/admin/feedback/' + box.items[1].id, { token: admin.token })).json;
    expect(one).toMatchObject({ status: 'read', shot: true, from: { handle: 'Sami' } });
    const pic = await t.call('GET', '/v1/admin/feedback/' + one.id + '/image', { token: admin.token });
    expect(pic.res.headers.get('content-type')).toBe('image/jpeg');
    expect([...new Uint8Array(await pic.res.arrayBuffer()).slice(0, 3)]).toEqual([0xff, 0xd8, 0xff]);
    expect((await t.call('GET', '/v1/admin/feedback/' + one.id + '/image', { token: sami.token })).status).toBe(403);
    expect((await t.call('GET', '/v1/admin/feedback', { token: admin.token })).json.unread).toBe(1);
    expect((await t.call('POST', '/v1/admin/feedback/' + one.id, { token: admin.token, body: { status: 'done' } })).status).toBe(200);
    expect(t.pushes.at(-1)).toMatchObject({ token: 'tok-sami-0123456789abcdef', body: 'اطّلعنا على المشكلة التي أبلغت عنها. شكرًا لك!', data: { kind: 'feedback_done', id: one.id } });
    expect((await t.call('GET', '/v1/feedback', { token: sami.token })).json.mine.find((x: any) => x.id === one.id).status).toBe('done');
    await t.call('POST', '/v1/admin/feedback/' + one.id, { token: admin.token, body: { status: 'done' } });
    expect(t.pushes.filter(p => p.data.kind === 'feedback_done')).toHaveLength(1);  // never twice
    expect((await t.call('DELETE', '/v1/admin/feedback/' + one.id, { token: admin.token })).status).toBe(200);
    expect((await t.call('GET', '/v1/admin/feedback/' + one.id, { token: admin.token })).status).toBe(404);
  });
});
