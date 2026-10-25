// Levanta la base de Doggo (schema.sql + seed.sql) en tu máquina para
// explorarla con psql o una app visual (TablePlus, DBeaver, Postico...).
// Es Postgres real (PGlite) en memoria: se reinicia limpia cada vez.
//
//   npm run db:serve
//   psql "postgresql://postgres@127.0.0.1:5433/postgres"
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import { createDb } from './tests/harness.mjs';

const PORT = Number(process.env.DB_PORT ?? 5433);

const db = await createDb();
const server = new PGLiteSocketServer({ db, port: PORT, host: '127.0.0.1' });
await server.start();

console.log(`
Base de Doggo lista (schema.sql + seed.sql cargados).

  Conexión:  postgresql://postgres@127.0.0.1:${PORT}/postgres
  Terminal:  psql "postgresql://postgres@127.0.0.1:${PORT}/postgres"
  App visual: host 127.0.0.1 · puerto ${PORT} · usuario postgres · base postgres · sin contraseña · SSL desactivado

Ctrl+C para apagarla. Los cambios que hagas se pierden al apagarla.
`);

process.on('SIGINT', async () => {
  await server.stop();
  await db.close();
  process.exit(0);
});
