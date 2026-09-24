-- ═══════════════════════════════════════════════════════════════
--  TALLER · Base de datos para Supabase
--  Pega todo este archivo en Supabase → SQL Editor → Run.
--  Se puede ejecutar más de una vez sin romper nada.
-- ═══════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

-- ─────────────── Tablas ───────────────
create table if not exists public.ajustes(
  id int primary key default 1 check (id = 1),
  registro_abierto boolean not null default true);
insert into public.ajustes(id, registro_abierto) values (1, true) on conflict (id) do nothing;

create table if not exists public.talleres(
  id bigint generated always as identity primary key,
  nombre text not null,
  logo text,            -- imagen en base64, lo sube el personal de oficina
  direccion text, telefono text, email text, cif text,
  creado timestamptz not null default now());
alter table public.talleres add column if not exists logo text;
alter table public.talleres add column if not exists direccion text;
alter table public.talleres add column if not exists telefono text;
alter table public.talleres add column if not exists email text;
alter table public.talleres add column if not exists cif text;

create table if not exists public.perfiles(
  id uuid primary key references auth.users(id) on delete cascade,
  taller_id bigint not null references public.talleres(id),
  nombre text not null,
  usuario text not null unique,
  rol text not null check (rol in ('admin','mecanico')),
  activo boolean not null default true,
  creado timestamptz not null default now());

create table if not exists public.coches(
  id bigint generated always as identity primary key,
  taller_id bigint not null references public.talleres(id),
  matricula text not null, marca text not null, modelo text not null,
  anio int, color text not null default '#3A6EA5',
  carroceria text not null default 'berlina',
  km int, vin text, notas text,
  creado timestamptz not null default now(),
  unique (taller_id, matricula));

create table if not exists public.ordenes(
  id bigint generated always as identity primary key,
  taller_id bigint not null references public.talleres(id),
  coche_id bigint not null references public.coches(id),
  tipo_revision text not null,
  tipo_checklist text not null check (tipo_checklist in ('basico','completo')),
  notas text,
  estado text not null default 'abierta' check (estado in ('abierta','finalizada','cancelada')),
  seg_consumidos numeric not null default 0,   -- saldo del mecánico que lleva la cuenta (puede ser negativo)
  seg_tarea numeric not null default 0,        -- tiempo dedicado a la reparación en curso
  cuenta_mecanico uuid references public.perfiles(id),
  seg_totales numeric not null default 0,      -- tiempo real total del coche
  en_marcha_desde timestamptz,
  creado timestamptz not null default now(),
  cerrado timestamptz);
alter table public.ordenes add column if not exists seg_consumidos numeric not null default 0;
alter table public.ordenes add column if not exists seg_totales numeric not null default 0;
alter table public.ordenes add column if not exists seg_tarea numeric not null default 0;
alter table public.ordenes add column if not exists cuenta_mecanico uuid references public.perfiles(id);
alter table public.ordenes add column if not exists en_marcha_desde timestamptz;

create table if not exists public.checklists(
  orden_id bigint not null references public.ordenes(id) on delete cascade,
  tipo text not null default 'inicial' check (tipo in ('inicial','final')),
  taller_id bigint not null references public.talleres(id),
  realizado_por uuid not null references public.perfiles(id),
  datos jsonb not null,
  creado timestamptz not null default now(),
  modificado timestamptz,
  modificado_por uuid references public.perfiles(id),
  primary key (orden_id, tipo));
alter table public.checklists add column if not exists tipo text not null default 'inicial';
do $$
declare n int;
begin
  select count(*) into n from pg_index i, unnest(i.indkey) k
   where i.indrelid = 'public.checklists'::regclass and i.indisprimary;
  if n = 1 then
    alter table public.checklists drop constraint checklists_pkey;
    alter table public.checklists add primary key (orden_id, tipo);
  end if;
end $$;

create table if not exists public.tareas(
  id bigint generated always as identity primary key,
  orden_id bigint not null references public.ordenes(id) on delete cascade,
  taller_id bigint not null references public.talleres(id),
  titulo text not null, descripcion text,
  seg_asignados int not null check (seg_asignados > 0),
  estado text not null default 'pendiente' check (estado in ('pendiente','finalizada')),
  pos int not null default 0,
  finalizada timestamptz,
  finalizada_por uuid references public.perfiles(id),
  seg_reales numeric);
alter table public.tareas add column if not exists finalizada_por uuid references public.perfiles(id);
alter table public.tareas add column if not exists seg_reales numeric;
alter table public.tareas drop column if exists seg_consumidos;
alter table public.tareas drop column if exists en_marcha_desde;
update public.tareas set estado = 'pendiente' where estado not in ('pendiente','finalizada');
alter table public.tareas drop constraint if exists tareas_estado_check;
alter table public.tareas add constraint tareas_estado_check check (estado in ('pendiente','finalizada'));

create table if not exists public.tarea_mecanicos(
  tarea_id bigint not null references public.tareas(id) on delete cascade,
  mecanico_id uuid not null references public.perfiles(id),
  taller_id bigint not null references public.talleres(id),
  primary key (tarea_id, mecanico_id));

drop table if exists public.tarea_sesiones cascade;

create table if not exists public.orden_sesiones(
  id bigint generated always as identity primary key,
  orden_id bigint not null references public.ordenes(id) on delete cascade,
  taller_id bigint not null references public.talleres(id),
  mecanico_id uuid not null references public.perfiles(id),
  inicio timestamptz not null default now(),
  fin timestamptz,
  motivo text check (motivo in ('finalizada','fin_turno','cerrada_admin')),
  nota text,
  relevo_id uuid references public.perfiles(id));

create table if not exists public.avisos(
  id bigint generated always as identity primary key,
  taller_id bigint not null references public.talleres(id),
  orden_id bigint not null references public.ordenes(id) on delete cascade,
  tarea_id bigint references public.tareas(id) on delete set null,
  mecanico_id uuid not null references public.perfiles(id),
  tipo text not null check (tipo in ('incidencia','nota','fin_turno','tarea','fin_trabajo')),
  texto text not null,
  fotos jsonb not null default '[]'::jsonb,
  creado timestamptz not null default now(),
  leido timestamptz,
  leido_por uuid references public.perfiles(id));
create index if not exists ix_avisos_taller on public.avisos(taller_id, leido);
alter table public.avisos add column if not exists fotos jsonb not null default '[]'::jsonb;
alter table public.avisos drop constraint if exists avisos_tipo_check;
alter table public.avisos add constraint avisos_tipo_check
  check (tipo in ('incidencia','nota','fin_turno','tarea','fin_trabajo'));

create table if not exists public.fichajes(
  id bigint generated always as identity primary key,
  taller_id bigint not null references public.talleres(id),
  mecanico_id uuid not null references public.perfiles(id),
  tipo text not null check (tipo in ('entrada','descanso','vuelta','fin')),
  momento timestamptz not null default now());
create index if not exists ix_fichajes on public.fichajes(taller_id, mecanico_id, momento);

create table if not exists public.turnos_plantilla(
  id bigint generated always as identity primary key,
  taller_id bigint not null references public.talleres(id),
  nombre text not null,
  hora_inicio time not null,
  hora_fin time not null,
  creado timestamptz not null default now());

create table if not exists public.turnos(
  id bigint generated always as identity primary key,
  taller_id bigint not null references public.talleres(id),
  mecanico_id uuid not null references public.perfiles(id),
  inicio timestamptz not null,
  fin timestamptz not null,
  comentario text,
  creado timestamptz not null default now());
create index if not exists ix_turnos on public.turnos(taller_id, inicio);
create index if not exists ix_turnos_mec on public.turnos(mecanico_id, inicio);

-- Un mecánico solo puede estar trabajando en un coche a la vez
create unique index if not exists un_coche_a_la_vez on public.orden_sesiones(mecanico_id) where fin is null;
create index if not exists ix_tareas_orden on public.tareas(orden_id);
create index if not exists ix_tm_mecanico on public.tarea_mecanicos(mecanico_id);
create index if not exists ix_ses_orden on public.orden_sesiones(orden_id);

-- ─────────────── Funciones de apoyo ───────────────
create or replace function public.mi_taller() returns bigint
language sql stable security definer set search_path = public as $$
  select taller_id from perfiles where id = auth.uid() and activo
$$;

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select rol = 'admin' from perfiles where id = auth.uid() and activo), false)
$$;

create or replace function public.tarea_mia(p bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from tarea_mecanicos where tarea_id = p and mecanico_id = auth.uid())
$$;

create or replace function public.orden_mia(p bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from tareas t join tarea_mecanicos tm on tm.tarea_id = t.id
                where t.orden_id = p and tm.mecanico_id = auth.uid())
$$;

create or replace function public.tarea_de_orden_mia(p bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from tareas t where t.id = p and public.orden_mia(t.orden_id))
$$;

create or replace function public.coche_mio(p bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from ordenes o where o.coche_id = p and public.orden_mia(o.id))
$$;

create or replace function public.seg_checklists() returns int
language sql immutable as $$ select 12 * 60 $$;   -- 12 minutos por los dos checklists

create or replace function public.ahora() returns timestamptz
language sql stable as $$ select now() $$;

create or replace function public.plantillas() returns jsonb
language sql immutable as $$
  -- "basico" y "completo" apuntan al mismo checklist de entrada, para que las órdenes
  -- antiguas sigan viéndose bien. El de entrada y el control final son los que se usan.
  select jsonb_build_object('inicial', v, 'basico', v, 'completo', v, 'final', f)
  from (select '[
      {"id":"b1","texto":"Nivel de aceite del motor"},
      {"id":"b2","texto":"Líquido refrigerante"},
      {"id":"b3","texto":"Líquido de frenos"},
      {"id":"b5","texto":"Luces exteriores"},
      {"id":"b6","texto":"Limpiaparabrisas y líquido"},
      {"id":"b7","texto":"Batería y bornes"},
      {"id":"b8","texto":"Testigos del cuadro"},
      {"id":"c1","texto":"Desgaste de neumáticos"},
      {"id":"c2","texto":"Pastillas y discos de freno"},
      {"id":"c3","texto":"Suspensión y amortiguadores"},
      {"id":"c4","texto":"Dirección y rótulas"},
      {"id":"c5","texto":"Correa de accesorios"},
      {"id":"c6","texto":"Sistema de escape"},
      {"id":"c7","texto":"Fugas bajo el vehículo"}]'::jsonb as v,
    '[
      {"id":"f1","texto":"Nivel de aceite"},
      {"id":"f2","texto":"Tapón y filtro"},
      {"id":"f3","texto":"Sin fugas"},
      {"id":"f4","texto":"Niveles finales"},
      {"id":"f5","texto":"Presiones"},
      {"id":"f6","texto":"Tapas y protecciones"},
      {"id":"f7","texto":"Avisos del cuadro"},
      {"id":"f8","texto":"Servicio reseteado si procede"},
      {"id":"f9","texto":"Apriete de ruedas si se desmontaron"},
      {"id":"f10","texto":"Vehículo listo"}]'::jsonb as f) z
$$;

create or replace function public._yo() returns public.perfiles
language plpgsql stable security definer set search_path = public as $$
declare p perfiles;
begin
  select * into p from perfiles where id = auth.uid() and activo;
  if not found then raise exception 'Inicia sesión con un usuario activo'; end if;
  return p;
end $$;

create or replace function public._admin() returns bigint
language plpgsql stable security definer set search_path = public as $$
declare t bigint;
begin
  select taller_id into t from perfiles where id = auth.uid() and activo and rol = 'admin';
  if t is null then raise exception 'Solo el personal de oficina puede hacer esto'; end if;
  return t;
end $$;

-- ─────────────── Seguridad por filas (solo lectura) ───────────────
-- Todas las escrituras pasan por las funciones de abajo, que aplican las reglas.
alter table public.ajustes         enable row level security;
alter table public.talleres        enable row level security;
alter table public.perfiles        enable row level security;
alter table public.coches          enable row level security;
alter table public.ordenes         enable row level security;
alter table public.checklists      enable row level security;
alter table public.tareas          enable row level security;
alter table public.tarea_mecanicos enable row level security;
alter table public.orden_sesiones  enable row level security;
alter table public.avisos          enable row level security;
alter table public.fichajes        enable row level security;
alter table public.turnos          enable row level security;
alter table public.turnos_plantilla enable row level security;

drop policy if exists leer on public.talleres;
create policy leer on public.talleres for select to authenticated using (id = public.mi_taller());
drop policy if exists leer on public.perfiles;
create policy leer on public.perfiles for select to authenticated using (taller_id = public.mi_taller());
drop policy if exists leer on public.coches;
create policy leer on public.coches for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or public.coche_mio(id)));
drop policy if exists leer on public.ordenes;
create policy leer on public.ordenes for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or public.orden_mia(id)));
drop policy if exists leer on public.checklists;
create policy leer on public.checklists for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or public.orden_mia(orden_id)));
drop policy if exists leer on public.tareas;
create policy leer on public.tareas for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or public.orden_mia(orden_id)));
drop policy if exists leer on public.tarea_mecanicos;
create policy leer on public.tarea_mecanicos for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or public.tarea_de_orden_mia(tarea_id)));
drop policy if exists leer on public.turnos;
create policy leer on public.turnos for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or mecanico_id = auth.uid()));
drop policy if exists leer on public.turnos_plantilla;
create policy leer on public.turnos_plantilla for select to authenticated
  using (taller_id = public.mi_taller());

drop policy if exists leer on public.fichajes;
create policy leer on public.fichajes for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or mecanico_id = auth.uid()));

drop policy if exists leer on public.avisos;
create policy leer on public.avisos for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or mecanico_id = auth.uid()));

drop policy if exists leer on public.orden_sesiones;
create policy leer on public.orden_sesiones for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or public.orden_mia(orden_id)));

revoke insert, update, delete on all tables in schema public from anon, authenticated;

-- ─────────────── Usuarios ───────────────
create or replace function public.crear_taller(p_taller text, p_nombre text) returns bigint
language plpgsql security definer set search_path = public as $$
declare t bigint; v_email text;
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  if not (select registro_abierto from ajustes where id = 1) then
    raise exception 'El registro de talleres está cerrado'; end if;
  if exists(select 1 from perfiles where id = auth.uid()) then
    raise exception 'Este usuario ya pertenece a un taller'; end if;
  if length(trim(coalesce(p_taller,''))) < 2 or length(trim(coalesce(p_nombre,''))) < 2 then
    raise exception 'Escribe el nombre del taller y tu nombre'; end if;
  select email into v_email from auth.users where id = auth.uid();
  insert into talleres(nombre) values (trim(p_taller)) returning id into t;
  insert into perfiles(id, taller_id, nombre, usuario, rol)
    values (auth.uid(), t, trim(p_nombre), split_part(v_email, '@', 1), 'admin');
  return t;
exception when unique_violation then
  raise exception 'Ese usuario ya existe';
end $$;

create or replace function public.vincular_mecanico(p_user uuid, p_nombre text) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_email text; v_creado timestamptz;
begin
  if length(trim(coalesce(p_nombre,''))) < 2 then raise exception 'Escribe el nombre del mecánico'; end if;
  select email, created_at into v_email, v_creado from auth.users where id = p_user;
  if not found then raise exception 'Usuario no encontrado'; end if;
  if v_creado < now() - interval '15 minutes' or exists(select 1 from perfiles where id = p_user) then
    raise exception 'Ese usuario ya existe'; end if;
  insert into perfiles(id, taller_id, nombre, usuario, rol)
    values (p_user, t, trim(p_nombre), split_part(v_email, '@', 1), 'mecanico');
exception when unique_violation then
  raise exception 'Ese usuario ya existe';
end $$;

create or replace function public.editar_mecanico(p_id uuid, p_nombre text, p_activo boolean, p_password text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare t bigint := public._admin();
begin
  if length(trim(coalesce(p_nombre,''))) < 2 then raise exception 'Escribe el nombre del mecánico'; end if;
  update perfiles set nombre = trim(p_nombre), activo = p_activo
   where id = p_id and taller_id = t and rol = 'mecanico';
  if not found then raise exception 'Mecánico no encontrado'; end if;
  if coalesce(p_password, '') <> '' then
    if length(p_password) < 6 then raise exception 'La contraseña debe tener al menos 6 caracteres'; end if;
    update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
                          updated_at = now()
     where id = p_id;
  end if;
  if coalesce(p_password, '') <> '' or not p_activo then
    begin
      delete from auth.sessions where user_id = p_id;   -- cierra sus sesiones abiertas
    exception when others then null;
    end;
  end if;
end $$;

create or replace function public.guardar_taller(p_nombre text, p_logo text default null,
        p_direccion text default null, p_telefono text default null,
        p_email text default null, p_cif text default null, p_borrar_logo boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin();
begin
  if length(trim(coalesce(p_nombre,''))) < 2 then raise exception 'Escribe el nombre del taller'; end if;
  if p_logo is not null and length(p_logo) > 400000 then
    raise exception 'El logo pesa demasiado. Usa una imagen más pequeña'; end if;
  update talleres set nombre = trim(p_nombre),
                      direccion = nullif(trim(coalesce(p_direccion,'')),''),
                      telefono  = nullif(trim(coalesce(p_telefono,'')),''),
                      email     = nullif(trim(coalesce(p_email,'')),''),
                      cif       = nullif(trim(coalesce(p_cif,'')),''),
                      logo = case when p_borrar_logo then null when p_logo is not null then p_logo else logo end
   where id = t;
end $$;

-- ─────────────── Fotos de los checklists ───────────────
-- Las fotos se guardan en Storage. Cada taller solo entra en su carpeta.
do $$
begin
  insert into storage.buckets (id, name, public) values ('fotos', 'fotos', false) on conflict (id) do nothing;
exception when others then
  raise notice 'No se pudo crear el bucket. Créalo a mano en Storage, privado y con el nombre fotos';
end $$;

do $$
begin
  drop policy if exists "fotos del taller: leer" on storage.objects;
  drop policy if exists "fotos del taller: subir" on storage.objects;
  drop policy if exists "fotos del taller: borrar" on storage.objects;
  create policy "fotos del taller: leer" on storage.objects for select to authenticated
    using (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.mi_taller()::text);
  create policy "fotos del taller: subir" on storage.objects for insert to authenticated
    with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.mi_taller()::text);
  create policy "fotos del taller: borrar" on storage.objects for delete to authenticated
    using (bucket_id = 'fotos' and (storage.foldername(name))[1] = public.mi_taller()::text);
exception when others then
  raise notice 'No se pudieron crear las reglas de Storage: mira el README';
end $$;

-- ─────────────── Coches y órdenes ───────────────
create or replace function public.guardar_coche(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_id bigint; v_mat text;
begin
  v_mat := upper(regexp_replace(coalesce(p->>'matricula',''), '[\s-]', '', 'g'));
  if length(v_mat) < 2 or coalesce(trim(p->>'marca'),'') = '' or coalesce(trim(p->>'modelo'),'') = '' then
    raise exception 'Pon matrícula, marca y modelo'; end if;
  if coalesce(p->>'carroceria','berlina') not in ('berlina','hatchback','familiar','suv','coupe','furgoneta','pickup') then
    raise exception 'Tipo de carrocería no válido'; end if;
  if coalesce(p->>'color','#3A6EA5') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Color no válido'; end if;
  if p_id is null then
    insert into coches(taller_id, matricula, marca, modelo, anio, color, carroceria, km, vin, notas)
    values (t, v_mat, trim(p->>'marca'), trim(p->>'modelo'), nullif(p->>'anio','')::int,
            coalesce(p->>'color','#3A6EA5'), coalesce(p->>'carroceria','berlina'),
            nullif(p->>'km','')::numeric::int, nullif(trim(p->>'vin'),''), nullif(trim(p->>'notas'),''))
    returning id into v_id;
  else
    update coches set matricula = v_mat, marca = trim(p->>'marca'), modelo = trim(p->>'modelo'),
      anio = nullif(p->>'anio','')::int, color = coalesce(p->>'color','#3A6EA5'),
      carroceria = coalesce(p->>'carroceria','berlina'), km = nullif(p->>'km','')::numeric::int,
      vin = nullif(trim(p->>'vin'),''), notas = nullif(trim(p->>'notas'),'')
    where id = p_id and taller_id = t returning id into v_id;
    if v_id is null then raise exception 'Coche no encontrado'; end if;
  end if;
  return v_id;
exception when unique_violation then
  raise exception 'Ya hay un coche con esa matrícula';
end $$;

create or replace function public.guardar_tarea(p_id bigint, p_orden bigint, p_titulo text, p_descripcion text,
                                                p_minutos numeric, p_mecanicos uuid[]) returns bigint
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_id bigint;
begin
  if coalesce(trim(p_titulo),'') = '' then raise exception 'Cada reparación necesita un nombre'; end if;
  if coalesce(p_minutos, 0) <= 0 then raise exception 'Pon los minutos de «%»', p_titulo; end if;
  if coalesce(array_length(p_mecanicos, 1), 0) = 0 then
    raise exception 'Asigna al menos un mecánico a «%»', p_titulo; end if;
  if exists(select 1 from unnest(p_mecanicos) m
            where not exists(select 1 from perfiles where id = m and taller_id = t and rol = 'mecanico')) then
    raise exception 'Hay un mecánico que no pertenece a este taller'; end if;
  if p_id is null then
    if not exists(select 1 from ordenes where id = p_orden and taller_id = t) then
      raise exception 'Orden no encontrada'; end if;
    insert into tareas(orden_id, taller_id, titulo, descripcion, seg_asignados, pos)
    values (p_orden, t, trim(p_titulo), nullif(trim(p_descripcion),''), round(p_minutos * 60),
            (select coalesce(max(pos), -1) + 1 from tareas where orden_id = p_orden))
    returning id into v_id;
    update ordenes set estado = 'abierta', cerrado = null where id = p_orden and estado = 'finalizada';
  else
    update tareas set titulo = trim(p_titulo), descripcion = nullif(trim(p_descripcion),''),
                      seg_asignados = round(p_minutos * 60)
     where id = p_id and taller_id = t returning id into v_id;
    if v_id is null then raise exception 'Tarea no encontrada'; end if;
    delete from tarea_mecanicos where tarea_id = v_id;
  end if;
  insert into tarea_mecanicos(tarea_id, mecanico_id, taller_id)
  select distinct v_id, m, t from unnest(p_mecanicos) m;
  return v_id;
end $$;

create or replace function public.borrar_tarea(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin();
begin
  if exists(select 1 from tareas where id = p_id and estado = 'finalizada') then
    raise exception 'No se puede eliminar: ya está marcada como hecha'; end if;
  delete from tareas where id = p_id and taller_id = t;
  if not found then raise exception 'Tarea no encontrada'; end if;
end $$;

create or replace function public.crear_orden(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_coche bigint; v_orden bigint; x jsonb;
begin
  if coalesce(trim(p->>'tipo_revision'),'') = '' then raise exception 'Indica el tipo de revisión'; end if;
  if coalesce(p->>'tipo_checklist','completo') not in ('basico','completo') then raise exception 'Tipo de checklist no válido'; end if;
  if jsonb_array_length(coalesce(p->'tareas','[]'::jsonb)) = 0 then raise exception 'Añade al menos una reparación'; end if;
  if nullif(p->>'coche_id','') is not null then
    select id into v_coche from coches where id = (p->>'coche_id')::bigint and taller_id = t;
    if v_coche is null then raise exception 'Coche no encontrado'; end if;
  else
    v_coche := public.guardar_coche(null, p->'coche');
  end if;
  insert into ordenes(taller_id, coche_id, tipo_revision, tipo_checklist, notas)
  values (t, v_coche, trim(p->>'tipo_revision'), coalesce(p->>'tipo_checklist','completo'), nullif(trim(p->>'notas'),''))
  returning id into v_orden;
  for x in select * from jsonb_array_elements(p->'tareas') loop
    perform public.guardar_tarea(null, v_orden, x->>'titulo', x->>'descripcion', (x->>'minutos')::numeric,
      array(select jsonb_array_elements_text(coalesce(x->'mecanicos','[]'::jsonb))::uuid));
  end loop;
  return v_orden;
end $$;

create or replace function public.editar_orden(p_id bigint, p_tipo text, p_notas text) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin();
begin
  if coalesce(trim(p_tipo),'') = '' then raise exception 'Indica el tipo de revisión'; end if;
  update ordenes set tipo_revision = trim(p_tipo), notas = nullif(trim(p_notas),'')
   where id = p_id and taller_id = t;
  if not found then raise exception 'Orden no encontrada'; end if;
end $$;

create or replace function public.cambiar_estado_orden(p_id bigint, p_estado text) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); o ordenes;
begin
  if p_estado not in ('abierta','finalizada','cancelada') then raise exception 'Estado no válido'; end if;
  select * into o from ordenes where id = p_id and taller_id = t for update;
  if not found then raise exception 'Orden no encontrada'; end if;
  if p_estado = 'abierta' then
    update ordenes set estado = 'abierta', cerrado = null where id = p_id;
  else
    if o.en_marcha_desde is not null then
      update ordenes set seg_consumidos = o.seg_consumidos + extract(epoch from now() - o.en_marcha_desde),
                         seg_tarea = o.seg_tarea + extract(epoch from now() - o.en_marcha_desde),
                         seg_totales = o.seg_totales + extract(epoch from now() - o.en_marcha_desde),
                         en_marcha_desde = null where id = p_id;
    end if;
    update orden_sesiones set fin = now(), motivo = 'cerrada_admin' where orden_id = p_id and fin is null;
    update ordenes set estado = p_estado, cerrado = now() where id = p_id;
  end if;
end $$;

-- ─────────────── Checklist ───────────────
create or replace function public._validar_checklist(p_tipo text, p jsonb) returns jsonb
language plpgsql immutable as $$
declare it jsonb; v jsonb; items jsonb := '{}'::jsonb;
begin
  for it in select * from jsonb_array_elements(public.plantillas()->p_tipo) loop
    v := p->'items'->(it->>'id');
    if v is null or coalesce(v->>'estado','') not in ('ok','revisar','na') then
      raise exception 'Falta revisar: %', it->>'texto'; end if;
    items := items || jsonb_build_object(it->>'id',
      jsonb_build_object('estado', v->>'estado', 'nota', left(trim(coalesce(v->>'nota','')), 300),
        'fotos', coalesce((select jsonb_agg(f) from (
            select f from jsonb_array_elements_text(
              case when jsonb_typeof(v->'fotos') = 'array' then v->'fotos' else '[]'::jsonb end) f
            limit 6) z), '[]'::jsonb)));
  end loop;
  return jsonb_build_object('items', items,
    'km', case when jsonb_typeof(p->'km') = 'number' and (p->>'km')::numeric >= 0 then p->'km' end,
    'observaciones', left(trim(coalesce(p->>'observaciones','')), 1000));
end $$;

drop function if exists public.hacer_checklist(bigint, jsonb);
drop function if exists public.modificar_checklist(bigint, jsonb);

create or replace function public.hacer_checklist(p_orden bigint, p_datos jsonb, p_tipo text default 'inicial') returns void
language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); o ordenes; d jsonb; v_plantilla text;
begin
  if p_tipo not in ('inicial','final') then raise exception 'Tipo de checklist no válido'; end if;
  select * into o from ordenes where id = p_orden and taller_id = yo.taller_id for update;
  if not found then raise exception 'Orden no encontrada'; end if;
  if yo.rol = 'mecanico' and not public.orden_mia(p_orden) then
    raise exception 'Este coche no está asignado a ti'; end if;
  if o.estado <> 'abierta' then raise exception 'La orden está cerrada'; end if;
  if exists(select 1 from checklists where orden_id = p_orden and tipo = p_tipo) then
    raise exception 'Ese checklist ya está hecho. Solo el personal de oficina puede modificarlo'; end if;
  if p_tipo = 'final' then
    if not exists(select 1 from checklists where orden_id = p_orden and tipo = 'inicial') then
      raise exception 'Primero hay que hacer el checklist inicial'; end if;
    if exists(select 1 from tareas where orden_id = p_orden and estado <> 'finalizada') then
      raise exception 'Marca todas las reparaciones antes del control final'; end if;
    if yo.rol = 'mecanico' and not exists(select 1 from orden_sesiones
        where orden_id = p_orden and mecanico_id = yo.id and fin is null) then
      raise exception 'Primero tienes que empezar el trabajo'; end if;
  end if;
  v_plantilla := case when p_tipo = 'final' then 'final' else o.tipo_checklist end;
  d := public._validar_checklist(v_plantilla, p_datos);
  insert into checklists(orden_id, tipo, taller_id, realizado_por, datos)
  values (p_orden, p_tipo, yo.taller_id, yo.id, d);
  if p_tipo = 'inicial' and d->>'km' is not null then
    update coches set km = (d->>'km')::numeric::int where id = o.coche_id;
  end if;
end $$;

create or replace function public.modificar_checklist(p_orden bigint, p_datos jsonb, p_tipo text default 'inicial') returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_tipo text; v_plantilla text;
begin
  if p_tipo not in ('inicial','final') then raise exception 'Tipo de checklist no válido'; end if;
  select tipo_checklist into v_tipo from ordenes where id = p_orden and taller_id = t;
  if v_tipo is null then raise exception 'Orden no encontrada'; end if;
  v_plantilla := case when p_tipo = 'final' then 'final' else v_tipo end;
  update checklists set datos = public._validar_checklist(v_plantilla, p_datos),
                        modificado = now(), modificado_por = auth.uid()
   where orden_id = p_orden and tipo = p_tipo;
  if not found then raise exception 'Esa orden aún no tiene ese checklist'; end if;
end $$;

-- ─────────────── Tiempo de trabajo (una sola cuenta por coche) ───────────────
drop function if exists public.iniciar_tarea(bigint);
drop function if exists public.terminar_tarea(bigint, text, uuid, text);

create or replace function public.iniciar_orden(p_orden bigint) returns void
language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); o ordenes;
begin
  select * into o from ordenes where id = p_orden and taller_id = yo.taller_id for update;
  if not found then raise exception 'Orden no encontrada'; end if;
  if o.estado <> 'abierta' then raise exception 'La orden está cerrada'; end if;
  if not public.orden_mia(p_orden) then raise exception 'Este coche no está asignado a ti'; end if;
  if not exists(select 1 from checklists where orden_id = p_orden and tipo = 'inicial') then
    raise exception 'Primero tienes que hacer el checklist'; end if;
  if exists(select 1 from orden_sesiones where mecanico_id = yo.id and fin is null and orden_id <> p_orden) then
    raise exception 'Ya estás trabajando en otro coche. Marca fin de turno antes'; end if;
  if exists(select 1 from orden_sesiones where mecanico_id = yo.id and fin is null and orden_id = p_orden) then
    return; end if;
  -- el saldo de tiempo es de quien lleva la cuenta: si entra otro mecánico, empieza limpio
  if o.cuenta_mecanico is distinct from yo.id and o.en_marcha_desde is null then
    update ordenes set seg_consumidos = 0, seg_tarea = 0, cuenta_mecanico = yo.id where id = p_orden;
  elsif o.cuenta_mecanico is null then
    update ordenes set cuenta_mecanico = yo.id where id = p_orden;
  end if;
  if o.en_marcha_desde is null then
    update ordenes set en_marcha_desde = now() where id = p_orden;
  end if;
  insert into orden_sesiones(orden_id, taller_id, mecanico_id) values (p_orden, yo.taller_id, yo.id);
end $$;

create or replace function public.marcar_tarea(p_id bigint, p_hecha boolean) returns void
language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); t tareas; o ordenes; v_tramo numeric; v_paso numeric := 0;
begin
  select * into t from tareas where id = p_id and taller_id = yo.taller_id;
  if not found then raise exception 'Reparación no encontrada'; end if;
  select * into o from ordenes where id = t.orden_id for update;
  if o.estado <> 'abierta' then raise exception 'La orden está cerrada'; end if;
  if yo.rol = 'mecanico' then
    if not public.tarea_mia(p_id) then raise exception 'Esta reparación no está asignada a ti'; end if;
    if not exists(select 1 from orden_sesiones where orden_id = t.orden_id and mecanico_id = yo.id and fin is null) then
      raise exception 'Primero tienes que empezar el trabajo'; end if;
  end if;
  if p_hecha then
    if t.estado = 'finalizada' then return; end if;
    if o.en_marcha_desde is not null then v_paso := extract(epoch from now() - o.en_marcha_desde); end if;
    v_tramo := o.seg_tarea + v_paso;   -- lo que ha costado esta reparación
    -- el tiempo asignado sale de la cuenta. Si se ha pasado, la demora se arrastra;
    -- si ha terminado antes, el margen no se guarda (el saldo nunca baja de cero)
    update ordenes set seg_consumidos = greatest(0, o.seg_consumidos + v_paso - t.seg_asignados),
                       seg_tarea = 0,
                       seg_totales = o.seg_totales + v_paso,
                       en_marcha_desde = case when o.en_marcha_desde is null then null else now() end
     where id = o.id;
    update tareas set estado = 'finalizada', finalizada = now(), finalizada_por = yo.id, seg_reales = v_tramo
     where id = p_id;
    if yo.rol = 'mecanico' then
      insert into avisos(taller_id, orden_id, tarea_id, mecanico_id, tipo, texto)
      values (yo.taller_id, o.id, p_id, yo.id, 'tarea',
              'Reparación hecha: ' || t.titulo || ' (' || round(t.seg_asignados / 60.0) || ' min asignados, '
              || round(v_tramo / 60.0) || ' min reales)');
    end if;
  else
    if t.estado <> 'finalizada' then return; end if;
    -- al desmarcar, la reparación vuelve a contar con su tiempo y el saldo se queda como está
    update tareas set estado = 'pendiente', finalizada = null, finalizada_por = null, seg_reales = null
     where id = p_id;
  end if;
end $$;

create or replace function public.terminar_orden(p_orden bigint, p_motivo text, p_relevo uuid default null, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); o ordenes; v_ses bigint; v_desde timestamptz; v_pend text;
begin
  if p_motivo not in ('finalizada','fin_turno') then raise exception 'Motivo no válido'; end if;
  select * into o from ordenes where id = p_orden and taller_id = yo.taller_id for update;
  if not found then raise exception 'Orden no encontrada'; end if;
  select id into v_ses from orden_sesiones where orden_id = p_orden and mecanico_id = yo.id and fin is null;
  if v_ses is null then raise exception 'No estás trabajando en este coche'; end if;
  if p_motivo = 'fin_turno' and p_relevo is not null then
    if p_relevo = yo.id or not exists(select 1 from perfiles where id = p_relevo and taller_id = yo.taller_id
                                       and rol = 'mecanico' and activo) then
      raise exception 'Compañero no válido'; end if;
  else
    p_relevo := null;
  end if;
  v_desde := coalesce(o.en_marcha_desde, now());
  update orden_sesiones set fin = now(), motivo = p_motivo, nota = nullif(trim(p_nota),''), relevo_id = p_relevo
   where id = v_ses;
  if nullif(trim(p_nota), '') is not null then
    insert into avisos(taller_id, orden_id, mecanico_id, tipo, texto)
    values (yo.taller_id, p_orden, yo.id, 'fin_turno', trim(p_nota));
  end if;
  if p_motivo = 'finalizada' then
    select titulo into v_pend from tareas where orden_id = p_orden and estado <> 'finalizada' order by pos, id limit 1;
    if v_pend is not null then
      raise exception 'Falta marcar «%». Marca todas las reparaciones antes de terminar', v_pend; end if;
    if not exists(select 1 from checklists where orden_id = p_orden and tipo = 'final') then
      raise exception 'Falta el control final'; end if;
    update orden_sesiones set fin = now(), motivo = 'finalizada' where orden_id = p_orden and fin is null;
    update ordenes set seg_consumidos = o.seg_consumidos + extract(epoch from now() - v_desde),
                       seg_tarea = o.seg_tarea + extract(epoch from now() - v_desde),
                       seg_totales = o.seg_totales + extract(epoch from now() - v_desde),
                       en_marcha_desde = null, estado = 'finalizada', cerrado = now()
     where id = p_orden;
    insert into avisos(taller_id, orden_id, mecanico_id, tipo, texto)
    values (yo.taller_id, p_orden, yo.id, 'fin_trabajo', 'Coche terminado: control final hecho y todas las reparaciones marcadas');
  else
    if p_relevo is not null then
      insert into tarea_mecanicos(tarea_id, mecanico_id, taller_id)
      select t.id, p_relevo, yo.taller_id from tareas t where t.orden_id = p_orden and t.estado <> 'finalizada'
      on conflict do nothing;
    end if;
    if not exists(select 1 from orden_sesiones where orden_id = p_orden and fin is null) then
      update ordenes set seg_consumidos = o.seg_consumidos + extract(epoch from now() - v_desde),
                         seg_tarea = o.seg_tarea + extract(epoch from now() - v_desde),
                         seg_totales = o.seg_totales + extract(epoch from now() - v_desde),
                         en_marcha_desde = null where id = p_orden;
    end if;
  end if;
end $$;

create or replace function public.parar_tiempo(p_orden bigint, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); o ordenes;
begin
  select * into o from ordenes where id = p_orden and taller_id = t for update;
  if not found then raise exception 'Orden no encontrada'; end if;
  if o.en_marcha_desde is null then raise exception 'Este coche no tiene el tiempo en marcha'; end if;
  update orden_sesiones set fin = now(), motivo = 'fin_turno',
         nota = coalesce(nullif(trim(p_nota), ''), 'Tiempo parado por la oficina')
   where orden_id = p_orden and fin is null;
  update ordenes set seg_consumidos = o.seg_consumidos + extract(epoch from now() - o.en_marcha_desde),
                     seg_tarea = o.seg_tarea + extract(epoch from now() - o.en_marcha_desde),
                     seg_totales = o.seg_totales + extract(epoch from now() - o.en_marcha_desde),
                     en_marcha_desde = null
   where id = p_orden;
end $$;

-- ─────────────── Turnos ───────────────
create or replace function public.guardar_plantilla_turno(p_id bigint, p_nombre text,
        p_inicio time, p_fin time) returns bigint
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_id bigint;
begin
  if length(trim(coalesce(p_nombre,''))) < 2 then raise exception 'Ponle nombre al turno'; end if;
  if p_inicio = p_fin then raise exception 'Las horas no pueden ser iguales'; end if;
  if p_id is null then
    insert into turnos_plantilla(taller_id, nombre, hora_inicio, hora_fin)
    values (t, trim(p_nombre), p_inicio, p_fin) returning id into v_id;
  else
    update turnos_plantilla set nombre = trim(p_nombre), hora_inicio = p_inicio, hora_fin = p_fin
     where id = p_id and taller_id = t returning id into v_id;
    if v_id is null then raise exception 'Turno no encontrado'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.borrar_plantilla_turno(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin();
begin
  delete from turnos_plantilla where id = p_id and taller_id = t;
  if not found then raise exception 'Turno no encontrado'; end if;
end $$;

create or replace function public.guardar_turno(p_id bigint, p_mecanico uuid, p_inicio timestamptz,
        p_fin timestamptz, p_comentario text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_id bigint; v_nombre text;
begin
  if p_fin <= p_inicio then raise exception 'El turno tiene que acabar después de empezar'; end if;
  if p_fin - p_inicio > interval '16 hours' then raise exception 'Un turno no puede durar más de 16 horas'; end if;
  select nombre into v_nombre from perfiles
   where id = p_mecanico and taller_id = t and rol = 'mecanico';
  if v_nombre is null then raise exception 'Ese mecánico no es de este taller'; end if;
  if exists(select 1 from turnos where mecanico_id = p_mecanico and (p_id is null or id <> p_id)
            and inicio < p_fin and fin > p_inicio) then
    raise exception '% ya tiene otro turno a esa hora', v_nombre; end if;
  if p_id is null then
    insert into turnos(taller_id, mecanico_id, inicio, fin, comentario)
    values (t, p_mecanico, p_inicio, p_fin, nullif(trim(coalesce(p_comentario,'')),'')) returning id into v_id;
  else
    update turnos set mecanico_id = p_mecanico, inicio = p_inicio, fin = p_fin,
                      comentario = nullif(trim(coalesce(p_comentario,'')),'')
     where id = p_id and taller_id = t returning id into v_id;
    if v_id is null then raise exception 'Turno no encontrado'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.borrar_turno(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin();
begin
  delete from turnos where id = p_id and taller_id = t;
  if not found then raise exception 'Turno no encontrado'; end if;
end $$;

-- ─────────────── Fichajes de jornada ───────────────
create or replace function public.fichar(p_tipo text) returns text
language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); v_ultimo text; o ordenes;
begin
  if p_tipo not in ('entrada','descanso','vuelta','fin') then raise exception 'Fichaje no válido'; end if;
  select tipo into v_ultimo from fichajes where mecanico_id = yo.id order by momento desc, id desc limit 1;
  v_ultimo := coalesce(v_ultimo, 'fin');
  if p_tipo = 'entrada' and v_ultimo not in ('fin') then
    raise exception 'Ya has fichado la entrada'; end if;
  if p_tipo = 'descanso' and v_ultimo not in ('entrada','vuelta') then
    raise exception 'Para salir a descansar tienes que estar trabajando'; end if;
  if p_tipo = 'vuelta' and v_ultimo <> 'descanso' then
    raise exception 'Solo puedes volver si estás en el descanso'; end if;
  if p_tipo = 'fin' and v_ultimo = 'fin' then
    raise exception 'Ya has fichado la salida'; end if;
  -- salir a descansar o terminar la jornada para el tiempo del coche que se esté llevando
  if p_tipo in ('descanso','fin') then
    for o in select ord.* from ordenes ord join orden_sesiones se on se.orden_id = ord.id
             where se.mecanico_id = yo.id and se.fin is null for update loop
      update orden_sesiones set fin = now(), motivo = 'fin_turno',
             nota = case when p_tipo = 'descanso' then 'Salida para descanso' else 'Fin de turno' end
       where orden_id = o.id and mecanico_id = yo.id and fin is null;
      if not exists(select 1 from orden_sesiones where orden_id = o.id and fin is null) then
        update ordenes set seg_consumidos = o.seg_consumidos + extract(epoch from now() - coalesce(o.en_marcha_desde, now())),
                           seg_tarea = o.seg_tarea + extract(epoch from now() - coalesce(o.en_marcha_desde, now())),
                           seg_totales = o.seg_totales + extract(epoch from now() - coalesce(o.en_marcha_desde, now())),
                           en_marcha_desde = null
         where id = o.id;
      end if;
    end loop;
  end if;
  insert into fichajes(taller_id, mecanico_id, tipo) values (yo.taller_id, yo.id, p_tipo);
  return p_tipo;
end $$;

create or replace function public.historico_fichajes(p_mecanico uuid default null,
                                                     p_desde timestamptz default null,
                                                     p_hasta timestamptz default null)
returns table(momento timestamptz, tipo text, mecanico text, mecanico_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare t bigint := public._admin();
begin
  return query
  select f.momento, f.tipo, u.nombre, u.id
  from fichajes f join perfiles u on u.id = f.mecanico_id
  where f.taller_id = t
    and (p_mecanico is null or f.mecanico_id = p_mecanico)
    and (p_desde is null or f.momento >= p_desde)
    and (p_hasta is null or f.momento < p_hasta)
  order by f.momento desc
  limit 5000;
end $$;

-- ─────────────── Incidencias y avisos a la oficina ───────────────
drop function if exists public.crear_incidencia(bigint, text);
drop function if exists public.crear_nota(bigint, text, bigint);

create or replace function public._fotos(p jsonb) returns jsonb
language sql immutable as $$
  select coalesce((select jsonb_agg(f) from (
    select f from jsonb_array_elements_text(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) f
    limit 6) z), '[]'::jsonb)
$$;

create or replace function public.crear_incidencia(p_tarea bigint, p_nota text, p_fotos jsonb default '[]'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); t tareas; o ordenes;
begin
  if length(trim(coalesce(p_nota, ''))) < 3 then raise exception 'Escribe qué ha pasado'; end if;
  select * into t from tareas where id = p_tarea and taller_id = yo.taller_id;
  if not found then raise exception 'Reparación no encontrada'; end if;
  select * into o from ordenes where id = t.orden_id for update;
  if o.estado <> 'abierta' then raise exception 'La orden está cerrada'; end if;
  if yo.rol = 'mecanico' and not public.tarea_mia(p_tarea) then
    raise exception 'Esta reparación no está asignada a ti'; end if;
  if not exists(select 1 from orden_sesiones where orden_id = o.id and mecanico_id = yo.id and fin is null) then
    raise exception 'Primero tienes que empezar el trabajo'; end if;
  -- la incidencia para el tiempo del coche
  update orden_sesiones set fin = now(), motivo = 'fin_turno', nota = 'Incidencia: ' || trim(p_nota)
   where orden_id = o.id and fin is null;
  if o.en_marcha_desde is not null then
    update ordenes set seg_consumidos = o.seg_consumidos + extract(epoch from now() - o.en_marcha_desde),
                       seg_tarea = o.seg_tarea + extract(epoch from now() - o.en_marcha_desde),
                       seg_totales = o.seg_totales + extract(epoch from now() - o.en_marcha_desde),
                       en_marcha_desde = null where id = o.id;
  end if;
  insert into avisos(taller_id, orden_id, tarea_id, mecanico_id, tipo, texto, fotos)
  values (yo.taller_id, o.id, p_tarea, yo.id, 'incidencia', trim(p_nota), public._fotos(p_fotos));
end $$;

create or replace function public.crear_nota(p_orden bigint, p_texto text, p_tarea bigint default null,
                                             p_fotos jsonb default '[]'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo();
begin
  if length(trim(coalesce(p_texto, ''))) < 3 then raise exception 'Escribe la nota'; end if;
  if not exists(select 1 from ordenes where id = p_orden and taller_id = yo.taller_id) then
    raise exception 'Orden no encontrada'; end if;
  if yo.rol = 'mecanico' and not public.orden_mia(p_orden) then
    raise exception 'Este coche no está asignado a ti'; end if;
  insert into avisos(taller_id, orden_id, tarea_id, mecanico_id, tipo, texto, fotos)
  values (yo.taller_id, p_orden, p_tarea, yo.id, 'nota', trim(p_texto), public._fotos(p_fotos));
end $$;

create or replace function public.marcar_avisos(p_ids bigint[] default null) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin();
begin
  update avisos set leido = now(), leido_por = auth.uid()
   where taller_id = t and leido is null and (p_ids is null or id = any(p_ids));
end $$;

-- ─────────────── Histórico ───────────────
drop function if exists public.historico(uuid, text, timestamptz, timestamptz);

create or replace function public.historico(p_mecanico uuid default null, p_matricula text default null,
                                            p_desde timestamptz default null, p_hasta timestamptz default null)
returns table(inicio timestamptz, fin timestamptz, motivo text, nota text, mecanico_id uuid, mecanico text,
              relevo text, orden_id bigint, tipo_revision text, seg_asignados bigint, reparaciones bigint,
              matricula text, marca text, modelo text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare t bigint := public._admin();
begin
  return query
  select s.inicio, s.fin, s.motivo, s.nota, u.id, u.nombre, r.nombre, o.id, o.tipo_revision,
         (select coalesce(sum(ta.seg_asignados), 0) from tareas ta where ta.orden_id = o.id) + public.seg_checklists(),
         (select count(*) from tareas ta where ta.orden_id = o.id and ta.finalizada_por = u.id),
         c.matricula, c.marca, c.modelo
  from orden_sesiones s
  join ordenes o on o.id = s.orden_id
  join coches c on c.id = o.coche_id
  join perfiles u on u.id = s.mecanico_id
  left join perfiles r on r.id = s.relevo_id
  where s.taller_id = t
    and (p_mecanico is null or s.mecanico_id = p_mecanico)
    and (coalesce(p_matricula,'') = '' or c.matricula like '%' || upper(regexp_replace(p_matricula, '[\s-]', '', 'g')) || '%')
    and (p_desde is null or s.inicio >= p_desde)
    and (p_hasta is null or s.inicio < p_hasta)
  order by s.inicio desc
  limit 5000;
end $$;

drop function if exists public.historico_reparaciones(uuid, text, timestamptz, timestamptz);

create or replace function public.historico_reparaciones(p_mecanico uuid default null, p_matricula text default null,
                                                         p_desde timestamptz default null, p_hasta timestamptz default null)
returns table(finalizada timestamptz, reparacion text, minutos numeric, minutos_reales numeric, mecanico text,
              orden_id bigint, tipo_revision text, matricula text, marca text, modelo text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare t bigint := public._admin();
begin
  return query
  select ta.finalizada, ta.titulo, round(ta.seg_asignados / 60.0, 1), round(ta.seg_reales / 60.0, 1), u.nombre, o.id, o.tipo_revision,
         c.matricula, c.marca, c.modelo
  from tareas ta
  join ordenes o on o.id = ta.orden_id
  join coches c on c.id = o.coche_id
  left join perfiles u on u.id = ta.finalizada_por
  where ta.taller_id = t and ta.estado = 'finalizada'
    and (p_mecanico is null or ta.finalizada_por = p_mecanico)
    and (coalesce(p_matricula,'') = '' or c.matricula like '%' || upper(regexp_replace(p_matricula, '[\s-]', '', 'g')) || '%')
    and (p_desde is null or ta.finalizada >= p_desde)
    and (p_hasta is null or ta.finalizada < p_hasta)
  order by ta.finalizada desc
  limit 5000;
end $$;

-- Las funciones internas no se pueden llamar desde la app
revoke execute on function public._yo(), public._admin(), public._validar_checklist(text, jsonb) from public, anon, authenticated;
