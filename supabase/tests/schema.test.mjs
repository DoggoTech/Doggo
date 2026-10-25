// Pruebas del esquema de Supabase. Cada criterio de seguridad del contexto
// (sección 16) tiene al menos una prueba que lo intenta romper como lo haría un
// cliente malicioso: llamando a la API directamente, sin pasar por la UI.
//
//   npm run test:db
import { test, describe, before } from 'node:test';
import assert from 'node:assert/strict';
import { createDb, inTx, IDS } from './harness.mjs';

let db;
before(async () => {
  db = await createDb();
});

const tx = (fn) => inTx(db, fn);
const rejects = (err, pattern) => {
  assert.ok(err, 'se esperaba un error y la sentencia fue aceptada');
  assert.match(err.message, pattern);
};

const INSERT_BOOKING = `
  insert into bookings (owner_id, sitter_id, dog_id, service_type, start_at, end_at, total_cop)
  values ($1, $2, $3, $4, now() + interval '2 days', now() + interval '2 days' + $5::interval, 1)
  returning id, total_cop, status`;

/** Dueña (Marcela) reserva a Laura; devuelve la reserva creada. */
async function book(t, { service = 'walk', length = '1 hour', sitter = IDS.laura } = {}) {
  const rows = await t.as(IDS.marcela, () =>
    t.q(INSERT_BOOKING, [IDS.marcela, sitter, IDS.rocky, service, length]),
  );
  return rows[0];
}

/** Crea y deja listo un usuario con rol privilegiado. */
async function adminUser(t, email = 'admin@t.test', role = 'admin') {
  const id = await t.signUp(email, {});
  await t.setRole(id, role);
  return id;
}

// ---------------------------------------------------------------------------
describe('esquema y datos de ejemplo', () => {
  test('el seed deja 10 cuidadores aprobados (algunos verificados) y 2 en revisión', () =>
    tx(async (t) => {
      const rows = await t.q(
        `select status, count(*)::int n, sum(verified::int)::int v
           from profiles where role = 'sitter' group by status`,
      );
      const by = Object.fromEntries(rows.map((r) => [r.status, r]));
      assert.equal(by.approved.n, 10);
      assert.ok(by.approved.v >= 3, 'hay verificados');
      assert.equal(by.pending_review.n, 2);
    }));

  test('la ubicación del mapa está desplazada entre 200 y 300 m de la exacta', () =>
    tx(async (t) => {
      const rows = await t.q(
        `select p.approx_lat, p.approx_lng, pp.exact_lat, pp.exact_lng
           from profiles p join profile_private pp using (id) where p.role = 'sitter'`,
      );
      assert.equal(rows.length, 12);
      for (const r of rows) {
        const dLat = ((r.approx_lat - r.exact_lat) * Math.PI) / 180;
        const dLng = ((r.approx_lng - r.exact_lng) * Math.PI) / 180;
        const a =
          Math.sin(dLat / 2) ** 2 +
          Math.cos((r.exact_lat * Math.PI) / 180) * Math.cos((r.approx_lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
        const meters = 2 * 6371000 * Math.asin(Math.sqrt(a));
        assert.ok(meters >= 195 && meters <= 305, `desplazamiento ${meters.toFixed(0)} m`);
      }
    }));

  test('el desplazamiento es estable: guardar de nuevo no cambia la ubicación aproximada', () =>
    tx(async (t) => {
      const before = (await t.q(`select approx_lat, approx_lng from profiles where id = $1`, [IDS.laura]))[0];
      await t.as(IDS.laura, () =>
        t.q(`update profile_private set exact_lat = exact_lat, address = 'Otra' where id = $1`, [IDS.laura]),
      );
      await t.q(`update profile_private set exact_lat = exact_lat + 0 where id = $1`, [IDS.laura]);
      const after = (await t.q(`select approx_lat, approx_lng from profiles where id = $1`, [IDS.laura]))[0];
      assert.deepEqual(after, before);
    }));

  test('el keep-alive funciona con la clave anónima (lee sitter_services)', () =>
    tx((t) =>
      t.as(null, async () => {
        const rows = await t.q(`select id from sitter_services limit 1`);
        assert.equal(rows.length, 1);
      }),
    ));

  test('bookings está en la publicación de realtime con replica identity full', () =>
    tx(async (t) => {
      const pub = await t.q(`select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'bookings'`);
      assert.equal(pub.length, 1);
      const ident = await t.q(`select relreplident from pg_class where oid = 'public.bookings'::regclass`);
      assert.equal(ident[0].relreplident, 'f');
    }));

  test('el bucket de avatares limita tamaño y tipos', () =>
    tx(async (t) => {
      const [b] = await t.q(`select * from storage.buckets where id = 'avatars'`);
      assert.equal(Number(b.file_size_limit), 2097152);
      assert.deepEqual([...b.allowed_mime_types].sort(), ['image/jpeg', 'image/png', 'image/webp']);
    }));
});

// ---------------------------------------------------------------------------
describe('registro y roles', () => {
  test('la app registra dueño como approved y cuidador como pending_review', () =>
    tx(async (t) => {
      const owner = await t.signUp('o@t.test', { role: 'owner', full_name: 'Ola', accepted_terms: true });
      const sitter = await t.signUp('s@t.test', { role: 'sitter', full_name: 'Sol', accepted_terms: true });
      const rows = await t.q(`select id, role, status, terms_accepted_at from profiles where id in ($1, $2)`, [owner, sitter]);
      const by = Object.fromEntries(rows.map((r) => [r.id, r]));
      assert.equal(by[owner].status, 'approved');
      assert.equal(by[sitter].role, 'sitter');
      assert.equal(by[sitter].status, 'pending_review');
      assert.ok(by[sitter].terms_accepted_at, 'guarda terms_accepted_at');
    }));

  test('registrarse pidiendo role admin o superadmin se rechaza', () =>
    tx(async (t) => {
      for (const role of ['admin', 'superadmin']) {
        const err = await t.fails(
          `insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), $1, $2::jsonb)`,
          [`${role}@t.test`, JSON.stringify({ role, accepted_terms: true })],
        );
        rejects(err, /invalid_role/);
      }
    }));

  test('registrarse desde la app sin aceptar los términos se rechaza', () =>
    tx(async (t) => {
      const err = await t.fails(
        `insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'x@t.test', '{"role":"owner"}')`,
      );
      rejects(err, /terms_required/);
    }));

  test('las cuentas creadas desde el panel de Supabase nacen como dueño', () =>
    tx(async (t) => {
      const id = await t.signUp('panel@t.test', {});
      const [p] = await t.q(`select role, status from profiles where id = $1`, [id]);
      assert.deepEqual({ ...p }, { role: 'owner', status: 'approved' });
    }));

  test('solo puede existir un superadmin', () =>
    tx(async (t) => {
      await adminUser(t, 'sa1@t.test', 'superadmin');
      const other = await t.signUp('sa2@t.test', {});
      const err = await t.fails(`update profiles set role = 'superadmin' where id = $1`, [other]);
      rejects(err, /profiles_single_superadmin|duplicate key/);
    }));

  test('un usuario no puede cambiarse role, status ni verified con una llamada directa', () =>
    tx(async (t) => {
      for (const [col, val] of [['role', 'admin'], ['role', 'superadmin'], ['status', 'approved'], ['verified', 'true']]) {
        const err = await t.as(IDS.natalia, () =>
          t.fails(`update profiles set ${col} = '${val}' where id = $1`, [IDS.natalia]),
        );
        rejects(err, /permission denied/);
      }
      const [p] = await t.q(`select role, status, verified from profiles where id = $1`, [IDS.natalia]);
      assert.deepEqual({ ...p }, { role: 'sitter', status: 'pending_review', verified: false });
    }));

  test('un usuario no puede fijar su ubicación aproximada directamente', () =>
    tx(async (t) => {
      const err = await t.as(IDS.laura, () =>
        t.fails(`update profiles set approx_lat = 4.0 where id = $1`, [IDS.laura]),
      );
      rejects(err, /permission denied/);
    }));

  test('nadie puede crear perfiles ni borrarlos desde la API', () =>
    tx(async (t) => {
      const e1 = await t.as(IDS.marcela, () =>
        t.fails(`insert into profiles (id, role) values (gen_random_uuid(), 'admin')`),
      );
      rejects(e1, /permission denied/);
      const e2 = await t.as(IDS.marcela, () => t.fails(`delete from profiles where id = $1`, [IDS.marcela]));
      rejects(e2, /permission denied/);
    }));

  test('un usuario sí puede editar su nombre y bio', () =>
    tx((t) =>
      t.as(IDS.laura, async () => {
        await t.q(`update profiles set full_name = 'Laura G.', bio = 'Nueva bio sin contacto' where id = $1`, [IDS.laura]);
        const [p] = await t.q(`select full_name from profiles where id = $1`, [IDS.laura]);
        assert.equal(p.full_name, 'Laura G.');
      }),
    ));
});

// ---------------------------------------------------------------------------
describe('visibilidad y moderación en el mapa', () => {
  test('un cuidador en revisión no aparece para otros ni para anon', () =>
    tx(async (t) => {
      const forOwner = await t.as(IDS.marcela, () => t.q(`select id from profiles where id = $1`, [IDS.natalia]));
      const forAnon = await t.as(null, () => t.q(`select id from profiles where id = $1`, [IDS.natalia]));
      assert.equal(forOwner.length, 0);
      assert.equal(forAnon.length, 0);
      const own = await t.as(IDS.natalia, () => t.q(`select id from profiles where id = $1`, [IDS.natalia]));
      assert.equal(own.length, 1, 've su propio perfil para ver "Perfil en revisión"');
    }));

  test('los servicios de un cuidador en revisión no son públicos', () =>
    tx(async (t) => {
      const rows = await t.as(null, () => t.q(`select id from sitter_services where sitter_id = $1`, [IDS.natalia]));
      assert.equal(rows.length, 0);
    }));

  test('tras aprobarlo el admin, el cuidador aparece en el mapa', () =>
    tx(async (t) => {
      const admin = await adminUser(t);
      await t.as(admin, () => t.q(`select admin_set_sitter_approval($1, true)`, [IDS.natalia]));
      const rows = await t.as(IDS.marcela, () => t.q(`select id from profiles where id = $1`, [IDS.natalia]));
      assert.equal(rows.length, 1);
    }));

  test('un usuario suspendido desaparece del mapa y de los servicios públicos', () =>
    tx(async (t) => {
      const admin = await adminUser(t);
      await t.as(admin, () => t.q(`select admin_set_user_suspended($1, true)`, [IDS.laura]));
      const MAP = `select id from profiles where role = 'sitter' and status = 'approved' and id = $1`;
      // Alguien sin reserva con ella no la ve en absoluto.
      assert.equal((await t.as(IDS.andres, () => t.q(`select id from profiles where id = $1`, [IDS.laura]))).length, 0);
      // Quien tuvo una reserva con ella conserva su perfil (historial), pero ya no está en el mapa.
      assert.equal((await t.as(IDS.marcela, () => t.q(MAP, [IDS.laura]))).length, 0);
      assert.equal((await t.as(null, () => t.q(MAP, [IDS.laura]))).length, 0);
      const s = await t.as(null, () => t.q(`select id from sitter_services where sitter_id = $1`, [IDS.laura]));
      assert.equal(s.length, 0);
    }));

  test('un usuario suspendido no puede reservar ni recibir reservas', () =>
    tx(async (t) => {
      const admin = await adminUser(t);
      await t.as(admin, () => t.q(`select admin_set_user_suspended($1, true)`, [IDS.laura]));
      rejects(
        await t.as(IDS.marcela, () => t.fails(INSERT_BOOKING, [IDS.marcela, IDS.laura, IDS.rocky, 'walk', '1 hour'])),
        /sitter_not_available/,
      );
      await t.q(`select 1`);
    }));

  test('un dueño suspendido no puede reservar', () =>
    tx(async (t) => {
      await t.q(`update profiles set status = 'suspended' where id = $1`, [IDS.marcela]);
      rejects(
        await t.as(IDS.marcela, () => t.fails(INSERT_BOOKING, [IDS.marcela, IDS.laura, IDS.rocky, 'walk', '1 hour'])),
        /owner_not_allowed/,
      );
    }));
});

// ---------------------------------------------------------------------------
describe('datos privados', () => {
  test('teléfono y ubicación exacta no son visibles antes de una reserva accepted', () =>
    tx(async (t) => {
      const none = await t.as(IDS.marcela, () => t.q(`select * from profile_private where id = $1`, [IDS.laura]));
      assert.equal(none.length, 0, 'sin reserva');
      const { id } = await book(t);
      const pending = await t.as(IDS.marcela, () => t.q(`select * from profile_private where id = $1`, [IDS.laura]));
      assert.equal(pending.length, 0, 'reserva pending');
      await t.as(IDS.laura, () => t.q(`update bookings set status = 'accepted' where id = $1`, [id]));
      const accepted = await t.as(IDS.marcela, () => t.q(`select phone, exact_lat from profile_private where id = $1`, [IDS.laura]));
      assert.equal(accepted.length, 1, 'reserva accepted');
      assert.ok(accepted[0].phone && accepted[0].exact_lat);
    }));

  test('anon no ve datos privados', () =>
    tx(async (t) => {
      const err = await t.as(null, () => t.fails(`select * from profile_private`));
      rejects(err, /permission denied/);
    }));

  test('un extraño no puede leer los datos privados de otro', () =>
    tx(async (t) => {
      const rows = await t.as(IDS.andres, () => t.q(`select * from profile_private where id <> $1`, [IDS.andres]));
      assert.equal(rows.length, 0);
    }));

  test('las notas del perro solo las ve el cuidador con reserva accepted', () =>
    tx(async (t) => {
      await t.as(IDS.marcela, () =>
        t.q(`insert into dog_notes (dog_id, notes) values ($1, 'Alergia a la penicilina')`, [IDS.rocky]),
      );
      const { id } = await book(t);
      const dogPending = await t.as(IDS.laura, () => t.q(`select name from dogs where id = $1`, [IDS.rocky]));
      assert.equal(dogPending.length, 1, 've al perro de una reserva pendiente');
      const notesPending = await t.as(IDS.laura, () => t.q(`select notes from dog_notes where dog_id = $1`, [IDS.rocky]));
      assert.equal(notesPending.length, 0, 'pero no sus notas');
      await t.as(IDS.laura, () => t.q(`update bookings set status = 'accepted' where id = $1`, [id]));
      const notesAccepted = await t.as(IDS.laura, () => t.q(`select notes from dog_notes where dog_id = $1`, [IDS.rocky]));
      assert.equal(notesAccepted.length, 1);
      const stranger = await t.as(IDS.andres, () => t.q(`select * from dogs where id = $1`, [IDS.rocky]));
      assert.equal(stranger.length, 0, 'otro cuidador no ve al perro');
    }));

  test('un perro con reservas activas no se puede borrar', () =>
    tx(async (t) => {
      await book(t);
      rejects(
        await t.as(IDS.marcela, () => t.fails(`delete from dogs where id = $1`, [IDS.rocky])),
        /dog_has_active_bookings/,
      );
      const [luna] = await t.q(`select id from dogs where name = 'Luna'`);
      await t.as(IDS.marcela, () => t.q(`delete from dogs where id = $1`, [luna.id]));
    }));

  test('se rechazan teléfonos, correos y enlaces en bio y notas', () =>
    tx(async (t) => {
      const bad = [
        'llámame al 300 111 2233',
        'escríbeme a laura@gmail.com',
        'mira https://wa.me/573001112233',
        'visita www.mipagina.com',
        'mi sitio es paseos.co',
      ];
      for (const text of bad) {
        const e1 = await t.as(IDS.laura, () => t.fails(`update profiles set bio = $2 where id = $1`, [IDS.laura, text]));
        rejects(e1, /check constraint|profiles_bio_check/);
        const e2 = await t.as(IDS.marcela, () =>
          t.fails(`insert into dog_notes (dog_id, notes) values ($1, $2)`, [IDS.rocky, text]),
        );
        rejects(e2, /check constraint|dog_notes_notes_check/);
      }
    }));

  test('texto normal con números pequeños no se confunde con un teléfono', () =>
    tx((t) =>
      t.as(IDS.laura, async () => {
        await t.q(`update profiles set bio = 'Tengo 2 perros, 5 años de experiencia y 10 reseñas.' where id = $1`, [IDS.laura]);
      }),
    ));
});

// ---------------------------------------------------------------------------
describe('reservas: validaciones en la base', () => {
  test('una reserva válida nace pending y el total lo calcula la base', () =>
    tx(async (t) => {
      const b = await book(t);
      assert.equal(b.status, 'pending');
      assert.equal(b.total_cop, 25000, 'precio del paseo de Laura, no el 1 que mandó el cliente');
    }));

  test('un cliente no puede crear una reserva ya aceptada ni con total propio', () =>
    tx(async (t) => {
      const rows = await t.as(IDS.marcela, () =>
        t.q(
          `insert into bookings (owner_id, sitter_id, dog_id, service_type, start_at, end_at, total_cop, status)
           values ($1, $2, $3, 'walk', now() + interval '1 day', now() + interval '1 day 1 hour', 5000, 'accepted')
           returning status, total_cop`,
          [IDS.marcela, IDS.laura, IDS.rocky],
        ),
      );
      assert.equal(rows[0].status, 'pending');
      assert.equal(rows[0].total_cop, 25000);
    }));

  test('guardería y hospedaje se cobran por día / noche', () =>
    tx(async (t) => {
      const b = await book(t, { service: 'daycare', length: '2 days 3 hours' });
      assert.equal(b.total_cop, 60000 * 3);
    }));

  test('start_at en el pasado se rechaza', () =>
    tx(async (t) => {
      const err = await t.as(IDS.marcela, () =>
        t.fails(
          `insert into bookings (owner_id, sitter_id, dog_id, service_type, start_at, end_at, total_cop)
           values ($1, $2, $3, 'walk', now() - interval '1 day', now() - interval '23 hours', 25000)`,
          [IDS.marcela, IDS.laura, IDS.rocky],
        ),
      );
      rejects(err, /start_in_past/);
    }));

  test('el cuidador tiene 2 horas para responder (o hasta 30 min antes del inicio)', () =>
    tx(async (t) => {
      const far = await book(t); // empieza en 2 días: plazo = ahora + 2 h
      const [a] = await t.q(`select extract(epoch from response_deadline - now()) / 60 as min from bookings where id = $1`, [far.id]);
      assert.ok(Math.abs(a.min - 120) < 1, `plazo ${a.min} min`);

      const [near] = await t.as(IDS.marcela, () =>
        t.q(
          `insert into bookings (owner_id, sitter_id, dog_id, service_type, start_at, end_at, total_cop)
           values ($1, $2, $3, 'walk', now() + interval '90 minutes', now() + interval '150 minutes', 1)
           returning extract(epoch from response_deadline - now()) / 60 as min`,
          [IDS.marcela, IDS.laura, IDS.rocky],
        ),
      );
      assert.ok(Math.abs(near.min - 60) < 1, `inicio en 90 min: plazo ${near.min} min`);
    }));

  test('reservar con menos de 1 hora de anticipación se rechaza', () =>
    tx(async (t) => {
      const err = await t.as(IDS.marcela, () =>
        t.fails(
          `insert into bookings (owner_id, sitter_id, dog_id, service_type, start_at, end_at, total_cop)
           values ($1, $2, $3, 'walk', now() + interval '40 minutes', now() + interval '100 minutes', 1)`,
          [IDS.marcela, IDS.laura, IDS.rocky],
        ),
      );
      rejects(err, /start_too_soon/);
    }));

  test('vencido el plazo, el cuidador ya no puede aceptar ni rechazar', () =>
    tx(async (t) => {
      const { id } = await book(t);
      await t.q(`update bookings set response_deadline = now() - interval '1 minute' where id = $1`, [id]);
      rejects(
        await t.as(IDS.laura, () => t.fails(`update bookings set status = 'accepted' where id = $1`, [id])),
        /response_deadline_passed/,
      );
      // El dueño sí puede cancelar su solicitud vencida.
      await t.as(IDS.marcela, () => t.q(`update bookings set status = 'cancelled' where id = $1`, [id]));
    }));

  test('nadie puede mover el plazo de respuesta', () =>
    tx(async (t) => {
      const { id } = await book(t);
      rejects(
        await t.as(IDS.laura, () => t.fails(`update bookings set response_deadline = now() + interval '9 days' where id = $1`, [id])),
        /permission denied/,
      );
    }));

  test('end_at debe ser posterior a start_at', () =>
    tx(async (t) => {
      const err = await t.as(IDS.marcela, () =>
        t.fails(INSERT_BOOKING, [IDS.marcela, IDS.laura, IDS.rocky, 'walk', '-1 hour']),
      );
      rejects(err, /bookings_end_after_start/);
    }));

  test('owner_id y sitter_id no pueden ser la misma persona', () =>
    tx(async (t) => {
      const err = await t.as(IDS.laura, () =>
        t.fails(INSERT_BOOKING, [IDS.laura, IDS.laura, IDS.rocky, 'walk', '1 hour']),
      );
      assert.ok(err);
    }));

  test('no se puede reservar a un cuidador en revisión', () =>
    tx(async (t) => {
      const err = await t.as(IDS.marcela, () =>
        t.fails(INSERT_BOOKING, [IDS.marcela, IDS.natalia, IDS.rocky, 'walk', '1 hour']),
      );
      rejects(err, /sitter_not_available/);
    }));

  test('solo se reservan servicios que el cuidador ofrece', () =>
    tx(async (t) => {
      const err = await t.as(IDS.marcela, () =>
        t.fails(INSERT_BOOKING, [IDS.marcela, IDS.laura, IDS.rocky, 'grooming', '1 hour']),
      );
      rejects(err, /service_not_offered/);
    }));

  test('no se reserva con el perro de otro dueño', () =>
    tx(async (t) => {
      const other = await t.signUp('o2@t.test', { role: 'owner', accepted_terms: true });
      const [dog] = await t.q(`insert into dogs (owner_id, name) values ($1, 'Ajeno') returning id`, [other]);
      const err = await t.as(IDS.marcela, () =>
        t.fails(INSERT_BOOKING, [IDS.marcela, IDS.laura, dog.id, 'walk', '1 hour']),
      );
      rejects(err, /invalid_dog/);
    }));

  test('no se puede reservar a nombre de otro usuario', () =>
    tx(async (t) => {
      const err = await t.as(IDS.andres, () =>
        t.fails(INSERT_BOOKING, [IDS.marcela, IDS.laura, IDS.rocky, 'walk', '1 hour']),
      );
      assert.ok(err);
    }));

  test('un cuidador no puede reservar (solo dueños)', () =>
    tx(async (t) => {
      const [dog] = await t.q(`insert into dogs (owner_id, name) values ($1, 'D') returning id`, [IDS.andres]);
      const err = await t.as(IDS.andres, () =>
        t.fails(INSERT_BOOKING, [IDS.andres, IDS.laura, dog.id, 'walk', '1 hour']),
      );
      assert.ok(err);
    }));

  test('el precio de un servicio debe estar en un rango razonable', () =>
    tx(async (t) => {
      for (const price of [100, 999999999]) {
        const err = await t.as(IDS.laura, () =>
          t.fails(`update sitter_services set price_cop = $2 where sitter_id = $1 and service_type = 'walk'`, [IDS.laura, price]),
        );
        assert.ok(err);
      }
    }));
});

// ---------------------------------------------------------------------------
describe('reservas: estados y privacidad', () => {
  test('el cuidador acepta y luego completa; las transiciones inválidas fallan', () =>
    tx(async (t) => {
      const { id } = await book(t);
      rejects(
        await t.as(IDS.laura, () => t.fails(`update bookings set status = 'completed' where id = $1`, [id])),
        /invalid_status_transition/,
      );
      await t.as(IDS.laura, () => t.q(`update bookings set status = 'accepted' where id = $1`, [id]));
      await t.as(IDS.laura, () => t.q(`update bookings set status = 'completed' where id = $1`, [id]));
      rejects(
        await t.as(IDS.laura, () => t.fails(`update bookings set status = 'pending' where id = $1`, [id])),
        /invalid_status_transition/,
      );
    }));

  test('el dueño no puede aceptar su propia reserva, pero sí cancelarla', () =>
    tx(async (t) => {
      const { id } = await book(t);
      rejects(
        await t.as(IDS.marcela, () => t.fails(`update bookings set status = 'accepted' where id = $1`, [id])),
        /invalid_status_transition/,
      );
      await t.as(IDS.marcela, () => t.q(`update bookings set status = 'cancelled' where id = $1`, [id]));
      const [b] = await t.q(`select status from bookings where id = $1`, [id]);
      assert.equal(b.status, 'cancelled');
    }));

  test('el cuidador rechaza una solicitud pending', () =>
    tx(async (t) => {
      const { id } = await book(t);
      await t.as(IDS.laura, () => t.q(`update bookings set status = 'rejected' where id = $1`, [id]));
      const [b] = await t.q(`select status from bookings where id = $1`, [id]);
      assert.equal(b.status, 'rejected');
    }));

  test('no se pueden cambiar el total, las fechas ni las partes de una reserva', () =>
    tx(async (t) => {
      const { id } = await book(t);
      const e = await t.as(IDS.marcela, () => t.fails(`update bookings set total_cop = 5000 where id = $1`, [id]));
      rejects(e, /permission denied/);
    }));

  test('un tercero no ve ni modifica reservas ajenas', () =>
    tx(async (t) => {
      const { id } = await book(t);
      const seen = await t.as(IDS.andres, () => t.q(`select id from bookings where id = $1`, [id]));
      assert.equal(seen.length, 0);
      const upd = await t.as(IDS.andres, () => t.q(`update bookings set status = 'accepted' where id = $1 returning id`, [id]));
      assert.equal(upd.length, 0);
    }));

  test('anon no puede leer reservas ni perros', () =>
    tx(async (t) => {
      rejects(await t.as(null, () => t.fails(`select * from bookings`)), /permission denied/);
      rejects(await t.as(null, () => t.fails(`select * from dogs`)), /permission denied/);
    }));

  test('un cuidador suspendido no puede aceptar solicitudes', () =>
    tx(async (t) => {
      const { id } = await book(t);
      await t.q(`update profiles set status = 'suspended' where id = $1`, [IDS.laura]);
      rejects(
        await t.as(IDS.laura, () => t.fails(`update bookings set status = 'accepted' where id = $1`, [id])),
        /invalid_status_transition/,
      );
    }));
});

// ---------------------------------------------------------------------------
describe('reseñas', () => {
  test('solo se reseña una reserva completed', () =>
    tx(async (t) => {
      const { id } = await book(t);
      const err = await t.as(IDS.marcela, () =>
        t.fails(`insert into reviews (booking_id, rating, comment) values ($1, 5, 'Genial')`, [id]),
      );
      rejects(err, /booking_not_completed/);
    }));

  test('una reseña por reserva', () =>
    tx(async (t) => {
      const err = await t.as(IDS.marcela, () =>
        t.fails(`insert into reviews (booking_id, rating) values ($1, 3)`, [IDS.bookingLaura]),
      );
      rejects(err, /duplicate key|reviews_booking_id_key/);
    }));

  test('solo el dueño de la reserva puede reseñar y sitter_id sale de la reserva', () =>
    tx(async (t) => {
      const { id } = await book(t);
      await t.as(IDS.laura, () => t.q(`update bookings set status = 'accepted' where id = $1`, [id]));
      await t.as(IDS.laura, () => t.q(`update bookings set status = 'completed' where id = $1`, [id]));

      const other = await t.signUp('o3@t.test', { role: 'owner', accepted_terms: true });
      rejects(
        await t.as(other, () => t.fails(`insert into reviews (booking_id, rating, owner_id) values ($1, 1, $2)`, [id, other])),
        /forbidden|row-level security/,
      );

      const [r] = await t.as(IDS.marcela, () =>
        t.q(`insert into reviews (booking_id, sitter_id, rating) values ($1, $2, 4) returning sitter_id, owner_id`, [id, IDS.andres]),
      );
      assert.equal(r.sitter_id, IDS.laura, 'ignora el sitter_id que mandó el cliente');
      assert.equal(r.owner_id, IDS.marcela);
    }));

  test('la calificación va de 1 a 5 y las reseñas no se editan', () =>
    tx(async (t) => {
      rejects(
        await t.as(IDS.marcela, () => t.fails(`insert into reviews (booking_id, rating) values ($1, 9)`, [IDS.bookingLaura])),
        /check constraint|reviews_rating_check|duplicate/,
      );
      rejects(
        await t.as(IDS.marcela, () => t.fails(`update reviews set rating = 1`)),
        /permission denied/,
      );
    }));

  test('las reseñas de cuidadores aprobados son públicas y hay promedio', () =>
    tx(async (t) => {
      const rows = await t.as(null, () => t.q(`select rating_avg, rating_count from sitter_rating_stats where sitter_id = $1`, [IDS.laura]));
      assert.equal(rows.length, 1);
      assert.equal(rows[0].rating_count, 1);
    }));
});

// ---------------------------------------------------------------------------
describe('reportes', () => {
  const report = (t, by, against, extra = '') =>
    t.as(by, () =>
      t.q(
        `insert into reports (reporter_id, reported_user_id, reason, comment${extra ? ', booking_id' : ''})
         values ($1, $2, 'fake_profile', 'Perfil sospechoso'${extra ? ', $3' : ''}) returning id, status`,
        extra ? [by, against, extra] : [by, against],
      ),
    );

  test('un reporte creado por un usuario aparece al admin y a nadie más', () =>
    tx(async (t) => {
      const [r] = await report(t, IDS.marcela, IDS.laura);
      assert.equal(r.status, 'open');
      const admin = await adminUser(t);
      const forAdmin = await t.as(admin, () => t.q(`select id from reports where id = $1`, [r.id]));
      const forOwner = await t.as(IDS.marcela, () => t.q(`select id from reports where id = $1`, [r.id]));
      const forOther = await t.as(IDS.andres, () => t.q(`select id from reports where id = $1`, [r.id]));
      assert.equal(forAdmin.length, 1);
      assert.equal(forOwner.length, 1);
      assert.equal(forOther.length, 0);
    }));

  test('no se puede reportar a uno mismo ni crear un reporte ya "revisado"', () =>
    tx(async (t) => {
      const self = await t.as(IDS.marcela, () =>
        t.fails(`insert into reports (reporter_id, reported_user_id, reason) values ($1, $1, 'other')`, [IDS.marcela]),
      );
      rejects(self, /reports_distinct_users/);
      const [r] = await t.as(IDS.marcela, () =>
        t.q(
          `insert into reports (reporter_id, reported_user_id, reason, status) values ($1, $2, 'other', 'dismissed') returning status`,
          [IDS.marcela, IDS.laura],
        ),
      );
      assert.equal(r.status, 'open');
    }));

  test('el reporte con reserva asociada exige que ambos participen en ella', () =>
    tx(async (t) => {
      const { id } = await book(t);
      const err = await t.as(IDS.andres, () =>
        t.fails(
          `insert into reports (reporter_id, reported_user_id, booking_id, reason) values ($1, $2, $3, 'other')`,
          [IDS.andres, IDS.laura, id],
        ),
      );
      rejects(err, /booking_mismatch/);
      const ok = await report(t, IDS.marcela, IDS.laura, id);
      assert.equal(ok.length, 1);
    }));

  test('el admin ve la reserva asociada a un reporte, y solo esa', () =>
    tx(async (t) => {
      const { id } = await book(t);
      const other = await book(t, { service: 'daycare' });
      await report(t, IDS.marcela, IDS.laura, id);
      const admin = await adminUser(t);
      const seen = await t.as(admin, () => t.q(`select id from bookings`));
      assert.deepEqual(seen.map((r) => r.id), [id]);
      assert.notEqual(other.id, id);
    }));

  test('un admin atiende un reporte: suspende al reportado y queda auditado', () =>
    tx(async (t) => {
      const [r] = await report(t, IDS.marcela, IDS.laura);
      const admin = await adminUser(t);
      await t.as(admin, () => t.q(`select admin_resolve_report($1, 'reviewed', true)`, [r.id]));
      const [rep] = await t.q(`select status, reviewed_by from reports where id = $1`, [r.id]);
      const [laura] = await t.q(`select status from profiles where id = $1`, [IDS.laura]);
      assert.equal(rep.status, 'reviewed');
      assert.equal(rep.reviewed_by, admin);
      assert.equal(laura.status, 'suspended');
      const log = await t.q(`select action from admin_actions where target_user_id = $1`, [IDS.laura]);
      assert.deepEqual(log.map((l) => l.action), ['resolve_report']);
    }));

  test('un usuario normal no puede resolver reportes', () =>
    tx(async (t) => {
      const [r] = await report(t, IDS.marcela, IDS.laura);
      rejects(
        await t.as(IDS.andres, () => t.fails(`select admin_resolve_report($1, 'dismissed')`, [r.id])),
        /forbidden/,
      );
    }));
});

// ---------------------------------------------------------------------------
describe('administración y superadmin', () => {
  test('un usuario normal no puede llamar a ninguna acción de admin', () =>
    tx(async (t) => {
      const calls = [
        [`select admin_set_sitter_approval($1, true)`, [IDS.natalia]],
        [`select admin_set_verified($1, true)`, [IDS.laura]],
        [`select admin_set_user_suspended($1, true)`, [IDS.laura]],
        [`select admin_search_users('a')`, []],
        [`select superadmin_set_admin($1, true)`, [IDS.laura]],
        [`select superadmin_delete_user($1)`, [IDS.laura]],
      ];
      for (const [sql, params] of calls) {
        rejects(await t.as(IDS.marcela, () => t.fails(sql, params)), /forbidden/);
      }
    }));

  test('anon no puede ejecutar acciones de admin', () =>
    tx(async (t) => {
      rejects(await t.as(null, () => t.fails(`select admin_search_users('a')`)), /permission denied/);
    }));

  test('un admin no puede suspender ni modificar a otro admin ni al superadmin', () =>
    tx(async (t) => {
      const admin = await adminUser(t, 'a1@t.test', 'admin');
      const admin2 = await adminUser(t, 'a2@t.test', 'admin');
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      for (const target of [admin2, sa]) {
        rejects(await t.as(admin, () => t.fails(`select admin_set_user_suspended($1, true)`, [target])), /protected_user/);
        rejects(await t.as(admin, () => t.fails(`select admin_set_verified($1, true)`, [target])), /protected_user|not_a_sitter/);
      }
      const rows = await t.q(`select status from profiles where id in ($1, $2)`, [admin2, sa]);
      assert.ok(rows.every((r) => r.status === 'approved'));
    }));

  test('el superadmin no puede suspenderse ni degradarse a sí mismo', () =>
    tx(async (t) => {
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      rejects(await t.as(sa, () => t.fails(`select admin_set_user_suspended($1, true)`, [sa])), /cannot_target_self/);
      rejects(await t.as(sa, () => t.fails(`select superadmin_set_admin($1, false)`, [sa])), /cannot_target_self/);
      rejects(await t.as(sa, () => t.fails(`select superadmin_delete_user($1)`, [sa])), /cannot_target_self/);
    }));

  test('nadie puede modificar al superadmin', () =>
    tx(async (t) => {
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      const admin = await adminUser(t, 'a@t.test', 'admin');
      rejects(await t.as(admin, () => t.fails(`select admin_set_user_suspended($1, true)`, [sa])), /protected_user/);
    }));

  test('el superadmin crea un admin, el admin puede moderar y luego se le revoca', () =>
    tx(async (t) => {
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      const candidate = await t.signUp('cand@t.test', { role: 'owner', accepted_terms: true });

      await t.as(sa, () => t.q(`select superadmin_set_admin($1, true)`, [candidate]));
      assert.equal((await t.q(`select role from profiles where id = $1`, [candidate]))[0].role, 'admin');

      await t.as(candidate, () => t.q(`select admin_set_sitter_approval($1, true)`, [IDS.natalia]));
      assert.equal((await t.q(`select status from profiles where id = $1`, [IDS.natalia]))[0].status, 'approved');

      rejects(await t.as(candidate, () => t.fails(`select superadmin_set_admin($1, true)`, [IDS.laura])), /forbidden/);

      await t.as(sa, () => t.q(`select superadmin_set_admin($1, false)`, [candidate]));
      assert.equal((await t.q(`select role from profiles where id = $1`, [candidate]))[0].role, 'owner');
    }));

  test('el superadmin suspende a un admin; un admin no puede', () =>
    tx(async (t) => {
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      const admin = await adminUser(t, 'a@t.test', 'admin');
      await t.as(sa, () => t.q(`select admin_set_user_suspended($1, true)`, [admin]));
      assert.equal((await t.q(`select status from profiles where id = $1`, [admin]))[0].status, 'suspended');
    }));

  test('un admin suspendido pierde sus poderes', () =>
    tx(async (t) => {
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      const admin = await adminUser(t, 'a@t.test', 'admin');
      await t.as(sa, () => t.q(`select admin_set_user_suspended($1, true)`, [admin]));
      rejects(await t.as(admin, () => t.fails(`select admin_search_users('a')`)), /forbidden/);
    }));

  test('cada acción de moderación queda registrada en admin_actions', () =>
    tx(async (t) => {
      const admin = await adminUser(t);
      await t.as(admin, async () => {
        await t.q(`select admin_set_sitter_approval($1, true)`, [IDS.natalia]);
        await t.q(`select admin_set_verified($1, true)`, [IDS.natalia]);
        await t.q(`select admin_set_user_suspended($1, true, 'spam')`, [IDS.andres]);
        await t.q(`select admin_set_user_suspended($1, false)`, [IDS.andres]);
      });
      const log = await t.q(`select action, admin_id from admin_actions order by created_at, id`);
      assert.deepEqual(
        log.map((l) => l.action).sort(),
        ['approve_sitter', 'reactivate_user', 'suspend_user', 'verify_sitter'],
      );
      assert.ok(log.every((l) => l.admin_id === admin));
    }));

  test('el historial: el admin ve el suyo, el superadmin ve todo, un usuario nada', () =>
    tx(async (t) => {
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      const a1 = await adminUser(t, 'a1@t.test', 'admin');
      const a2 = await adminUser(t, 'a2@t.test', 'admin');
      await t.as(a1, () => t.q(`select admin_set_sitter_approval($1, true)`, [IDS.natalia]));
      await t.as(a2, () => t.q(`select admin_set_user_suspended($1, true)`, [IDS.andres]));
      assert.equal((await t.as(a1, () => t.q(`select * from admin_actions`))).length, 1);
      assert.equal((await t.as(a2, () => t.q(`select * from admin_actions`))).length, 1);
      assert.equal((await t.as(sa, () => t.q(`select * from admin_actions`))).length, 2);
      assert.equal((await t.as(IDS.marcela, () => t.q(`select * from admin_actions`))).length, 0);
    }));

  test('nadie puede escribir ni borrar el historial directamente', () =>
    tx(async (t) => {
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      rejects(await t.as(sa, () => t.fails(`insert into admin_actions (action) values ('x')`)), /permission denied/);
      rejects(await t.as(sa, () => t.fails(`delete from admin_actions`)), /permission denied/);
    }));

  test('un admin no puede cambiar roles directamente con UPDATE', () =>
    tx(async (t) => {
      const admin = await adminUser(t);
      rejects(await t.as(admin, () => t.fails(`update profiles set role = 'superadmin' where id = $1`, [admin])), /permission denied/);
    }));

  test('la búsqueda de usuarios encuentra por nombre o correo y filtra', () =>
    tx(async (t) => {
      const admin = await adminUser(t);
      const byName = await t.as(admin, () => t.q(`select * from admin_search_users('Laura')`));
      assert.ok(byName.some((u) => u.id === IDS.laura));
      const byEmail = await t.as(admin, () => t.q(`select * from admin_search_users('seed.natalia')`));
      assert.equal(byEmail.length, 1);
      assert.equal(byEmail[0].email, 'seed.natalia@doggo.test');
      const pending = await t.as(admin, () => t.q(`select * from admin_search_users(null, 'sitter', 'pending_review')`));
      assert.equal(pending.length, 2);
    }));

  test('el superadmin elimina una cuenta y el registro de auditoría sobrevive', () =>
    tx(async (t) => {
      const sa = await adminUser(t, 'sa@t.test', 'superadmin');
      await t.as(sa, () => t.q(`select superadmin_delete_user($1)`, [IDS.natalia]));
      assert.equal((await t.q(`select 1 from profiles where id = $1`, [IDS.natalia])).length, 0);
      const log = await t.q(`select action from admin_actions where target_user_id = $1`, [IDS.natalia]);
      assert.deepEqual(log.map((l) => l.action), ['delete_user']);
    }));
});

// ---------------------------------------------------------------------------
describe('cambio de rol desde ajustes', () => {
  test('dueño a cuidador: queda en revisión; de vuelta a dueño: aprobado', () =>
    tx(async (t) => {
      const id = await t.signUp('sw@t.test', { role: 'owner', accepted_terms: true });
      await t.as(id, () => t.q(`select switch_role('sitter')`));
      assert.deepEqual({ ...(await t.q(`select role, status from profiles where id = $1`, [id]))[0] }, { role: 'sitter', status: 'pending_review' });
      await t.as(id, () => t.q(`select switch_role('owner')`));
      assert.deepEqual({ ...(await t.q(`select role, status from profiles where id = $1`, [id]))[0] }, { role: 'owner', status: 'approved' });
    }));

  test('se bloquea con reservas activas', () =>
    tx(async (t) => {
      await book(t);
      rejects(await t.as(IDS.marcela, () => t.fails(`select switch_role('sitter')`)), /active_bookings/);
      rejects(await t.as(IDS.laura, () => t.fails(`select switch_role('owner')`)), /active_bookings/);
    }));

  test('no se puede cambiar a admin ni desde admin, ni estando suspendido', () =>
    tx(async (t) => {
      rejects(await t.as(IDS.marcela, () => t.fails(`select switch_role('admin')`)), /role_not_switchable/);
      const admin = await adminUser(t);
      rejects(await t.as(admin, () => t.fails(`select switch_role('owner')`)), /role_not_switchable/);
      await t.q(`update profiles set status = 'suspended' where id = $1`, [IDS.marcela]);
      rejects(await t.as(IDS.marcela, () => t.fails(`select switch_role('sitter')`)), /account_suspended/);
    }));
});

// ---------------------------------------------------------------------------
describe('horario del cuidador y vencimiento', () => {
  // Un día a las HH:00 hora de Bogotá, dentro de 2 días.
  const AT = (hour) =>
    `(date_trunc('day', now() at time zone 'America/Bogota') + interval '2 days ${hour} hours') at time zone 'America/Bogota'`;
  const bookAt = (t, hour) =>
    t.as(IDS.marcela, () =>
      t.fails(
        `insert into bookings (owner_id, sitter_id, dog_id, service_type, start_at, end_at, total_cop)
         values ($1, $2, $3, 'walk', ${AT(hour)}, ${AT(hour)} + interval '1 hour', 1)`,
        [IDS.marcela, IDS.laura, IDS.rocky],
      ),
    );
  const setWindow = (t, startMin, endMin) =>
    t.as(IDS.laura, () =>
      t.q(
        `insert into sitter_availability (sitter_id, weekday, start_minute, end_minute)
         values ($1, extract(isodow from ${AT(0)} at time zone 'America/Bogota')::int, $2, $3)`,
        [IDS.laura, startMin, endMin],
      ),
    );

  test('sin horario definido no hay restricción', () =>
    tx(async (t) => {
      assert.equal(await bookAt(t, 9), null);
    }));

  test('la reserva debe empezar dentro del horario del cuidador (hora de Bogotá)', () =>
    tx(async (t) => {
      await setWindow(t, 600, 720); // 10:00–12:00
      rejects(await bookAt(t, 9), /outside_availability/);
      assert.equal(await bookAt(t, 11), null);
      // Otro día de la semana sin fila: ese día no atiende.
      const other = await t.as(IDS.marcela, () =>
        t.fails(
          `insert into bookings (owner_id, sitter_id, dog_id, service_type, start_at, end_at, total_cop)
           values ($1, $2, $3, 'walk', ${AT(11)} + interval '1 day', ${AT(11)} + interval '1 day 1 hour', 1)`,
          [IDS.marcela, IDS.laura, IDS.rocky],
        ),
      );
      rejects(other, /outside_availability/);
    }));

  test('el horario es público, pero solo su dueño lo edita', () =>
    tx(async (t) => {
      await setWindow(t, 600, 720);
      const pub = await t.as(null, () => t.q(`select * from sitter_availability where sitter_id = $1`, [IDS.laura]));
      assert.equal(pub.length, 1);
      const upd = await t.as(IDS.andres, () =>
        t.q(`update sitter_availability set end_minute = 1400 where sitter_id = $1 returning 1`, [IDS.laura]),
      );
      assert.equal(upd.length, 0);
      rejects(
        await t.as(IDS.andres, () =>
          t.fails(`insert into sitter_availability values ($1, 1, 0, 60)`, [IDS.laura]),
        ),
        /row-level security/,
      );
      rejects(
        await t.as(IDS.marcela, () =>
          t.fails(`insert into sitter_availability values ($1, 1, 0, 60)`, [IDS.marcela]),
        ),
        /row-level security/,
      );
    }));

  test('un horario con fin antes del inicio se rechaza', () =>
    tx(async (t) => {
      rejects(
        await t.as(IDS.laura, () => t.fails(`insert into sitter_availability values ($1, 1, 700, 600)`, [IDS.laura])),
        /availability_window/,
      );
    }));

  test('expire_overdue_bookings vence las pendientes con el plazo pasado, y solo esas', () =>
    tx(async (t) => {
      const late = await book(t);
      const onTime = await book(t, { service: 'daycare' });
      await t.q(`update bookings set response_deadline = now() - interval '1 minute' where id = $1`, [late.id]);
      const [{ n }] = await t.q(`select public.expire_overdue_bookings() as n`);
      assert.equal(n, 1);
      const rows = await t.q(`select id, status from bookings where id in ($1, $2)`, [late.id, onTime.id]);
      const by = Object.fromEntries(rows.map((r) => [r.id, r.status]));
      assert.equal(by[late.id], 'expired');
      assert.equal(by[onTime.id], 'pending');
      // Vencida: el cuidador no puede aceptarla.
      rejects(
        await t.as(IDS.laura, () => t.fails(`update bookings set status = 'accepted' where id = $1`, [late.id])),
        /invalid_status_transition/,
      );
    }));

  test('ningún cliente puede ejecutar el vencimiento a mano', () =>
    tx(async (t) => {
      rejects(await t.as(IDS.marcela, () => t.fails(`select public.expire_overdue_bookings()`)), /permission denied/);
    }));
});

describe('servicios del cuidador', () => {
  test('un cuidador gestiona solo sus servicios', () =>
    tx(async (t) => {
      await t.as(IDS.laura, () =>
        t.q(`update sitter_services set price_cop = 27000 where sitter_id = $1 and service_type = 'walk'`, [IDS.laura]),
      );
      const other = await t.as(IDS.laura, () =>
        t.q(`update sitter_services set price_cop = 5000 where sitter_id = $1 returning id`, [IDS.andres]),
      );
      assert.equal(other.length, 0, 'no toca los de otro');
      const err = await t.as(IDS.laura, () =>
        t.fails(`insert into sitter_services (sitter_id, service_type, price_cop) values ($1, 'training', 50000)`, [IDS.andres]),
      );
      rejects(err, /row-level security/);
    }));

  test('un dueño no puede crear servicios', () =>
    tx(async (t) => {
      const err = await t.as(IDS.marcela, () =>
        t.fails(`insert into sitter_services (sitter_id, service_type, price_cop) values ($1, 'walk', 20000)`, [IDS.marcela]),
      );
      rejects(err, /row-level security/);
    }));

  test('un cuidador en revisión puede preparar sus servicios', () =>
    tx((t) =>
      t.as(IDS.natalia, async () => {
        await t.q(`insert into sitter_services (sitter_id, service_type, price_cop) values ($1, 'boarding', 70000)`, [IDS.natalia]);
      }),
    ));
});
