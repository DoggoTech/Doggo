-- =============================================================================
-- Doggo: datos de ejemplo (Bogotá)
--
-- Ejecutar DESPUÉS de schema.sql, en el SQL Editor (corre como `postgres`, por
-- eso las restricciones de columna para clientes no aplican).
--
-- Crea 12 cuidadores (10 aprobados, algunos verificados, y 2 en revisión para
-- que el panel de admin tenga algo que aprobar), un dueño de ejemplo con perros
-- y reservas completadas con reseñas para que los cuidadores tengan calificación.
-- Estas cuentas NO se pueden usar para iniciar sesión (contraseña inválida a
-- propósito): son solo datos. Las cuentas de prueba se crean desde el panel de
-- Supabase y se les asigna rol con supabase/assign_roles.sql.
--
-- Se puede volver a ejecutar: no duplica filas.
-- =============================================================================

-- 1. Usuarios de Auth (el trigger on_auth_user_created crea perfil y fila privada).
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new
)
select '00000000-0000-0000-0000-000000000000', s.id, 'authenticated', 'authenticated',
       s.email, '!no-login', now(),
       '{"provider":"email","providers":["email"]}'::jsonb,
       jsonb_build_object('role', s.role, 'full_name', s.full_name, 'accepted_terms', true),
       now(), now(), '', '', '', ''
from (values
  ('a1000000-0000-4000-8000-000000000001'::uuid, 'sitter',  'Laura Gómez',      'seed.laura@doggo.test'),
  ('a1000000-0000-4000-8000-000000000002'::uuid, 'sitter',  'Andrés Rojas',     'seed.andres@doggo.test'),
  ('a1000000-0000-4000-8000-000000000003'::uuid, 'sitter',  'Camila Herrera',   'seed.camila@doggo.test'),
  ('a1000000-0000-4000-8000-000000000004'::uuid, 'sitter',  'Julián Castro',    'seed.julian@doggo.test'),
  ('a1000000-0000-4000-8000-000000000005'::uuid, 'sitter',  'Valentina Ruiz',   'seed.valentina@doggo.test'),
  ('a1000000-0000-4000-8000-000000000006'::uuid, 'sitter',  'Mateo Vargas',     'seed.mateo@doggo.test'),
  ('a1000000-0000-4000-8000-000000000007'::uuid, 'sitter',  'Daniela Moreno',   'seed.daniela@doggo.test'),
  ('a1000000-0000-4000-8000-000000000008'::uuid, 'sitter',  'Sebastián Ortiz',  'seed.sebastian@doggo.test'),
  ('a1000000-0000-4000-8000-000000000009'::uuid, 'sitter',  'Isabela Mejía',    'seed.isabela@doggo.test'),
  ('a1000000-0000-4000-8000-000000000010'::uuid, 'sitter',  'Felipe Cárdenas',  'seed.felipe@doggo.test'),
  ('a1000000-0000-4000-8000-000000000011'::uuid, 'sitter',  'Natalia Peña',     'seed.natalia@doggo.test'),
  ('a1000000-0000-4000-8000-000000000012'::uuid, 'sitter',  'Ricardo Salazar',  'seed.ricardo@doggo.test'),
  ('a2000000-0000-4000-8000-000000000001'::uuid, 'owner',   'Marcela Duarte',   'seed.marcela@doggo.test')
) as s (id, role, full_name, email)
on conflict (id) do nothing;

-- 2. Perfil de cada cuidador: bio, radio, estado y verificación.
update public.profiles p set
  bio = v.bio, radius_km = v.radius_km, status = v.status::public.user_status,
  verified = v.verified,
  avatar_url = 'https://i.pravatar.cc/300?img=' || v.img
from (values
  ('a1000000-0000-4000-8000-000000000001'::uuid, 'Veterinaria de profesión. Tu perro tendrá paseos largos y mucho cariño en Chapinero.', 4, 'approved', true,  47),
  ('a1000000-0000-4000-8000-000000000002'::uuid, 'Casa con patio grande en Usaquén. Experiencia con razas grandes y cachorros.', 6, 'approved', true,  12),
  ('a1000000-0000-4000-8000-000000000003'::uuid, 'Entrenadora canina certificada. Paseos con refuerzo positivo cerca de Cedritos.', 5, 'approved', true,  32),
  ('a1000000-0000-4000-8000-000000000004'::uuid, 'Estudiante de zootecnia. Hospedaje familiar en Teusaquillo, cerca del parque.', 3, 'approved', false, 15),
  ('a1000000-0000-4000-8000-000000000005'::uuid, 'Amante de los perros pequeños. Visitas a domicilio y guardería en Suba.', 5, 'approved', false, 45),
  ('a1000000-0000-4000-8000-000000000006'::uuid, 'Tengo dos labradores y mucho espacio. Hospedaje nocturno en Kennedy.', 4, 'approved', true,  53),
  ('a1000000-0000-4000-8000-000000000007'::uuid, 'Peluquera canina con 8 años de experiencia. Baño y corte en el Chicó.', 6, 'approved', true,  25),
  ('a1000000-0000-4000-8000-000000000008'::uuid, 'Corredor y ciclista: ideal para perros con mucha energía. Zona Fontibón.', 8, 'approved', false, 59),
  ('a1000000-0000-4000-8000-000000000009'::uuid, 'Cuido perros senior y con necesidades especiales en Engativá.', 4, 'approved', false, 44),
  ('a1000000-0000-4000-8000-000000000010'::uuid, 'Apartamento en La Candelaria. Paseos por el centro y guardería de día.', 3, 'approved', false, 68),
  ('a1000000-0000-4000-8000-000000000011'::uuid, 'Recién registrada: ofrezco paseos y guardería en Bosa.', 5, 'pending_review', false, 5),
  ('a1000000-0000-4000-8000-000000000012'::uuid, 'Recién registrado: visitas a domicilio en Restrepo.', 4, 'pending_review', false, 8)
) as v (id, bio, radius_km, status, verified, img)
where p.id = v.id;

-- 3. Ubicación exacta (privada). El trigger calcula la aproximada que ve el mapa.
update public.profile_private pp set
  exact_lat = v.lat, exact_lng = v.lng, address = v.addr, phone = v.phone
from (values
  ('a1000000-0000-4000-8000-000000000001'::uuid, 4.6486, -74.0628, 'Chapinero',        '3001110001'),
  ('a1000000-0000-4000-8000-000000000002'::uuid, 4.7110, -74.0305, 'Usaquén',          '3001110002'),
  ('a1000000-0000-4000-8000-000000000003'::uuid, 4.7230, -74.0420, 'Cedritos',         '3001110003'),
  ('a1000000-0000-4000-8000-000000000004'::uuid, 4.6410, -74.0850, 'Teusaquillo',      '3001110004'),
  ('a1000000-0000-4000-8000-000000000005'::uuid, 4.7400, -74.0900, 'Suba',             '3001110005'),
  ('a1000000-0000-4000-8000-000000000006'::uuid, 4.6280, -74.1500, 'Kennedy',          '3001110006'),
  ('a1000000-0000-4000-8000-000000000007'::uuid, 4.6700, -74.0520, 'El Chicó',         '3001110007'),
  ('a1000000-0000-4000-8000-000000000008'::uuid, 4.6700, -74.1450, 'Fontibón',         '3001110008'),
  ('a1000000-0000-4000-8000-000000000009'::uuid, 4.7000, -74.1100, 'Engativá',         '3001110009'),
  ('a1000000-0000-4000-8000-000000000010'::uuid, 4.5960, -74.0730, 'La Candelaria',    '3001110010'),
  ('a1000000-0000-4000-8000-000000000011'::uuid, 4.6050, -74.1900, 'Bosa',             '3001110011'),
  ('a1000000-0000-4000-8000-000000000012'::uuid, 4.5850, -74.1000, 'Restrepo',         '3001110012')
) as v (id, lat, lng, addr, phone)
where pp.id = v.id;

-- 4. Servicios y precios (COP) variados por cuidador.
insert into public.sitter_services (sitter_id, service_type, price_cop)
select s.sitter_id::uuid, s.service_type::public.service_type, s.price_cop
from (values
  ('a1000000-0000-4000-8000-000000000001', 'walk',       25000), ('a1000000-0000-4000-8000-000000000001', 'home_visit', 35000),
  ('a1000000-0000-4000-8000-000000000001', 'daycare',    60000),
  ('a1000000-0000-4000-8000-000000000002', 'walk',       30000), ('a1000000-0000-4000-8000-000000000002', 'boarding',  85000),
  ('a1000000-0000-4000-8000-000000000002', 'daycare',    70000),
  ('a1000000-0000-4000-8000-000000000003', 'walk',       28000), ('a1000000-0000-4000-8000-000000000003', 'training',  90000),
  ('a1000000-0000-4000-8000-000000000004', 'boarding',   65000), ('a1000000-0000-4000-8000-000000000004', 'walk',      20000),
  ('a1000000-0000-4000-8000-000000000005', 'home_visit', 30000), ('a1000000-0000-4000-8000-000000000005', 'daycare',   55000),
  ('a1000000-0000-4000-8000-000000000005', 'walk',       22000),
  ('a1000000-0000-4000-8000-000000000006', 'boarding',   60000), ('a1000000-0000-4000-8000-000000000006', 'walk',      18000),
  ('a1000000-0000-4000-8000-000000000007', 'grooming',  120000), ('a1000000-0000-4000-8000-000000000007', 'walk',      35000),
  ('a1000000-0000-4000-8000-000000000008', 'walk',       24000), ('a1000000-0000-4000-8000-000000000008', 'training',  80000),
  ('a1000000-0000-4000-8000-000000000009', 'home_visit', 32000), ('a1000000-0000-4000-8000-000000000009', 'boarding',  75000),
  ('a1000000-0000-4000-8000-000000000010', 'walk',       21000), ('a1000000-0000-4000-8000-000000000010', 'daycare',   50000),
  ('a1000000-0000-4000-8000-000000000011', 'walk',       19000), ('a1000000-0000-4000-8000-000000000011', 'daycare',   45000),
  ('a1000000-0000-4000-8000-000000000012', 'home_visit', 28000)
) as s (sitter_id, service_type, price_cop)
on conflict (sitter_id, service_type) do nothing;

-- 5. Dueño de ejemplo con dos perros.
insert into public.dogs (id, owner_id, name, breed, size) values
  ('d1000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'Rocky', 'Labrador',   'large'),
  ('d1000000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-000000000001', 'Luna',  'Beagle',     'medium')
on conflict (id) do nothing;

-- 6. Reservas completadas y reseñas (para que haya calificaciones en el mapa).
insert into public.bookings (id, owner_id, sitter_id, dog_id, service_type, start_at, end_at, status)
select b.id::uuid, 'a2000000-0000-4000-8000-000000000001', b.sitter_id::uuid,
       'd1000000-0000-4000-8000-000000000001', b.service_type::public.service_type,
       now() - interval '20 days', now() - interval '20 days' + interval '1 hour', 'completed'
from (values
  ('b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'walk'),
  ('b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000002', 'walk'),
  ('b1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000003', 'walk'),
  ('b1000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000007', 'grooming'),
  ('b1000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000006', 'walk')
) as b (id, sitter_id, service_type)
on conflict (id) do nothing;

insert into public.reviews (booking_id, rating, comment)
select r.booking_id::uuid, r.rating, r.comment
from (values
  ('b1000000-0000-4000-8000-000000000001', 5, 'Rocky volvió feliz y cansado. Muy puntual y cariñosa.'),
  ('b1000000-0000-4000-8000-000000000002', 5, 'Excelente trato y mucha comunicación durante el paseo.'),
  ('b1000000-0000-4000-8000-000000000003', 4, 'Muy profesional, repetiremos.'),
  ('b1000000-0000-4000-8000-000000000004', 5, 'Dejó a Rocky precioso. Súper recomendada.'),
  ('b1000000-0000-4000-8000-000000000005', 4, 'Todo bien, un poco de retraso al llegar.')
) as r (booking_id, rating, comment)
on conflict (booking_id) do nothing;
