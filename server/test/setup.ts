import { applyD1Migrations, env } from 'cloudflare:test';

// the real migrations, applied to the test database before each test file
await applyD1Migrations((env as any).DB, (env as any).TEST_MIGRATIONS);
