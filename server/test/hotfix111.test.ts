// 1.1.1 hotfix: the friends box only searches now (no add by typed @handle), so an exact @handle comes first and never
// falls past the 20 results.
import { describe, expect, it } from 'vitest';
import { setup } from './helpers.ts';
import { DB } from './live.ts';

describe('search: an exact @handle first (1.1.1)', () => {
  it('with more than 20 handles starting the same way, @moh is the first result', async () => {
    const t = await setup(), me = await t.user('Sami');
    await DB().batch([...Array.from({ length: 22 }, (_, i) => 'moh' + String.fromCharCode(97 + i) + 'x'), 'moh'].map((h, i) =>
      DB().prepare('INSERT INTO users (id, handle, display, created_at) VALUES (?, ?, ?, 1)').bind('m' + i, h, h === 'moh' ? 'Zz last by name' : 'A' + h)));
    const r = await t.call('GET', '/v1/users?q=MOH', { token: me.token });
    expect(r.json.users).toHaveLength(20);
    expect(r.json.users[0].handle).toBe('moh');
  });
});
