-- Coach & PGC Dashboard — run this in Supabase: SQL Editor → New query → paste all → Run
-- Safe to run again (it only creates what is missing and refreshes the functions).
-- Then paste Project URL + anon public key into the dashboard Backup → Cloud panel.

/* =====================================================================
   1. Full backup (one JSON copy of everything — used to restore a browser)
   ===================================================================== */
create table if not exists public.dashboard_store (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- repair a dashboard_store that was created by hand with the wrong columns
alter table public.dashboard_store add column if not exists updated_at timestamptz not null default now();
do $$
begin
  if (select data_type from information_schema.columns
      where table_schema = 'public' and table_name = 'dashboard_store' and column_name = 'value') <> 'jsonb' then
    alter table public.dashboard_store alter column value drop default;
    alter table public.dashboard_store alter column value type jsonb
      using case when value is null or btrim(value) = '' then '{}'::jsonb else value::jsonb end;
  end if;
  alter table public.dashboard_store alter column value set default '{}'::jsonb;
  update public.dashboard_store set value = '{}'::jsonb where value is null;
  alter table public.dashboard_store alter column value set not null;
end $$;

/* =====================================================================
   2. Readable tables — one row per figure, browse/filter/edit them in
      Table Editor. The dashboard rewrites a year's rows every time it
      saves, and reads them back when it opens (edits made here win).
   ===================================================================== */

-- years the dashboard has synced (delete a row here to stop the tables overriding that year)
create table if not exists public.report_years (
  year       int primary key,
  source     text,
  synced_at  timestamptz not null default now()
);

-- failures per system, coach/PGC class and month (Summary sheet)
create table if not exists public.failure_summary (
  year         int  not null,
  section      text not null check (section in ('coach','pgc')),
  system       text not null,
  coach_class  text not null,            -- ASC / ADNS / ABC / AFC / UMW / INKA
  month        int  not null check (month between 1 and 12),
  failures     numeric,
  primary key (year, section, system, coach_class, month)
);

-- 4M analysis (METHOD / MATERIAL / MANPOWER / MACHINES) per month
create table if not exists public.failure_4m (
  year     int  not null,
  section  text not null check (section in ('coach','pgc')),
  element  text not null,
  month    int  not null check (month between 1 and 12),
  usw      numeric,
  fis      numeric,
  primary key (year, section, element, month)
);

-- monthly failure totals
create table if not exists public.monthly_failures (
  year     int  not null,
  section  text not null check (section in ('coach','pgc')),
  month    int  not null check (month between 1 and 12),
  usw      numeric,
  fis      numeric,
  primary key (year, section, month)
);

-- daily availability, actual vs target
create table if not exists public.availability (
  year     int  not null,
  section  text not null check (section in ('coach','pgc')),
  month    int  not null check (month between 1 and 12),
  day      int  not null check (day between 1 and 31),
  actual   numeric,
  target   numeric,
  primary key (year, section, month, day)
);

-- preventive maintenance, target vs actual per month
create table if not exists public.pm_compliance (
  year     int  not null,
  section  text not null check (section in ('coach','pgc')),
  month    int  not null check (month between 1 and 12),
  target   numeric,
  actual   numeric,
  primary key (year, section, month)
);

-- incident / failure investigation register
create table if not exists public.incidents (
  id             bigint generated always as identity primary key,
  year           int  not null,
  section        text not null check (section in ('coach','pgc')),
  row_order      int  not null,           -- position in the dashboard list
  no             text,
  failure        text,
  unit           text,
  incident_date  date,
  system         text,
  element        text,
  causes         text,
  root           text,
  evidence       text,
  action         text,
  rectifiable    text,
  extra          jsonb not null default '{}'::jsonb   -- any other fields, kept as-is
);
create index if not exists incidents_year_section_idx on public.incidents (year, section, row_order);

/* =====================================================================
   3. Helper + sync functions (called by the dashboard)
   ===================================================================== */
create or replace function public.rsd_num(j jsonb) returns numeric
language sql immutable as $$
  select case
    when jsonb_typeof(j) = 'number' then (j #>> '{}')::numeric
    when jsonb_typeof(j) = 'string' and (j #>> '{}') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then trim(j #>> '{}')::numeric
  end
$$;

create or replace function public.rsd_date(t text) returns date
language plpgsql immutable as $$
begin
  if t ~ '^\d{4}-\d{2}-\d{2}$' then return t::date; end if;
  return null;
exception when others then return null;
end $$;

create or replace function public.rsd_arr(j jsonb) returns jsonb
language sql immutable as $$ select case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end $$;

create or replace function public.rsd_obj(j jsonb) returns jsonb
language sql immutable as $$ select case when jsonb_typeof(j) = 'object' then j else '{}'::jsonb end $$;

-- daily status reports (one row per saved day; full record kept in data)
create table if not exists public.daily_reports (
  report_date   date primary key,
  saved_at      timestamptz,
  availability  numeric generated always as (public.rsd_num(data->'avail')) stored,
  on_duty       numeric generated always as (public.rsd_num(data->'duty')) stored,
  data          jsonb not null default '{}'::jsonb
);

-- replace every table row for one reporting year with the dashboard's data
create or replace function public.rsd_sync_year(p_year int, p_data jsonb, p_source text default null)
returns void language plpgsql as $$
begin
  delete from public.failure_summary  where year = p_year;
  delete from public.failure_4m       where year = p_year;
  delete from public.monthly_failures where year = p_year;
  delete from public.availability     where year = p_year;
  delete from public.pm_compliance    where year = p_year;
  delete from public.incidents        where year = p_year;

  insert into public.failure_summary (year, section, system, coach_class, month, failures)
  select p_year, sx.section, s->>'system', c.key, m.ord, public.rsd_num(m.val)
  from (values ('coach','coachSummary'), ('pgc','pgcSummary')) sx(section, k)
  cross join lateral jsonb_array_elements(public.rsd_arr(p_data->sx.k)) s
  cross join lateral jsonb_each(public.rsd_obj(s->'classes')) c
  cross join lateral jsonb_array_elements(public.rsd_arr(c.value)) with ordinality m(val, ord)
  where m.ord <= 12 and coalesce(s->>'system', '') <> ''
  on conflict do nothing;

  insert into public.failure_4m (year, section, element, month, usw, fis)
  select p_year, sx.section, e.key, m,
         public.rsd_num(e.value->'usw'->(m - 1)), public.rsd_num(e.value->'fis'->(m - 1))
  from (values ('coach','coach4m'), ('pgc','pgc4m')) sx(section, k)
  cross join lateral jsonb_each(public.rsd_obj(p_data->sx.k)) e
  cross join generate_series(1, 12) m;

  insert into public.monthly_failures (year, section, month, usw, fis)
  select p_year, sx.section, m,
         public.rsd_num(p_data->'monthlyFailures'->sx.section->'usw'->(m - 1)),
         public.rsd_num(p_data->'monthlyFailures'->sx.section->'fis'->(m - 1))
  from (values ('coach'), ('pgc')) sx(section)
  cross join generate_series(1, 12) m
  where p_data->'monthlyFailures'->sx.section is not null;

  insert into public.pm_compliance (year, section, month, target, actual)
  select p_year, sx.section, m,
         public.rsd_num(p_data->'pm'->(sx.section || 'Target')->(m - 1)),
         public.rsd_num(p_data->'pm'->(sx.section || 'Actual')->(m - 1))
  from (values ('coach'), ('pgc')) sx(section)
  cross join generate_series(1, 12) m;

  insert into public.availability (year, section, month, day, actual, target)
  select * from (
    select p_year, sx.section, mo.ord::int as month, d as day,
           public.rsd_num(mo.v->'actual'->(d - 1)) as actual,
           public.rsd_num(mo.v->'target'->(d - 1)) as target
    from (values ('coach','coachAvail'), ('pgc','pgcAvail')) sx(section, k)
    cross join lateral jsonb_array_elements(public.rsd_arr(p_data->sx.k)) with ordinality mo(v, ord)
    cross join generate_series(1, 31) d
    where mo.ord <= 12
  ) a
  where a.actual is not null or a.target is not null;

  insert into public.incidents (year, section, row_order, no, failure, unit, incident_date, system,
                                element, causes, root, evidence, action, rectifiable, extra)
  select p_year, sx.section, i.ord, i.v->>'no', i.v->>'failure', i.v->>'unit',
         public.rsd_date(i.v->>'date'), i.v->>'system', i.v->>'element', i.v->>'causes',
         i.v->>'root', i.v->>'evidence', i.v->>'action', i.v->>'rectifiable',
         (i.v - array['no','failure','unit','system','element','causes','root','evidence','action','rectifiable'])
           - (case when public.rsd_date(i.v->>'date') is not null then array['date'] else array[]::text[] end)
  from (values ('coach','coachIncidents'), ('pgc','pgcIncidents')) sx(section, k)
  cross join lateral jsonb_array_elements(public.rsd_arr(p_data->sx.k)) with ordinality i(v, ord)
  where jsonb_typeof(i.v) = 'object';

  insert into public.report_years (year, source, synced_at)
  values (p_year, p_source, now())
  on conflict (year) do update set source = excluded.source, synced_at = excluded.synced_at;
end $$;

-- replace all daily report rows with the dashboard's saved daily records
create or replace function public.rsd_sync_daily(p_recs jsonb)
returns void language plpgsql as $$
begin
  delete from public.daily_reports where true;
  insert into public.daily_reports (report_date, saved_at, data)
  select public.rsd_date(r.key),
         case when public.rsd_num(r.value->'ts') is not null
              then to_timestamp(public.rsd_num(r.value->'ts') / 1000) end,
         public.rsd_obj(r.value->'data')
  from jsonb_each(public.rsd_obj(p_recs)) r
  where public.rsd_date(r.key) is not null
  on conflict do nothing;
end $$;

-- everything in the readable tables, as one JSON (avoids the 1000-row API limit)
create or replace function public.rsd_load_all()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'years',   (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.report_years t),
    'summary', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.failure_summary t),
    'f4m',     (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.failure_4m t),
    'mf',      (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.monthly_failures t),
    'avail',   (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.availability t),
    'pm',      (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.pm_compliance t),
    'inc',     (select coalesce(jsonb_agg(to_jsonb(t) order by t.year, t.section, t.row_order, t.id), '[]') from public.incidents t),
    'daily',   (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.daily_reports t)
  )
$$;

/* =====================================================================
   4. Access (same open policy as before)
   ===================================================================== */
do $$
declare t text;
begin
  foreach t in array array['dashboard_store','report_years','failure_summary','failure_4m',
                           'monthly_failures','availability','pm_compliance','incidents','daily_reports']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "anon_all_%s" on public.%I', t, t);
    execute format('create policy "anon_all_%s" on public.%I for all to anon using (true) with check (true)', t, t);
    execute format('grant select, insert, update, delete on public.%I to anon', t);
  end loop;
end $$;

grant execute on function public.rsd_sync_year(int, jsonb, text) to anon;
grant execute on function public.rsd_sync_daily(jsonb) to anon;
grant execute on function public.rsd_load_all() to anon;

-- Anyone with the anon key in the HTML/config can read and write.
-- Add login + tighter policies before sharing this on the public internet.
