// "Mafia Dealer X is out" to every phone that follows the updates topic (S8-4), in its language: updates_en / updates_ar.
// Run by the Release workflow: node scripts/push-release.mjs <version>, with FCM_SERVICE_ACCOUNT in the environment.
import { importPKCS8, SignJWT } from 'jose';

const version = process.argv[2];
const sa = JSON.parse(process.env.FCM_SERVICE_ACCOUNT ?? '{}');
if (!version || !sa.private_key) { console.error('usage: FCM_SERVICE_ACCOUNT=... node scripts/push-release.mjs <version>'); process.exit(1); }

const jwt = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' }).setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
  .setIssuer(sa.client_email).setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h')
  .sign(await importPKCS8(sa.private_key, 'RS256'));
const t = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }) });
if (!t.ok) { console.error('google auth', t.status); process.exit(1); }
const { access_token } = await t.json();

const texts = { en: `Mafia Dealer ${version} is out. Tap to update.`, ar: `صدر Mafia Dealer ${version}. اضغط للتحديث.` };
for (const [lang, body] of Object.entries(texts)) {
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST', headers: { authorization: 'Bearer ' + access_token, 'content-type': 'application/json' },
    body: JSON.stringify({ message: { topic: 'updates_' + lang, data: { kind: 'update', version },
      android: { priority: 'high', notification: { title: 'Mafia Dealer', body, channel_id: 'updates', tag: 'update' } } } }),
  });
  console.log(lang, r.status, r.ok ? 'sent' : await r.text());
  if (!r.ok) process.exitCode = 1;
}
