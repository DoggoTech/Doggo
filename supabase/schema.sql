-- =============================================================================
-- Doggo: esquema de Supabase (Postgres)
--
-- Ejecutar UNA vez, completo, en el SQL Editor de un proyecto nuevo.
-- Orden: tipos -> helpers -> tablas -> triggers -> RLS -> RPCs -> realtime
--        -> storage -> permisos -> 11. casos de verificación (fase 13).
--
-- Principio: la seguridad vive en la base, no en la app. Ocultar un botón en la
-- UI no protege nada; las políticas RLS, los triggers y los permisos de columna
-- sí. Las acciones de moderación solo existen como funciones RPC con
-- `security definer` que validan el rol de quien llama y dejan auditoría.
-- =============================================================================

create schema if not exists private;

-- -----------------------------------------------------------------------------
-- 1. Tipos
-- -----------------------------------------------------------------------------
create type public.user_role      as enum ('owner', 'sitter', 'admin', 'superadmin');
create type public.user_status    as enum ('pending_review', 'approved', 'suspended');
create type public.service_type   as enum ('walk', 'daycare', 'boarding', 'home_visit', 'grooming', 'training');
create type public.booking_status as enum ('pending', 'accepted', 'rejected', 'cancelled', 'completed', 'expired');
create type public.report_reason  as enum ('inappropriate_behavior', 'fake_profile', 'off_platform_payment', 'animal_abuse', 'other');
create type public.report_status  as enum ('open', 'reviewed', 'dismissed');
create type public.dog_size       as enum ('small', 'medium', 'large', 'giant');

-- -----------------------------------------------------------------------------
-- 2. Helpers sin dependencias de tablas
-- -----------------------------------------------------------------------------

-- Detección básica de teléfonos, correos y enlaces (sección 13d del contexto).
-- Se usa en CHECK: la regla vale aunque alguien llame a la API directamente.
create function private.contains_contact_info(t text)
returns boolean
language sql
immutable
as $$
  select t is not null and (
    t ~* '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[a-z]{2,}'            -- correo
    or t ~* '(https?://|www\.)'                                    -- enlace
    or t ~* '\m[[:alnum:]-]+\.(com|co|net|org|io|app|me|ly)\M'     -- dominio suelto
    or t ~ '\d([[:space:].()-]*\d){6,}'                            -- 7+ dígitos seguidos
  );
$$;

-- Verdadero cuando la sentencia la ejecuta un cliente de la API (PostgREST usa
-- los roles anon/authenticated). Dentro de una función `security definer`
-- current_user pasa a ser el dueño de la función, así que las RPC internas y el
-- panel de Supabase quedan fuera de las restricciones de columna.
create function private.is_client_role()
returns boolean
language sql
stable
as $$ select current_user in ('anon', 'authenticated') $$;

-- -----------------------------------------------------------------------------
-- 3. Tablas
-- -----------------------------------------------------------------------------

-- Perfil público. La fila la crea el trigger de registro, nunca el cliente.
create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  role              public.user_role   not null default 'owner',
  full_name         text not null default '' check (char_length(full_name) <= 80),
  avatar_url        text,
  bio               text check (char_length(bio) <= 600 and not private.contains_contact_info(bio)),
  approx_lat        double precision check (approx_lat between -90 and 90),
  approx_lng        double precision check (approx_lng between -180 and 180),
  radius_km         integer check (radius_km between 1 and 50),
  -- Barrio que el cuidador muestra en el mapa ("Chapinero"), nunca la dirección.
  neighborhood      text check (char_length(neighborhood) <= 60 and not private.contains_contact_info(neighborhood)),
  status            public.user_status not null default 'approved',
  verified          boolean not null default false,
  terms_accepted_at timestamptz,
  created_at        timestamptz not null default now()
);

-- Solo puede existir un superadmin (la base lo garantiza).
create unique index profiles_single_superadmin on public.profiles (role) where role = 'superadmin';
create index profiles_role_status_idx on public.profiles (role, status);

-- Datos sensibles. Solo el dueño y la contraparte de una reserva `accepted`.
create table public.profile_private (
  id        uuid primary key references public.profiles (id) on delete cascade,
  phone     text check (phone ~ '^[0-9+() -]{7,20}$'),
  exact_lat double precision check (exact_lat between -90 and 90),
  exact_lng double precision check (exact_lng between -180 and 180),
  address   text check (char_length(address) <= 200)
);

create table public.dogs (
  id       uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name     text not null check (char_length(name) between 1 and 40),
  breed    text check (char_length(breed) <= 60),
  size     public.dog_size not null default 'medium'
);
create index dogs_owner_idx on public.dogs (owner_id);

-- Notas médicas y de comportamiento, aparte de `dogs` para poder mostrarlas
-- solo con una reserva `accepted` (RLS filtra filas, no columnas).
create table public.dog_notes (
  dog_id uuid primary key references public.dogs (id) on delete cascade,
  notes  text check (char_length(notes) <= 1000 and not private.contains_contact_info(notes))
);

create table public.sitter_services (
  id           uuid primary key default gen_random_uuid(),
  sitter_id    uuid not null references public.profiles (id) on delete cascade,
  service_type public.service_type not null,
  price_cop    integer not null check (price_cop between 5000 and 2000000),
  active       boolean not null default true,
  unique (sitter_id, service_type)
);

-- Horario semanal del cuidador: franja en la que puede EMPEZAR un servicio,
-- en hora de Bogotá. Día ISO (1 = lunes … 7 = domingo). Sin filas = sin
-- restricción (la app ofrece de 7:00 a 19:00).
create table public.sitter_availability (
  sitter_id    uuid not null references public.profiles (id) on delete cascade,
  weekday      smallint not null check (weekday between 1 and 7),
  start_minute smallint not null check (start_minute between 0 and 1439),
  end_minute   smallint not null check (end_minute between 0 and 1439),
  primary key (sitter_id, weekday),
  constraint availability_window check (end_minute >= start_minute)
);

create table public.bookings (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles (id) on delete cascade,
  sitter_id    uuid not null references public.profiles (id) on delete cascade,
  dog_id       uuid references public.dogs (id) on delete set null,
  service_type public.service_type not null,
  start_at     timestamptz not null,
  end_at       timestamptz not null,
  total_cop    integer not null check (total_cop between 5000 and 20000000),
  status       public.booking_status not null default 'pending',
  created_at   timestamptz not null default now(),
  -- Hasta cuándo puede responder el cuidador (lo fija el trigger de insert).
  response_deadline timestamptz not null,
  constraint bookings_distinct_parties check (owner_id <> sitter_id),
  constraint bookings_end_after_start  check (end_at > start_at)
);
create index bookings_sitter_idx on public.bookings (sitter_id, status);
create index bookings_owner_idx  on public.bookings (owner_id, status);

create table public.reviews (
  id         uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id) on delete cascade,
  sitter_id  uuid not null references public.profiles (id) on delete cascade,
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  rating     smallint not null check (rating between 1 and 5),
  -- "Daniela D.": lo fija el trigger. El perfil del dueño no es público, así
  -- que el nombre se guarda aquí para mostrarlo junto a la reseña.
  author_name text not null default '',
  comment    text check (char_length(comment) <= 500 and not private.contains_contact_info(comment)),
  created_at timestamptz not null default now()
);
create index reviews_sitter_idx on public.reviews (sitter_id);

create table public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references public.profiles (id) on delete cascade,
  reported_user_id uuid not null references public.profiles (id) on delete cascade,
  booking_id       uuid references public.bookings (id) on delete set null,
  reason           public.report_reason not null,
  comment          text check (char_length(comment) <= 1000),
  status           public.report_status not null default 'open',
  created_at       timestamptz not null default now(),
  reviewed_by      uuid references public.profiles (id) on delete set null,
  reviewed_at      timestamptz,
  constraint reports_distinct_users check (reporter_id <> reported_user_id)
);
create index reports_status_idx on public.reports (status);

-- Auditoría de cada acción de moderación. `target_user_id` no tiene FK a
-- propósito: el registro debe sobrevivir si la cuenta se elimina.
create table public.admin_actions (
  id             uuid primary key default gen_random_uuid(),
  admin_id       uuid references public.profiles (id) on delete set null,
  action         text not null,
  target_user_id uuid,
  details        jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index admin_actions_admin_idx on public.admin_actions (admin_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 4. Helpers que consultan tablas (schema `private`: PostgREST no lo expone)
--    `security definer` para que no dependan de las políticas RLS del llamador
--    ni creen recursión entre políticas.
-- -----------------------------------------------------------------------------
create function private.has_role(uid uuid, r public.user_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = uid and role = r and status <> 'suspended');
$$;

create function private.is_approved(uid uuid, r public.user_role)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = uid and role = r and status = 'approved');
$$;

create function private.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role in ('admin', 'superadmin') and status = 'approved'
  );
$$;

create function private.is_superadmin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role = 'superadmin' and status = 'approved'
  );
$$;

create function private.is_public_sitter(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select private.is_approved(uid, 'sitter');
$$;

create function private.has_booking_with(other uuid, only_status public.booking_status default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from bookings b
    where ((b.owner_id = auth.uid() and b.sitter_id = other)
        or (b.sitter_id = auth.uid() and b.owner_id = other))
      and (only_status is null or b.status = only_status)
  );
$$;

create function private.owns_dog(uid uuid, d uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from dogs where id = d and owner_id = uid);
$$;

-- ¿El cuidador que llama tiene una reserva (en estos estados) de este perro?
create function private.sitter_has_dog_booking(d uuid, statuses public.booking_status[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from bookings
    where dog_id = d and sitter_id = auth.uid() and status = any (statuses)
  );
$$;

create function private.booking_has_report(b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from reports where booking_id = b);
$$;

-- ¿El inicio cae dentro del horario del cuidador? (hora de Bogotá)
create function private.within_availability(s uuid, t timestamptz)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from sitter_availability where sitter_id = s)
      or exists (
        select 1 from sitter_availability
        where sitter_id = s
          and weekday = extract(isodow from (t at time zone 'America/Bogota'))::int
          and (extract(hour from (t at time zone 'America/Bogota')) * 60
             + extract(minute from (t at time zone 'America/Bogota')))
              between start_minute and end_minute
      );
$$;

create function private.service_price(s uuid, t public.service_type)
returns integer language sql stable security definer set search_path = public as $$
  select price_cop from sitter_services where sitter_id = s and service_type = t and active;
$$;

create function private.has_active_bookings(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from bookings
    where (owner_id = uid or sitter_id = uid) and status in ('pending', 'accepted')
  );
$$;

-- -----------------------------------------------------------------------------
-- 5. Triggers
-- -----------------------------------------------------------------------------

-- 5a. Registro: crea perfil y fila privada a partir de los metadatos de Auth.
--     Solo se aceptan `owner` y `sitter`; admin y superadmin se asignan aparte.
--     Si la cuenta viene de la app (trae `role`) exige haber aceptado términos.
--     Las cuentas creadas desde el panel de Supabase (sin metadatos) nacen
--     como dueño aprobado.
create function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  meta     jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  r        public.user_role := 'owner';
  accepted boolean := false;
begin
  if meta ? 'role' then
    if meta ->> 'role' not in ('owner', 'sitter') then
      raise exception 'invalid_role' using errcode = '22023';
    end if;
    r := (meta ->> 'role')::public.user_role;
    accepted := coalesce((meta ->> 'accepted_terms')::boolean, false);
    if not accepted then
      raise exception 'terms_required' using errcode = '22023';
    end if;
  end if;

  insert into profiles (id, role, full_name, status, terms_accepted_at)
  values (
    new.id, r,
    left(coalesce(meta ->> 'full_name', ''), 80),
    case when r = 'sitter' then 'pending_review' else 'approved' end::public.user_status,
    case when accepted then now() end
  );
  insert into profile_private (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- 5b. Un cliente no puede tocar role, status, verified ni la ubicación
--     aproximada. (Los permisos de columna ya lo impiden; esto es la segunda
--     barrera por si algún día se amplían los GRANT.)
create function private.guard_profile_update()
returns trigger language plpgsql as $$
begin
  if private.is_client_role() and (
       new.id                is distinct from old.id
    or new.role              is distinct from old.role
    or new.status            is distinct from old.status
    or new.verified          is distinct from old.verified
    or new.terms_accepted_at is distinct from old.terms_accepted_at
    or new.approx_lat        is distinct from old.approx_lat
    or new.approx_lng        is distinct from old.approx_lng
    or new.created_at        is distinct from old.created_at
  ) then
    raise exception 'protected_column' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger guard_profile_update
  before update on public.profiles
  for each row execute function private.guard_profile_update();

-- 5c. La ubicación del mapa es la exacta desplazada 200–300 m. El desplazamiento
--     es determinista por usuario (no aleatorio en cada guardado), porque un
--     desplazamiento nuevo cada vez permitiría promediar y recuperar la exacta.
create function private.sync_approx_location()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  bearing double precision;
  dist    double precision;
begin
  if new.exact_lat is null or new.exact_lng is null then
    update profiles set approx_lat = null, approx_lng = null where id = new.id;
  else
    bearing := radians((abs(hashtext(new.id::text)::bigint) % 360)::double precision);
    dist    := 200 + (abs(hashtext(new.id::text || 'd')::bigint) % 101);
    update profiles
       set approx_lat = new.exact_lat + degrees(dist * cos(bearing) / 6371000.0),
           approx_lng = new.exact_lng + degrees(dist * sin(bearing) / (6371000.0 * cos(radians(new.exact_lat))))
     where id = new.id;
  end if;
  return new;
end;
$$;

create trigger sync_approx_location
  after insert or update of exact_lat, exact_lng on public.profile_private
  for each row execute function private.sync_approx_location();

-- 5d. Reservas: validaciones de integridad en la base (sección 13e).
create function private.validate_booking_insert()
returns trigger language plpgsql as $$
declare
  price integer;
  units integer := 1;
  client boolean := private.is_client_role();
begin
  if client then
    if auth.uid() is distinct from new.owner_id then
      raise exception 'forbidden' using errcode = '42501';
    end if;
    new.status := 'pending';
    if new.start_at <= now() then
      raise exception 'start_in_past' using errcode = '22023';
    end if;
    -- Al menos 1 h de anticipación: deja 30 min mínimo para que el cuidador responda.
    if new.start_at < now() + interval '1 hour' then
      raise exception 'start_too_soon' using errcode = '22023';
    end if;
  end if;

  -- El cuidador responde en 2 h, o hasta 30 min antes del inicio si es antes.
  new.response_deadline := least(now() + interval '2 hours', new.start_at - interval '30 minutes');

  if not private.is_approved(new.owner_id, 'owner') then
    raise exception 'owner_not_allowed' using errcode = '22023';
  end if;
  if not private.is_approved(new.sitter_id, 'sitter') then
    raise exception 'sitter_not_available' using errcode = '22023';
  end if;
  if new.dog_id is null or not private.owns_dog(new.owner_id, new.dog_id) then
    raise exception 'invalid_dog' using errcode = '22023';
  end if;

  if not private.within_availability(new.sitter_id, new.start_at) then
    raise exception 'outside_availability' using errcode = '22023';
  end if;

  price := private.service_price(new.sitter_id, new.service_type);
  if price is null then
    raise exception 'service_not_offered' using errcode = '22023';
  end if;

  -- Guardería y hospedaje se cobran por día / noche; el resto, por unidad.
  if new.service_type in ('daycare', 'boarding') and new.end_at > new.start_at then
    units := greatest(1, ceil(extract(epoch from (new.end_at - new.start_at)) / 86400.0)::integer);
  end if;

  -- El total lo calcula la base: un cliente no puede fijar su propio precio.
  if client or new.total_cop is null then
    new.total_cop := price * units;
  end if;
  return new;
end;
$$;

create trigger validate_booking_insert
  before insert on public.bookings
  for each row execute function private.validate_booking_insert();

-- Solo cambia `status`, y solo por transiciones permitidas según quién llama.
create function private.guard_booking_update()
returns trigger language plpgsql as $$
declare
  uid uuid := auth.uid();
begin
  if not private.is_client_role() then
    return new;
  end if;

  if new.id           is distinct from old.id
  or new.owner_id     is distinct from old.owner_id
  or new.sitter_id    is distinct from old.sitter_id
  or new.dog_id       is distinct from old.dog_id
  or new.service_type is distinct from old.service_type
  or new.start_at     is distinct from old.start_at
  or new.end_at       is distinct from old.end_at
  or new.total_cop    is distinct from old.total_cop
  or new.created_at   is distinct from old.created_at
  or new.response_deadline is distinct from old.response_deadline then
    raise exception 'immutable_booking_column' using errcode = '42501';
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  -- Vencido el plazo, el cuidador ya no puede responder la solicitud.
  if uid = old.sitter_id and old.status = 'pending' and now() >= old.response_deadline then
    raise exception 'response_deadline_passed' using errcode = '22023';
  end if;

  if uid = old.sitter_id and private.is_approved(uid, 'sitter')
     and ((old.status = 'pending'  and new.status in ('accepted', 'rejected'))
       or (old.status = 'accepted' and new.status = 'completed')) then
    return new;
  end if;

  if uid = old.owner_id and private.is_approved(uid, 'owner')
     and old.status in ('pending', 'accepted') and new.status = 'cancelled' then
    return new;
  end if;

  raise exception 'invalid_status_transition' using errcode = '42501';
end;
$$;

create trigger guard_booking_update
  before update on public.bookings
  for each row execute function private.guard_booking_update();

-- 5e. Reseñas: solo sobre reservas `completed`, del dueño de esa reserva.
--     sitter_id y owner_id salen de la reserva, no de lo que mande el cliente.
create function private.validate_review_insert()
returns trigger language plpgsql as $$
declare
  b record;
begin
  select owner_id, sitter_id, status into b
    from private.booking_for_review(new.booking_id);
  if b.status is distinct from 'completed' then
    raise exception 'booking_not_completed' using errcode = '22023';
  end if;
  if private.is_client_role() and auth.uid() is distinct from b.owner_id then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  new.owner_id    := b.owner_id;
  new.sitter_id   := b.sitter_id;
  new.author_name := private.short_name(b.owner_id);
  return new;
end;
$$;

-- "Daniela Dueña" -> "Daniela D." (nombre y la inicial del apellido).
create function private.short_name(uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
           when split_part(trim(full_name), ' ', 2) = '' then split_part(trim(full_name), ' ', 1)
           else split_part(trim(full_name), ' ', 1) || ' ' || left(split_part(trim(full_name), ' ', 2), 1) || '.'
         end
    from profiles where id = uid;
$$;

create function private.booking_for_review(b uuid)
returns table (owner_id uuid, sitter_id uuid, status public.booking_status)
language sql stable security definer set search_path = public as $$
  select owner_id, sitter_id, status from bookings where id = b;
$$;

create trigger validate_review_insert
  before insert on public.reviews
  for each row execute function private.validate_review_insert();

-- 5f. Reportes.
create function private.validate_report_insert()
returns trigger language plpgsql as $$
begin
  if private.is_client_role() then
    if auth.uid() is distinct from new.reporter_id then
      raise exception 'forbidden' using errcode = '42501';
    end if;
    new.status      := 'open';
    new.reviewed_by := null;
    new.reviewed_at := null;
  end if;
  if not (private.is_approved(new.reporter_id, 'owner')
       or private.is_approved(new.reporter_id, 'sitter')) then
    raise exception 'reporter_not_allowed' using errcode = '22023';
  end if;
  if new.booking_id is not null and not private.booking_involves(new.booking_id, new.reporter_id, new.reported_user_id) then
    raise exception 'booking_mismatch' using errcode = '22023';
  end if;
  return new;
end;
$$;

create function private.booking_involves(b uuid, u1 uuid, u2 uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from bookings
    where id = b
      and ((owner_id = u1 and sitter_id = u2) or (owner_id = u2 and sitter_id = u1))
  );
$$;

-- 5g. Un perro con reservas activas no se borra: el cuidador perdería sus datos.
create function private.guard_dog_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from bookings where dog_id = old.id and status in ('pending', 'accepted')) then
    raise exception 'dog_has_active_bookings' using errcode = '22023';
  end if;
  return old;
end;
$$;

create trigger guard_dog_delete
  before delete on public.dogs
  for each row execute function private.guard_dog_delete();

create trigger validate_report_insert
  before insert on public.reports
  for each row execute function private.validate_report_insert();

-- -----------------------------------------------------------------------------
-- 6. Row Level Security
-- -----------------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.profile_private enable row level security;
alter table public.dogs            enable row level security;
alter table public.dog_notes       enable row level security;
alter table public.sitter_services enable row level security;
alter table public.bookings        enable row level security;
alter table public.sitter_availability enable row level security;
alter table public.reviews         enable row level security;
alter table public.reports         enable row level security;
alter table public.admin_actions   enable row level security;

-- profiles: lectura pública solo de cuidadores aprobados (suspendidos y en
-- revisión desaparecen del mapa); cada quien ve el suyo; la contraparte de una
-- reserva ve el perfil del otro; el admin ve todos.
create policy profiles_select on public.profiles for select using (
  id = auth.uid()
  or (role = 'sitter' and status = 'approved')
  or private.is_admin()
  or private.has_booking_with(id)
);
create policy profiles_update_own on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- profile_private: el dueño, y la contraparte SOLO con reserva `accepted`.
create policy profile_private_select on public.profile_private for select using (
  id = auth.uid() or private.has_booking_with(id, 'accepted')
);
create policy profile_private_update_own on public.profile_private for update
  using (id = auth.uid()) with check (id = auth.uid());

-- dogs: el dueño todo; el cuidador ve al perro de cualquier reserva suya (el
-- nombre aparece en su historial). Las notas médicas siguen aparte (dog_notes).
create policy dogs_select on public.dogs for select using (
  owner_id = auth.uid()
  or private.sitter_has_dog_booking(id, array['pending', 'accepted', 'rejected', 'cancelled', 'completed', 'expired']::public.booking_status[])
);
create policy dogs_insert_own on public.dogs for insert
  with check (owner_id = auth.uid() and private.has_role(auth.uid(), 'owner'));
create policy dogs_update_own on public.dogs for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy dogs_delete_own on public.dogs for delete using (owner_id = auth.uid());

-- dog_notes: el dueño; el cuidador solo con reserva `accepted` de ese perro.
create policy dog_notes_select on public.dog_notes for select using (
  private.owns_dog(auth.uid(), dog_id)
  or private.sitter_has_dog_booking(dog_id, array['accepted']::public.booking_status[])
);
create policy dog_notes_insert_own on public.dog_notes for insert
  with check (private.owns_dog(auth.uid(), dog_id));
create policy dog_notes_update_own on public.dog_notes for update
  using (private.owns_dog(auth.uid(), dog_id)) with check (private.owns_dog(auth.uid(), dog_id));
create policy dog_notes_delete_own on public.dog_notes for delete
  using (private.owns_dog(auth.uid(), dog_id));

-- sitter_services: públicos los activos de cuidadores aprobados (también para
-- `anon`: el keep-alive los consulta con la clave anónima).
create policy services_select on public.sitter_services for select using (
  (active and private.is_public_sitter(sitter_id))
  or sitter_id = auth.uid()
  or private.is_admin()
);
create policy services_insert_own on public.sitter_services for insert
  with check (sitter_id = auth.uid() and private.has_role(auth.uid(), 'sitter'));
create policy services_update_own on public.sitter_services for update
  using (sitter_id = auth.uid()) with check (sitter_id = auth.uid());
create policy services_delete_own on public.sitter_services for delete
  using (sitter_id = auth.uid());

-- sitter_availability: pública para cuidadores aprobados (la hoja de reserva
-- la necesita); el cuidador gestiona la suya, también estando en revisión.
create policy availability_select on public.sitter_availability for select using (
  private.is_public_sitter(sitter_id) or sitter_id = auth.uid() or private.is_admin()
);
create policy availability_insert_own on public.sitter_availability for insert
  with check (sitter_id = auth.uid() and private.has_role(auth.uid(), 'sitter'));
create policy availability_update_own on public.sitter_availability for update
  using (sitter_id = auth.uid()) with check (sitter_id = auth.uid());
create policy availability_delete_own on public.sitter_availability for delete
  using (sitter_id = auth.uid());

-- bookings: solo las partes; el admin ve únicamente la reserva ligada a un reporte.
create policy bookings_select on public.bookings for select using (
  owner_id = auth.uid()
  or sitter_id = auth.uid()
  or (private.is_admin() and private.booking_has_report(id))
);
create policy bookings_insert_own on public.bookings for insert
  with check (owner_id = auth.uid());
create policy bookings_update_parties on public.bookings for update
  using (owner_id = auth.uid() or sitter_id = auth.uid())
  with check (owner_id = auth.uid() or sitter_id = auth.uid());

-- reviews: públicas para cuidadores aprobados; las partes y el admin ven el resto.
create policy reviews_select on public.reviews for select using (
  private.is_public_sitter(sitter_id)
  or owner_id = auth.uid() or sitter_id = auth.uid()
  or private.is_admin()
);
create policy reviews_insert_own on public.reviews for insert
  with check (owner_id = auth.uid());

-- reports: quien reporta ve los suyos; el admin ve todos.
create policy reports_select on public.reports for select using (
  reporter_id = auth.uid() or private.is_admin()
);
create policy reports_insert_own on public.reports for insert
  with check (reporter_id = auth.uid());

-- admin_actions: el admin su propio historial; el superadmin todo. Solo las
-- RPC escriben aquí (no hay política de insert para clientes).
create policy admin_actions_select on public.admin_actions for select using (
  private.is_superadmin() or (private.is_admin() and admin_id = auth.uid())
);

-- Calificación promedio por cuidador (para el mapa y el perfil).
create view public.sitter_rating_stats with (security_invoker = true) as
  select sitter_id,
         round(avg(rating)::numeric, 2) as rating_avg,
         count(*)::integer              as rating_count
    from public.reviews
   group by sitter_id;

-- -----------------------------------------------------------------------------
-- 7. RPC: acciones que ningún cliente puede hacer directamente
-- -----------------------------------------------------------------------------

create function private.log_action(p_action text, p_target uuid, p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public as $$
  insert into admin_actions (admin_id, action, target_user_id, details)
  values (auth.uid(), p_action, p_target, coalesce(p_details, '{}'::jsonb));
$$;

-- Reglas de protección entre roles (sección 13b). Devuelve el rol del objetivo.
create function private.assert_can_moderate(target uuid)
returns public.user_role language plpgsql stable security definer set search_path = public as $$
declare
  actor_role  public.user_role;
  target_role public.user_role;
begin
  select role into actor_role from profiles where id = auth.uid() and status = 'approved';
  if actor_role not in ('admin', 'superadmin') or actor_role is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if target = auth.uid() then
    raise exception 'cannot_target_self' using errcode = '42501';
  end if;
  select role into target_role from profiles where id = target;
  if target_role is null then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  if target_role = 'superadmin' then
    raise exception 'protected_user' using errcode = '42501';
  end if;
  if target_role = 'admin' and actor_role <> 'superadmin' then
    raise exception 'protected_user' using errcode = '42501';
  end if;
  return target_role;
end;
$$;

-- Aprobar o rechazar a un cuidador en revisión. Rechazar = suspender la cuenta.
-- Aprobar es verificar. (La sección 11 la reemplaza: solo el admin del caso.)
create function public.admin_set_sitter_approval(target uuid, approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.user_role := private.assert_can_moderate(target);
begin
  if t <> 'sitter' then raise exception 'not_a_sitter' using errcode = '22023'; end if;
  update profiles
     set status = case when approve then 'approved' else 'suspended' end::public.user_status,
         verified = approve
   where id = target and status = 'pending_review';
  if not found then raise exception 'not_pending' using errcode = '22023'; end if;
  perform private.log_action(case when approve then 'approve_sitter' else 'reject_sitter' end, target);
end;
$$;

create function public.admin_set_user_suspended(target uuid, suspend boolean, reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.user_role := private.assert_can_moderate(target);
begin
  -- Reactivar a un cuidador lo deja aprobado, y aprobado es verificado.
  update profiles
     set status = case when suspend then 'suspended' else 'approved' end::public.user_status,
         verified = verified or (not suspend and t = 'sitter')
   where id = target;
  perform private.log_action(case when suspend then 'suspend_user' else 'reactivate_user' end,
                             target, jsonb_build_object('target_role', t, 'reason', reason));
end;
$$;

create function public.admin_resolve_report(
  report uuid,
  resolution public.report_status,
  suspend_reported boolean default false
)
returns void language plpgsql security definer set search_path = public as $$
declare
  reported uuid;
begin
  if not private.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if resolution = 'open' then raise exception 'invalid_resolution' using errcode = '22023'; end if;

  select reported_user_id into reported from reports where id = report and status = 'open';
  if reported is null then raise exception 'report_not_open' using errcode = '22023'; end if;

  if suspend_reported then
    perform private.assert_can_moderate(reported);
    update profiles set status = 'suspended' where id = reported;
  end if;

  update reports
     set status = resolution, reviewed_by = auth.uid(), reviewed_at = now()
   where id = report;
  perform private.log_action('resolve_report', reported,
          jsonb_build_object('report_id', report, 'resolution', resolution, 'suspended', suspend_reported));
end;
$$;

-- Búsqueda por nombre o correo (el correo vive en auth.users, que el cliente no lee).
create function public.admin_search_users(
  q text default null,
  p_role public.user_role default null,
  p_status public.user_status default null
)
returns table (id uuid, full_name text, email text, role public.user_role,
               status public.user_status, verified boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not private.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
    select p.id, p.full_name, u.email::text, p.role, p.status, p.verified
      from profiles p join auth.users u on u.id = p.id
     where (q is null or q = '' or p.full_name ilike '%' || q || '%' or u.email ilike '%' || q || '%')
       and (p_role is null or p.role = p_role)
       and (p_status is null or p.status = p_status)
     order by p.created_at desc
     limit 50;
end;
$$;

-- Cambio dueño <-> cuidador desde ajustes; bloqueado con reservas activas.
create function public.switch_role(new_role public.user_role)
returns void language plpgsql security definer set search_path = public as $$
declare
  me profiles%rowtype;
begin
  select * into me from profiles where id = auth.uid();
  if me.id is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if me.status = 'suspended' then raise exception 'account_suspended' using errcode = '42501'; end if;
  if me.role not in ('owner', 'sitter') or new_role not in ('owner', 'sitter') then
    raise exception 'role_not_switchable' using errcode = '42501';
  end if;
  if private.has_active_bookings(me.id) then
    raise exception 'active_bookings' using errcode = '22023';
  end if;
  update profiles
     set role = new_role,
         status = case when new_role = 'sitter' and not me.verified
                       then 'pending_review' else 'approved' end::public.user_status
   where id = me.id;
end;
$$;

-- Solo el superadmin gobierna al equipo.
create function public.superadmin_set_admin(target uuid, make_admin boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.user_role;
begin
  if not private.is_superadmin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if target = auth.uid() then raise exception 'cannot_target_self' using errcode = '42501'; end if;
  select role into t from profiles where id = target;
  if t is null then raise exception 'user_not_found' using errcode = 'P0002'; end if;
  if t = 'superadmin' then raise exception 'protected_user' using errcode = '42501'; end if;

  if make_admin then
    if t = 'admin' then return; end if;
    if private.has_active_bookings(target) then
      raise exception 'active_bookings' using errcode = '22023';
    end if;
    update profiles set role = 'admin', status = 'approved' where id = target;
    perform private.log_action('promote_admin', target, jsonb_build_object('from_role', t));
  else
    if t <> 'admin' then raise exception 'not_an_admin' using errcode = '22023'; end if;
    update profiles set role = 'owner', status = 'approved' where id = target;
    perform private.log_action('revoke_admin', target);
  end if;
end;
$$;

create function public.superadmin_delete_user(target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  t    public.user_role;
  name text;
begin
  if not private.is_superadmin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if target = auth.uid() then raise exception 'cannot_target_self' using errcode = '42501'; end if;
  select role, full_name into t, name from profiles where id = target;
  if t is null then raise exception 'user_not_found' using errcode = 'P0002'; end if;
  if t = 'superadmin' then raise exception 'protected_user' using errcode = '42501'; end if;
  -- La otra parte de una reserva en curso perdería la reserva sin aviso.
  if private.has_active_bookings(target) then
    raise exception 'active_bookings' using errcode = '22023';
  end if;
  -- El nombre queda en la auditoría: el perfil desaparece con la cuenta.
  perform private.log_action('delete_user', target,
          jsonb_build_object('target_role', t, 'target_name', name));
  delete from auth.users where id = target;
end;
$$;

-- Vence las solicitudes que el cuidador no respondió a tiempo. La ejecuta
-- pg_cron cada minuto (abajo); la app además muestra como vencida cualquier
-- solicitud `pending` con el plazo pasado, sin esperar al cron.
create function public.expire_overdue_bookings()
returns integer language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  update bookings set status = 'expired'
   where status = 'pending' and response_deadline <= now();
  get diagnostics n = row_count;
  return n;
end;
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('doggo-expire-bookings', '* * * * *', 'select public.expire_overdue_bookings()');
  else
    raise notice 'pg_cron no está disponible: activa la extensión en Supabase (Database -> Extensions) y vuelve a correr este bloque.';
  end if;
exception when others then
  raise notice 'No se pudo programar el vencimiento automático: %', sqlerrm;
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. Realtime: bookings
--    REPLICA IDENTITY FULL para que los UPDATE lleven la fila completa y los
--    filtros por owner_id / sitter_id funcionen en el cliente.
-- -----------------------------------------------------------------------------
alter table public.bookings replica identity full;
alter publication supabase_realtime add table public.bookings;

-- -----------------------------------------------------------------------------
-- 9. Storage: fotos de perfil (máx. 2 MB, solo imágenes, en la carpeta del usuario)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy avatars_read on storage.objects for select
  using (bucket_id = 'avatars');
create policy avatars_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update_own on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- -----------------------------------------------------------------------------
-- 10. Permisos
--     Supabase concede ALL por defecto a anon/authenticated; se revoca todo y se
--     concede lo mínimo, con permisos por COLUMNA donde importa. RLS filtra filas
--     y los GRANT filtran columnas: son dos barreras independientes.
-- -----------------------------------------------------------------------------
grant usage on schema public  to anon, authenticated;
grant usage on schema private to anon, authenticated;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- Público (anon): lo mismo que ve cualquiera en el mapa.
grant select (id, role, full_name, avatar_url, bio, approx_lat, approx_lng,
              radius_km, neighborhood, status, verified)
  on public.profiles to anon;
grant select on public.sitter_services, public.reviews, public.sitter_rating_stats,
                public.sitter_availability to anon;

-- Autenticados.
grant select on public.profiles, public.profile_private, public.dogs, public.dog_notes,
                public.sitter_services, public.bookings, public.reviews, public.reports,
                public.admin_actions, public.sitter_rating_stats, public.sitter_availability
  to authenticated;
grant update (full_name, avatar_url, bio, radius_km, neighborhood) on public.profiles to authenticated;
grant update (phone, exact_lat, exact_lng, address) on public.profile_private to authenticated;
grant insert, update, delete on public.dogs, public.dog_notes, public.sitter_services,
                               public.sitter_availability to authenticated;
grant insert on public.bookings, public.reviews, public.reports to authenticated;
grant update (status) on public.bookings to authenticated;

-- RPC: solo usuarios con sesión (cada una valida además el rol por dentro).
grant execute on function
  public.admin_set_sitter_approval(uuid, boolean),
  public.admin_set_user_suspended(uuid, boolean, text),
  public.admin_resolve_report(uuid, public.report_status, boolean),
  public.admin_search_users(text, public.user_role, public.user_status),
  public.switch_role(public.user_role),
  public.superadmin_set_admin(uuid, boolean),
  public.superadmin_delete_user(uuid)
  to authenticated;

-- Los helpers de `private` se evalúan dentro de políticas y CHECK, así que
-- necesitan EXECUTE (por defecto lo tiene PUBLIC); no se exponen por la API.

-- -----------------------------------------------------------------------------
-- 11. Fase 13: casos de verificación de cuidadores
--
--     Cada cuidador nuevo (en revisión) abre un CASO que se reparte solo al
--     admin con menos casos abiertos. Ese admin agenda una reunión virtual
--     inicial, la marca como hecha y decide. El cuidador puede subir, si
--     quiere, certificados (opcionales) a un bucket PRIVADO.
--
--     Proyecto existente: este bloque es también
--     supabase/migrations/2026-11-11_fase13_casos_cuidador.sql; córrelo UNA vez
--     en el SQL Editor. Proyecto nuevo: ya va incluido en schema.sql.
-- -----------------------------------------------------------------------------

create type public.case_stage      as enum ('new', 'meeting_scheduled', 'meeting_done');
create type public.sitter_doc_kind as enum ('certificate', 'first_aid', 'id_document', 'other');

-- Un caso por cuidador en revisión. Desaparece al aprobarlo o rechazarlo (la
-- decisión queda en admin_actions).
create table public.sitter_cases (
  sitter_id         uuid primary key references public.profiles (id) on delete cascade,
  assigned_admin    uuid references public.profiles (id) on delete set null,
  stage             public.case_stage not null default 'new',
  meeting_at        timestamptz,
  -- Reunión virtual: enlace https de Meet, Zoom, Teams, WhatsApp…
  meeting_link      text check (meeting_link is null
                                or (meeting_link ~ '^https://\S+$' and char_length(meeting_link) <= 300)),
  meeting_confirmed boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index sitter_cases_admin_idx on public.sitter_cases (assigned_admin);

-- Certificados que sube el cuidador (opcionales). El archivo vive en el bucket
-- `sitter-docs`, dentro de la carpeta del cuidador.
create table public.sitter_documents (
  id           uuid primary key default gen_random_uuid(),
  sitter_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  kind         public.sitter_doc_kind not null,
  file_name    text not null check (char_length(file_name) between 1 and 120),
  storage_path text not null unique,
  size_bytes   integer not null check (size_bytes between 1 and 10485760),
  created_at   timestamptz not null default now(),
  constraint sitter_documents_own_folder check (storage_path like sitter_id::text || '/%')
);
create index sitter_documents_sitter_idx on public.sitter_documents (sitter_id, created_at);

-- Reparte los casos sin admin: cada uno va al admin aprobado con menos casos
-- abiertos (empate: el más antiguo). El superadmin solo recibe casos si no hay
-- ningún admin.
create function private.assign_open_cases()
returns void language plpgsql security definer set search_path = public as $$
declare
  c    record;
  pick uuid;
begin
  for c in select sitter_id from sitter_cases where assigned_admin is null order by created_at loop
    select p.id into pick
      from profiles p
     where p.role in ('admin', 'superadmin') and p.status = 'approved'
     order by (p.role = 'superadmin'),
              (select count(*) from sitter_cases sc where sc.assigned_admin = p.id),
              p.created_at, p.id
     limit 1;
    exit when pick is null;
    update sitter_cases set assigned_admin = pick, updated_at = now() where sitter_id = c.sitter_id;
  end loop;
end;
$$;

-- Mantiene los casos al día con los perfiles, venga el cambio de donde venga
-- (registro, cambio de rol, aprobación, assign_roles.sql, eliminar cuenta):
--   * cuidador que entra en revisión  -> abre caso y lo reparte;
--   * cuidador que sale de revisión   -> cierra su caso;
--   * admin que deja de serlo         -> sus casos se reparten entre los demás;
--   * admin nuevo                     -> recibe los casos que estaban sin admin
--                                        (y los que el superadmin guardaba sin empezar).
create function private.sync_sitter_cases()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  was_pending boolean := false;
  is_pending  boolean := false;
  was_admin   boolean := false;
  is_admin    boolean := false;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    was_pending := old.role = 'sitter' and old.status = 'pending_review';
    was_admin   := old.role in ('admin', 'superadmin') and old.status = 'approved';
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    is_pending := new.role = 'sitter' and new.status = 'pending_review';
    is_admin   := new.role in ('admin', 'superadmin') and new.status = 'approved';
  end if;

  if is_pending and not was_pending then
    insert into sitter_cases (sitter_id) values (new.id) on conflict (sitter_id) do nothing;
  elsif was_pending and not is_pending and tg_op = 'UPDATE' then
    delete from sitter_cases where sitter_id = new.id;
  end if;

  if was_admin and not is_admin then
    update sitter_cases set assigned_admin = null, updated_at = now() where assigned_admin = old.id;
  end if;

  -- El superadmin solo guarda casos mientras no hay admins: al llegar uno, los
  -- que aún no empezó (sin reunión) se reparten.
  if is_admin and not was_admin and new.role = 'admin' then
    update sitter_cases set assigned_admin = null, updated_at = now()
     where stage = 'new'
       and assigned_admin in (select id from profiles where role = 'superadmin');
  end if;

  if (is_pending and not was_pending) or (was_admin <> is_admin) then
    perform private.assign_open_cases();
  end if;
  return null;
end;
$$;

create trigger profiles_sync_sitter_cases
  after insert or update of role, status or delete on public.profiles
  for each row execute function private.sync_sitter_cases();

-- Máximo 10 documentos por cuidador.
create function private.limit_sitter_documents()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from sitter_documents where sitter_id = new.sitter_id) >= 10 then
    raise exception 'too_many_documents' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger sitter_documents_limit
  before insert on public.sitter_documents
  for each row execute function private.limit_sitter_documents();

-- ¿Es `admin` quien lleva el caso del cuidador que llama? (para mostrarle su nombre)
create function private.is_my_case_admin(admin uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from sitter_cases where sitter_id = auth.uid() and assigned_admin = admin);
$$;

-- Solo el admin del caso (o el superadmin) puede actuar sobre él.
create function private.assert_case_handler(target uuid)
returns void language plpgsql stable security definer set search_path = public as $$
declare
  handler uuid;
begin
  if not private.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select assigned_admin into handler from sitter_cases where sitter_id = target;
  if not found then raise exception 'case_not_found' using errcode = 'P0002'; end if;
  if handler is distinct from auth.uid() and not private.is_superadmin() then
    raise exception 'not_your_case' using errcode = '42501';
  end if;
end;
$$;

-- RLS
alter table public.sitter_cases     enable row level security;
alter table public.sitter_documents enable row level security;

create policy sitter_cases_select on public.sitter_cases for select using (
  sitter_id = auth.uid() or private.is_admin()
);

create policy sitter_documents_select on public.sitter_documents for select using (
  sitter_id = auth.uid() or private.is_admin()
);
create policy sitter_documents_insert_own on public.sitter_documents for insert
  with check (sitter_id = auth.uid() and private.has_role(auth.uid(), 'sitter'));
create policy sitter_documents_delete_own on public.sitter_documents for delete
  using (sitter_id = auth.uid());

-- El cuidador en revisión ve el perfil (nombre) del admin que lleva su caso.
create policy profiles_select_case_admin on public.profiles for select using (
  private.is_my_case_admin(id)
);

-- RPC
-- Aprobar o rechazar: igual que antes, pero solo el admin del caso o el superadmin.
create or replace function public.admin_set_sitter_approval(target uuid, approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.user_role := private.assert_can_moderate(target);
begin
  if t <> 'sitter' then raise exception 'not_a_sitter' using errcode = '22023'; end if;
  if exists (select 1 from sitter_cases where sitter_id = target) then
    perform private.assert_case_handler(target);
  end if;
  update profiles
     set status = case when approve then 'approved' else 'suspended' end::public.user_status,
         verified = approve
   where id = target and status = 'pending_review';
  if not found then raise exception 'not_pending' using errcode = '22023'; end if;
  perform private.log_action(case when approve then 'approve_sitter' else 'reject_sitter' end, target);
end;
$$;

-- Agenda (o cambia) la reunión virtual inicial.
create function public.admin_schedule_meeting(target uuid, p_meeting_at timestamptz, p_link text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform private.assert_case_handler(target);
  if p_meeting_at is null or p_meeting_at <= now() then
    raise exception 'meeting_in_past' using errcode = '22023';
  end if;
  if p_meeting_at > now() + interval '90 days' then
    raise exception 'meeting_too_far' using errcode = '22023';
  end if;
  if p_link is null or btrim(p_link) !~ '^https://\S+$' or char_length(btrim(p_link)) > 300 then
    raise exception 'invalid_meeting_link' using errcode = '22023';
  end if;
  update sitter_cases
     set stage = 'meeting_scheduled', meeting_at = p_meeting_at, meeting_link = btrim(p_link),
         meeting_confirmed = false, updated_at = now()
   where sitter_id = target;
  perform private.log_action('schedule_meeting', target, jsonb_build_object('meeting_at', p_meeting_at));
end;
$$;

create function public.admin_mark_meeting_done(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform private.assert_case_handler(target);
  update sitter_cases set stage = 'meeting_done', updated_at = now()
   where sitter_id = target and stage = 'meeting_scheduled';
  if not found then raise exception 'no_meeting' using errcode = '22023'; end if;
  perform private.log_action('meeting_done', target);
end;
$$;

-- Un caso que quedó sin admin (p. ej. no había ninguno) lo puede tomar cualquiera.
create function public.admin_take_case(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not private.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  update sitter_cases set assigned_admin = auth.uid(), updated_at = now()
   where sitter_id = target and assigned_admin is null;
  if not found then raise exception 'case_taken' using errcode = '22023'; end if;
  perform private.log_action('take_case', target);
end;
$$;

create function public.superadmin_reassign_case(target uuid, new_admin uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  name text;
begin
  if not private.is_superadmin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select full_name into name from profiles
   where id = new_admin and role in ('admin', 'superadmin') and status = 'approved';
  if not found then raise exception 'not_an_admin' using errcode = '22023'; end if;
  update sitter_cases set assigned_admin = new_admin, updated_at = now() where sitter_id = target;
  if not found then raise exception 'case_not_found' using errcode = 'P0002'; end if;
  perform private.log_action('reassign_case', target, jsonb_build_object('to_name', name));
end;
$$;

-- El cuidador confirma que asistirá a la reunión.
create function public.sitter_confirm_meeting()
returns void language plpgsql security definer set search_path = public as $$
begin
  update sitter_cases set meeting_confirmed = true, updated_at = now()
   where sitter_id = auth.uid() and stage = 'meeting_scheduled';
  if not found then raise exception 'no_meeting' using errcode = '22023'; end if;
end;
$$;

-- Realtime: el cuidador ve aparecer su reunión y el admin sus casos nuevos.
alter table public.sitter_cases replica identity full;
alter publication supabase_realtime add table public.sitter_cases;

-- Storage: certificados (privado, máx. 10 MB, PDF o imagen, carpeta del cuidador).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sitter-docs', 'sitter-docs', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy sitter_docs_read on storage.objects for select to authenticated
  using (bucket_id = 'sitter-docs'
         and ((storage.foldername(name))[1] = auth.uid()::text or private.is_admin()));
create policy sitter_docs_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'sitter-docs'
              and (storage.foldername(name))[1] = auth.uid()::text
              and private.has_role(auth.uid(), 'sitter'));
create policy sitter_docs_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'sitter-docs' and (storage.foldername(name))[1] = auth.uid()::text);

-- Permisos (los objetos nuevos nacen con los permisos por defecto de Supabase).
revoke all on public.sitter_cases, public.sitter_documents from anon, authenticated;
grant select on public.sitter_cases to authenticated;
grant select, delete on public.sitter_documents to authenticated;
grant insert (kind, file_name, storage_path, size_bytes) on public.sitter_documents to authenticated;

revoke all on function
  public.admin_schedule_meeting(uuid, timestamptz, text),
  public.admin_mark_meeting_done(uuid),
  public.admin_take_case(uuid),
  public.superadmin_reassign_case(uuid, uuid),
  public.sitter_confirm_meeting()
  from public, anon, authenticated;
grant execute on function
  public.admin_schedule_meeting(uuid, timestamptz, text),
  public.admin_mark_meeting_done(uuid),
  public.admin_take_case(uuid),
  public.superadmin_reassign_case(uuid, uuid),
  public.sitter_confirm_meeting()
  to authenticated;

-- Cuidadores que ya estaban en revisión antes de esta fase.
insert into public.sitter_cases (sitter_id)
select id from public.profiles where role = 'sitter' and status = 'pending_review'
on conflict (sitter_id) do nothing;
select private.assign_open_cases();
