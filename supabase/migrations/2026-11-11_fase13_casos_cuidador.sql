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
