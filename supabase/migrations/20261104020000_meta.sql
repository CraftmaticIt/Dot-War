-- Stage 5 meta: boosters inventory, seasons, daily quests, attack loadouts.

alter table public.players add column if not exists boosters jsonb not null default '{"rage":1,"shield":1,"emp":1,"split":1}';
alter table public.players add column if not exists season int not null default 0;
alter table public.players add column if not exists quests jsonb;
alter table public.players add column if not exists quests_rev int not null default 0;
alter table public.players add column if not exists last_reward jsonb;
alter table public.attacks add column if not exists loadout jsonb not null default '[]';

-- Mirror players.crystals into colonies.data.crystals (bumps rev so a racing sync re-checks).
create or replace function public.mirror_crystals(p_id uuid)
returns void language sql as $$
  update public.colonies c
     set data = jsonb_set(c.data, '{crystals}', to_jsonb(p.crystals)), rev = c.rev + 1
    from public.players p
   where c.player_id = p_id and p.id = p_id;
$$;

-- Replaces adjust_player: crystals now change by a delta (mirrored).
drop function if exists public.adjust_player(uuid, int, int, timestamptz, int);
create or replace function public.adjust_player(p_id uuid, p_dtrophies int, p_dattacks int,
  p_shield timestamptz default null, p_dcrystals int default 0)
returns void language plpgsql as $$
begin
  update public.players
     set trophies = greatest(0, trophies + p_dtrophies),
         attacks = attacks + p_dattacks,
         shield_until = coalesce(p_shield, shield_until),
         crystals = greatest(0, crystals + p_dcrystals)
   where id = p_id;
  if p_dcrystals <> 0 then perform public.mirror_crystals(p_id); end if;
end $$;

-- All-or-nothing booster spend.
create or replace function public.take_boosters(p_id uuid, p_need jsonb)
returns boolean language plpgsql as $$
declare b jsonb; k text; n int;
begin
  select boosters into b from public.players where id = p_id for update;
  if b is null then return false; end if;
  for k, n in select key, value::int from jsonb_each_text(p_need) loop
    if coalesce((b->>k)::int, 0) < n then return false; end if;
    b := jsonb_set(b, array[k], to_jsonb(coalesce((b->>k)::int, 0) - n));
  end loop;
  update public.players set boosters = b where id = p_id;
  return true;
end $$;

create or replace function public.grant_items(p_id uuid, p_crystals int, p_boosters jsonb)
returns void language plpgsql as $$
declare b jsonb; k text; n int;
begin
  select boosters into b from public.players where id = p_id for update;
  if b is null then return; end if;
  for k, n in select key, value::int from jsonb_each_text(p_boosters) loop
    b := jsonb_set(b, array[k], to_jsonb(coalesce((b->>k)::int, 0) + n));
  end loop;
  update public.players set boosters = b, crystals = greatest(0, crystals + p_crystals) where id = p_id;
  if p_crystals <> 0 then perform public.mirror_crystals(p_id); end if;
end $$;

create or replace function public.buy_booster(p_id uuid, p_item text, p_price int)
returns boolean language plpgsql as $$
declare ok boolean;
begin
  update public.players
     set crystals = crystals - p_price,
         boosters = jsonb_set(boosters, array[p_item], to_jsonb(coalesce((boosters->>p_item)::int, 0) + 1))
   where id = p_id and crystals >= p_price
  returning true into ok;
  if ok then perform public.mirror_crystals(p_id); end if;
  return coalesce(ok, false);
end $$;

create or replace function public.settle_season(p_id uuid, p_season int, p_reward int, p_reset_above int, p_info jsonb)
returns boolean language plpgsql as $$
declare ok boolean;
begin
  update public.players
     set season = p_season, crystals = crystals + p_reward, last_reward = p_info,
         trophies = case when trophies > p_reset_above then p_reset_above + (trophies - p_reset_above) / 2 else trophies end
   where id = p_id and season < p_season
  returning true into ok;
  if ok then perform public.mirror_crystals(p_id); end if;
  return coalesce(ok, false);
end $$;

create or replace function public.set_quests(p_id uuid, p_quests jsonb, p_rev int)
returns boolean language sql as $$
  with u as (update public.players set quests = p_quests, quests_rev = quests_rev + 1
              where id = p_id and quests_rev = p_rev returning 1)
  select exists (select 1 from u);
$$;

revoke all on function public.mirror_crystals(uuid) from public, anon, authenticated;
revoke all on function public.adjust_player(uuid, int, int, timestamptz, int) from public, anon, authenticated;
revoke all on function public.take_boosters(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.grant_items(uuid, int, jsonb) from public, anon, authenticated;
revoke all on function public.buy_booster(uuid, text, int) from public, anon, authenticated;
revoke all on function public.settle_season(uuid, int, int, int, jsonb) from public, anon, authenticated;
revoke all on function public.set_quests(uuid, jsonb, int) from public, anon, authenticated;
grant execute on function public.mirror_crystals(uuid), public.adjust_player(uuid, int, int, timestamptz, int),
  public.take_boosters(uuid, jsonb), public.grant_items(uuid, int, jsonb), public.buy_booster(uuid, text, int),
  public.settle_season(uuid, int, int, int, jsonb), public.set_quests(uuid, jsonb, int) to service_role;
