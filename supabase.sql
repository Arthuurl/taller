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
  creado timestamptz not null default now());

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
  creado timestamptz not null default now(),
  cerrado timestamptz);

create table if not exists public.checklists(
  orden_id bigint primary key references public.ordenes(id) on delete cascade,
  taller_id bigint not null references public.talleres(id),
  realizado_por uuid not null references public.perfiles(id),
  datos jsonb not null,
  creado timestamptz not null default now(),
  modificado timestamptz,
  modificado_por uuid references public.perfiles(id));

create table if not exists public.tareas(
  id bigint generated always as identity primary key,
  orden_id bigint not null references public.ordenes(id) on delete cascade,
  taller_id bigint not null references public.talleres(id),
  titulo text not null, descripcion text,
  seg_asignados int not null check (seg_asignados > 0),
  seg_consumidos numeric not null default 0,
  en_marcha_desde timestamptz,
  estado text not null default 'pendiente' check (estado in ('pendiente','en_curso','a_medias','finalizada')),
  pos int not null default 0,
  finalizada timestamptz);

create table if not exists public.tarea_mecanicos(
  tarea_id bigint not null references public.tareas(id) on delete cascade,
  mecanico_id uuid not null references public.perfiles(id),
  taller_id bigint not null references public.talleres(id),
  primary key (tarea_id, mecanico_id));

create table if not exists public.tarea_sesiones(
  id bigint generated always as identity primary key,
  tarea_id bigint not null references public.tareas(id) on delete cascade,
  taller_id bigint not null references public.talleres(id),
  mecanico_id uuid not null references public.perfiles(id),
  inicio timestamptz not null default now(),
  fin timestamptz,
  motivo text check (motivo in ('finalizada','fin_turno','cerrada_admin')),
  nota text,
  relevo_id uuid references public.perfiles(id));

-- Un mecánico solo puede tener una tarea en marcha
create unique index if not exists una_tarea_a_la_vez on public.tarea_sesiones(mecanico_id) where fin is null;
create index if not exists ix_tareas_orden on public.tareas(orden_id);
create index if not exists ix_tm_mecanico on public.tarea_mecanicos(mecanico_id);
create index if not exists ix_ses_tarea on public.tarea_sesiones(tarea_id);

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

create or replace function public.coche_mio(p bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from ordenes o where o.coche_id = p and public.orden_mia(o.id))
$$;

create or replace function public.ahora() returns timestamptz
language sql stable as $$ select now() $$;

create or replace function public.plantillas() returns jsonb
language sql immutable as $$
  select '{
    "basico": [
      {"id":"b1","texto":"Nivel de aceite del motor"},
      {"id":"b2","texto":"Líquido refrigerante"},
      {"id":"b3","texto":"Líquido de frenos"},
      {"id":"b4","texto":"Presión de neumáticos"},
      {"id":"b5","texto":"Luces exteriores"},
      {"id":"b6","texto":"Limpiaparabrisas y líquido"},
      {"id":"b7","texto":"Batería y bornes"},
      {"id":"b8","texto":"Testigos del cuadro"}],
    "completo": [
      {"id":"b1","texto":"Nivel de aceite del motor"},
      {"id":"b2","texto":"Líquido refrigerante"},
      {"id":"b3","texto":"Líquido de frenos"},
      {"id":"b4","texto":"Presión de neumáticos"},
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
      {"id":"c7","texto":"Fugas bajo el vehículo"},
      {"id":"c8","texto":"Filtro de aire"},
      {"id":"c9","texto":"Filtro de habitáculo"},
      {"id":"c10","texto":"Carrocería y cristales"},
      {"id":"c11","texto":"Cinturones y airbag"},
      {"id":"c12","texto":"Climatización"}]
  }'::jsonb
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
  if t is null then raise exception 'Solo el administrador puede hacer esto'; end if;
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
alter table public.tarea_sesiones  enable row level security;

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
  using (taller_id = public.mi_taller() and (public.es_admin() or public.tarea_mia(id)));
drop policy if exists leer on public.tarea_mecanicos;
create policy leer on public.tarea_mecanicos for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or public.tarea_mia(tarea_id)));
drop policy if exists leer on public.tarea_sesiones;
create policy leer on public.tarea_sesiones for select to authenticated
  using (taller_id = public.mi_taller() and (public.es_admin() or public.tarea_mia(tarea_id)));

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
  if exists(select 1 from tarea_sesiones where tarea_id = p_id) then
    raise exception 'No se puede eliminar: ya se ha trabajado en ella'; end if;
  delete from tareas where id = p_id and taller_id = t;
  if not found then raise exception 'Tarea no encontrada'; end if;
end $$;

create or replace function public.crear_orden(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_coche bigint; v_orden bigint; x jsonb;
begin
  if coalesce(trim(p->>'tipo_revision'),'') = '' then raise exception 'Indica el tipo de revisión'; end if;
  if coalesce(p->>'tipo_checklist','') not in ('basico','completo') then raise exception 'Tipo de checklist no válido'; end if;
  if jsonb_array_length(coalesce(p->'tareas','[]'::jsonb)) = 0 then raise exception 'Añade al menos una reparación'; end if;
  if nullif(p->>'coche_id','') is not null then
    select id into v_coche from coches where id = (p->>'coche_id')::bigint and taller_id = t;
    if v_coche is null then raise exception 'Coche no encontrado'; end if;
  else
    v_coche := public.guardar_coche(null, p->'coche');
  end if;
  insert into ordenes(taller_id, coche_id, tipo_revision, tipo_checklist, notas)
  values (t, v_coche, trim(p->>'tipo_revision'), p->>'tipo_checklist', nullif(trim(p->>'notas'),''))
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
declare t bigint := public._admin(); r tareas;
begin
  if p_estado not in ('abierta','finalizada','cancelada') then raise exception 'Estado no válido'; end if;
  perform 1 from ordenes where id = p_id and taller_id = t for update;
  if not found then raise exception 'Orden no encontrada'; end if;
  if p_estado = 'abierta' then
    update ordenes set estado = 'abierta', cerrado = null where id = p_id;
  else
    for r in select * from tareas where orden_id = p_id and en_marcha_desde is not null for update loop
      update tareas set seg_consumidos = r.seg_consumidos + extract(epoch from now() - r.en_marcha_desde),
                        en_marcha_desde = null, estado = 'a_medias' where id = r.id;
    end loop;
    update tarea_sesiones set fin = now(), motivo = 'cerrada_admin'
     where fin is null and tarea_id in (select id from tareas where orden_id = p_id);
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
      jsonb_build_object('estado', v->>'estado', 'nota', left(trim(coalesce(v->>'nota','')), 300)));
  end loop;
  return jsonb_build_object('items', items,
    'km', case when jsonb_typeof(p->'km') = 'number' and (p->>'km')::numeric >= 0 then p->'km' end,
    'observaciones', left(trim(coalesce(p->>'observaciones','')), 1000));
end $$;

create or replace function public.hacer_checklist(p_orden bigint, p_datos jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); o ordenes; d jsonb;
begin
  select * into o from ordenes where id = p_orden and taller_id = yo.taller_id for update;
  if not found then raise exception 'Orden no encontrada'; end if;
  if yo.rol = 'mecanico' and not public.orden_mia(p_orden) then
    raise exception 'Este coche no está asignado a ti'; end if;
  if o.estado <> 'abierta' then raise exception 'La orden está cerrada'; end if;
  if exists(select 1 from checklists where orden_id = p_orden) then
    raise exception 'El checklist ya está hecho. Solo el administrador puede modificarlo'; end if;
  d := public._validar_checklist(o.tipo_checklist, p_datos);
  insert into checklists(orden_id, taller_id, realizado_por, datos) values (p_orden, yo.taller_id, yo.id, d);
  if d->>'km' is not null then
    update coches set km = (d->>'km')::numeric::int where id = o.coche_id;
  end if;
end $$;

create or replace function public.modificar_checklist(p_orden bigint, p_datos jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare t bigint := public._admin(); v_tipo text;
begin
  select tipo_checklist into v_tipo from ordenes where id = p_orden and taller_id = t;
  if v_tipo is null then raise exception 'Orden no encontrada'; end if;
  update checklists set datos = public._validar_checklist(v_tipo, p_datos),
                        modificado = now(), modificado_por = auth.uid()
   where orden_id = p_orden;
  if not found then raise exception 'Esta orden aún no tiene checklist'; end if;
end $$;

-- ─────────────── Tiempo de las tareas ───────────────
create or replace function public.iniciar_tarea(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); t tareas; v_estado text;
begin
  select * into t from tareas where id = p_id and taller_id = yo.taller_id for update;
  if not found then raise exception 'Tarea no encontrada'; end if;
  select estado into v_estado from ordenes where id = t.orden_id;
  if v_estado <> 'abierta' then raise exception 'La orden está cerrada'; end if;
  if not public.tarea_mia(p_id) then raise exception 'Esta tarea no está asignada a ti'; end if;
  if not exists(select 1 from checklists where orden_id = t.orden_id) then
    raise exception 'Primero tienes que hacer el checklist'; end if;
  if t.estado = 'finalizada' then raise exception 'La tarea ya está finalizada'; end if;
  if exists(select 1 from tarea_sesiones where mecanico_id = yo.id and fin is null) then
    raise exception 'Ya tienes otra tarea en marcha. Finalízala o marca fin de turno'; end if;
  if t.en_marcha_desde is null then
    update tareas set en_marcha_desde = now(), estado = 'en_curso' where id = p_id;
  end if;
  insert into tarea_sesiones(tarea_id, taller_id, mecanico_id) values (p_id, yo.taller_id, yo.id);
end $$;

create or replace function public.terminar_tarea(p_id bigint, p_motivo text, p_relevo uuid default null, p_nota text default null)
returns void language plpgsql security definer set search_path = public as $$
declare yo perfiles := public._yo(); t tareas; v_ses bigint; v_desde timestamptz;
begin
  if p_motivo not in ('finalizada','fin_turno') then raise exception 'Motivo no válido'; end if;
  select * into t from tareas where id = p_id and taller_id = yo.taller_id for update;
  if not found then raise exception 'Tarea no encontrada'; end if;
  select id into v_ses from tarea_sesiones where tarea_id = p_id and mecanico_id = yo.id and fin is null;
  if v_ses is null then raise exception 'No estás trabajando en esta tarea'; end if;
  if p_motivo = 'fin_turno' and p_relevo is not null then
    if p_relevo = yo.id or not exists(select 1 from perfiles where id = p_relevo and taller_id = yo.taller_id
                                       and rol = 'mecanico' and activo) then
      raise exception 'Compañero no válido'; end if;
  else
    p_relevo := null;
  end if;
  v_desde := coalesce(t.en_marcha_desde, now());
  update tarea_sesiones set fin = now(), motivo = p_motivo, nota = nullif(trim(p_nota),''), relevo_id = p_relevo
   where id = v_ses;
  if p_motivo = 'finalizada' then
    -- el tiempo es compartido: finalizar cierra la tarea para todos
    update tarea_sesiones set fin = now(), motivo = 'finalizada' where tarea_id = p_id and fin is null;
    update tareas set seg_consumidos = t.seg_consumidos + extract(epoch from now() - v_desde),
                      en_marcha_desde = null, estado = 'finalizada', finalizada = now()
     where id = p_id;
    if not exists(select 1 from tareas where orden_id = t.orden_id and estado <> 'finalizada') then
      update ordenes set estado = 'finalizada', cerrado = now() where id = t.orden_id;
    end if;
  else
    if p_relevo is not null then
      insert into tarea_mecanicos(tarea_id, mecanico_id, taller_id) values (p_id, p_relevo, yo.taller_id)
      on conflict do nothing;
    end if;
    if not exists(select 1 from tarea_sesiones where tarea_id = p_id and fin is null) then
      update tareas set seg_consumidos = t.seg_consumidos + extract(epoch from now() - v_desde),
                        en_marcha_desde = null, estado = 'a_medias'
       where id = p_id;
    end if;
  end if;
end $$;

-- ─────────────── Histórico ───────────────
create or replace function public.historico(p_mecanico uuid default null, p_matricula text default null,
                                            p_desde timestamptz default null, p_hasta timestamptz default null)
returns table(inicio timestamptz, fin timestamptz, motivo text, nota text, mecanico_id uuid, mecanico text,
              relevo text, tarea text, seg_asignados int, orden_id bigint, tipo_revision text,
              matricula text, marca text, modelo text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare t bigint := public._admin();
begin
  return query
  select s.inicio, s.fin, s.motivo, s.nota, u.id, u.nombre, r.nombre, ta.titulo, ta.seg_asignados,
         o.id, o.tipo_revision, c.matricula, c.marca, c.modelo
  from tarea_sesiones s
  join tareas ta on ta.id = s.tarea_id
  join ordenes o on o.id = ta.orden_id
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

-- Las funciones internas no se pueden llamar desde la app
revoke execute on function public._yo(), public._admin(), public._validar_checklist(text, jsonb) from public, anon, authenticated;
