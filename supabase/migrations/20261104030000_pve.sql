-- Stage 6 PvE: campaign stars, weekly arena scores, weekly settlement.

create table if not exists public.pve_progress (
  player_id uuid not null references public.players(id) on delete cascade,
  level int not null,
  stars int not null check (stars between 0 and 3),
  primary key (player_id, level)
);
create table if not exists public.pve_weekly (
  player_id uuid not null references public.players(id) on delete cascade,
  week int not null,
  score int not null check (score >= 0),
  primary key (player_id, week)
);
create index if not exists pve_weekly_rank on public.pve_weekly (week, score desc, player_id);
create table if not exists public.pve_weeks_settled (week int primary key, settled_at timestamptz not null default now());

alter table public.pve_progress enable row level security;
alter table public.pve_weekly enable row level security;
alter table public.pve_weeks_settled enable row level security;
create policy pve_progress_select_own on public.pve_progress for select to authenticated using (player_id = auth.uid());
create policy pve_weekly_select_own on public.pve_weekly for select to authenticated using (player_id = auth.uid());

-- stars = max(old, new); crystals for the newly gained stars only (row lock makes it once).
create or replace function public.pve_record(p_id uuid, p_level int, p_stars int, p_per_star int)
returns int language plpgsql as $$
declare old int; gained int;
begin
  insert into public.pve_progress (player_id, level, stars) values (p_id, p_level, 0)
    on conflict (player_id, level) do nothing;
  select stars into old from public.pve_progress where player_id = p_id and level = p_level for update;
  gained := greatest(0, p_stars - old);
  if gained > 0 then
    update public.pve_progress set stars = p_stars where player_id = p_id and level = p_level;
    update public.players set crystals = crystals + gained * p_per_star where id = p_id;
    perform public.mirror_crystals(p_id);
  end if;
  return gained;
end $$;

create or replace function public.pve_week_record(p_id uuid, p_week int, p_score int)
returns void language sql as $$
  insert into public.pve_weekly (player_id, week, score) values (p_id, p_week, p_score)
  on conflict (player_id, week) do update set score = greatest(public.pve_weekly.score, excluded.score);
$$;

-- Once per week: top p_top_pct% of players with score > 0 (at least 1, ties at the threshold in).
create or replace function public.settle_pve_week(p_week int, p_top_pct int, p_crystals int, p_boosters jsonb)
returns boolean language plpgsql as $$
declare n int; k int; threshold int; r record;
begin
  insert into public.pve_weeks_settled (week) values (p_week) on conflict do nothing;
  if not found then return false; end if;
  select count(*) into n from public.pve_weekly where week = p_week and score > 0;
  if n = 0 then return true; end if;
  k := greatest(1, (n * p_top_pct) / 100);
  select score into threshold from public.pve_weekly where week = p_week and score > 0
   order by score desc, player_id limit 1 offset k - 1;
  for r in select player_id from public.pve_weekly where week = p_week and score >= threshold and score > 0
           order by player_id loop
    perform public.grant_items(r.player_id, p_crystals, p_boosters);
  end loop;
  return true;
end $$;

create or replace function public.pve_unsettled_weeks(p_before int)
returns setof int language sql stable as $$
  select distinct w.week from public.pve_weekly w
   where w.week < p_before and not exists (select 1 from public.pve_weeks_settled s where s.week = w.week)
   order by 1;
$$;

revoke all on function public.pve_unsettled_weeks(int) from public, anon, authenticated;
revoke all on function public.pve_record(uuid, int, int, int) from public, anon, authenticated;
revoke all on function public.pve_week_record(uuid, int, int) from public, anon, authenticated;
revoke all on function public.settle_pve_week(int, int, int, jsonb) from public, anon, authenticated;
grant execute on function public.pve_record(uuid, int, int, int), public.pve_week_record(uuid, int, int),
  public.settle_pve_week(int, int, int, jsonb), public.pve_unsettled_weeks(int) to service_role;
