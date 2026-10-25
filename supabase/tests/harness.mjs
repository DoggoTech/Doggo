// Entorno de pruebas del esquema: Postgres real (PGlite) con lo mínimo de
// Supabase simulado (roles, auth.uid(), storage y la publicación de realtime).
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const sql = (name) => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8');

const SUPABASE_STUBS = `
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;

  create schema auth;
  create table auth.users (
    instance_id uuid, id uuid primary key, aud text, role text,
    email text unique, encrypted_password text, email_confirmed_at timestamptz,
    raw_app_meta_data jsonb default '{}', raw_user_meta_data jsonb default '{}',
    created_at timestamptz default now(), updated_at timestamptz default now(),
    confirmation_token text default '', recovery_token text default '',
    email_change text default '', email_change_token_new text default ''
  );
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid
  $$;
  grant usage on schema auth to anon, authenticated;

  create schema storage;
  create table storage.buckets (
    id text primary key, name text, public boolean,
    file_size_limit bigint, allowed_mime_types text[]
  );
  create table storage.objects (
    id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid
  );
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
  $$;

  create publication supabase_realtime;

  -- Supabase concede ALL por defecto: se replica para comprobar que el esquema
  -- lo revoca y deja solo lo necesario.
  alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
  grant usage on schema public to anon, authenticated, service_role;
`;

export async function createDb({ seed = true } = {}) {
  const db = new PGlite();
  await db.exec(SUPABASE_STUBS);
  await db.exec(sql('schema.sql'));
  if (seed) await db.exec(sql('seed.sql'));
  return db;
}

export const IDS = {
  laura: 'a1000000-0000-4000-8000-000000000001', // cuidadora aprobada y verificada (Chapinero)
  andres: 'a1000000-0000-4000-8000-000000000002',
  natalia: 'a1000000-0000-4000-8000-000000000011', // cuidadora en revisión
  ricardo: 'a1000000-0000-4000-8000-000000000012', // cuidador en revisión
  marcela: 'a2000000-0000-4000-8000-000000000001', // dueña de ejemplo
  rocky: 'd1000000-0000-4000-8000-000000000001',
  bookingLaura: 'b1000000-0000-4000-8000-000000000001', // completada
};

/**
 * Ejecuta `fn` dentro de una transacción que siempre se revierte, para que cada
 * prueba parta del mismo estado. Devuelve helpers para actuar como cada rol.
 */
export async function inTx(db, fn) {
  await db.exec('begin');
  try {
    return await fn(helpers(db));
  } finally {
    await db.exec('rollback');
  }
}

function helpers(db) {
  const q = async (text, params) => (await db.query(text, params)).rows;

  /** Como un cliente de la API: rol `authenticated` (o `anon`) con su JWT. */
  const as = async (userId, fn) => {
    const role = userId ? 'authenticated' : 'anon';
    const claims = userId ? { sub: userId, role } : { role };
    await db.exec(`set local role ${role}`);
    await db.query(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(claims)]);
    try {
      return await fn();
    } finally {
      await db.exec('reset role');
      await db.query(`select set_config('request.jwt.claims', '', true)`);
    }
  };

  /** Ejecuta una sentencia que debe fallar; devuelve el error y deja la transacción usable. */
  const fails = async (text, params) => {
    await db.exec('savepoint t');
    try {
      await db.query(text, params);
      await db.exec('release savepoint t');
      return null;
    } catch (e) {
      await db.exec('rollback to savepoint t');
      await db.exec('release savepoint t');
      return e;
    }
  };

  /** Crea un usuario de Auth como lo haría la app al registrarse. */
  const signUp = async (email, meta) => {
    const id = (await q('select gen_random_uuid() as id'))[0].id;
    await q(
      `insert into auth.users (id, email, raw_user_meta_data) values ($1, $2, $3::jsonb)`,
      [id, email, JSON.stringify(meta ?? {})],
    );
    return id;
  };

  /** Como el SQL Editor / assign_roles.sql: rol privilegiado. */
  const setRole = (id, role, status = 'approved') =>
    q(`update profiles set role = $2, status = $3 where id = $1`, [id, role, status]);

  return { q, as, fails, signUp, setRole };
}
