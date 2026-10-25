-- =============================================================================
-- Doggo: roles de las cuentas de prueba
--
-- 1. En el panel de Supabase (Authentication -> Users -> Add user, con
--    "Auto Confirm User" activado) crea:
--      dueno@doggo.app, cuidador@doggo.app, admin@doggo.app, superadmin@doggo.app
--    con la contraseña de demo que documentes en el README (no es secreta).
-- 2. Ejecuta este script en el SQL Editor.
--
-- Las cuentas creadas desde el panel nacen como dueño. `admin` y `superadmin`
-- solo se pueden asignar así (o, para admin, desde la pestaña Equipo): ningún
-- cliente de la API puede cambiar su propio rol.
-- =============================================================================

update public.profiles set full_name = 'Daniela Dueña', terms_accepted_at = now()
 where id = (select id from auth.users where email = 'dueno@doggo.app');

update public.profiles
   set role = 'sitter', status = 'approved', verified = true,
       full_name = 'Carlos Cuidador', radius_km = 5, terms_accepted_at = now(),
       bio = 'Cuidador de prueba: paseos y guardería en Chapinero.'
 where id = (select id from auth.users where email = 'cuidador@doggo.app');

update public.profile_private
   set exact_lat = 4.6530, exact_lng = -74.0610, address = 'Chapinero'
 where id = (select id from auth.users where email = 'cuidador@doggo.app');

insert into public.sitter_services (sitter_id, service_type, price_cop)
select u.id, s.t::public.service_type, s.p
  from auth.users u,
       (values ('walk', 26000), ('daycare', 62000), ('home_visit', 34000)) as s (t, p)
 where u.email = 'cuidador@doggo.app'
on conflict (sitter_id, service_type) do nothing;

update public.profiles
   set role = 'admin', status = 'approved', full_name = 'Ana Admin', terms_accepted_at = now()
 where id = (select id from auth.users where email = 'admin@doggo.app');

-- Falla si ya existe otro superadmin: el índice único lo garantiza.
update public.profiles
   set role = 'superadmin', status = 'approved', full_name = 'Sergio Superadmin', terms_accepted_at = now()
 where id = (select id from auth.users where email = 'superadmin@doggo.app');
