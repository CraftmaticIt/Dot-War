-- Atomic server operations (review fixes): compare-and-swap on colonies, atomic counters,
-- single-settlement attack claims, one live attack per attacker.

alter table public.colonies add column if not exists rev int not null default 0;

alter table public.attacks drop constraint if exists attacks_status_check;
alter table public.attacks add constraint attacks_status_check
  check (status in ('open', 'settling', 'done', 'abandoned'));

drop index if exists public.attacks_one_open_per_defender;
create unique index if not exists attacks_one_live_per_defender on public.attacks (defender)
  where status in ('open', 'settling');
create unique index if not exists attacks_one_live_per_attacker on public.attacks (attacker)
  where status in ('open', 'settling');

-- trophies = max(0, trophies + d); attacks += da; optional shield; optional crystals cap.
create or replace function public.adjust_player(p_id uuid, p_dtrophies int, p_dattacks int,
  p_shield timestamptz default null, p_crystals_max int default null)
returns void language sql as $$
  update public.players
     set trophies = greatest(0, trophies + p_dtrophies),
         attacks = attacks + p_dattacks,
         shield_until = coalesce(p_shield, shield_until),
         crystals = case when p_crystals_max is null then crystals else least(crystals, greatest(0, p_crystals_max)) end
   where id = p_id;
$$;

-- If dots >= p_min: zero them, mark attack_open, return the dots; else -1.
create or replace function public.consume_dots(p_id uuid, p_min int)
returns int language plpgsql as $$
declare d int;
begin
  select coalesce((data->>'dots')::int, 0) into d from public.colonies where player_id = p_id for update;
  if d is null or d < p_min then return -1; end if;
  update public.colonies
     set data = jsonb_set(jsonb_set(jsonb_set(data, '{dots}', '0'), '{dots_rem}', '0'), '{attack_open}', '1'),
         rev = rev + 1
   where player_id = p_id;
  return d;
end $$;

-- energy = max(0, energy + delta); optionally clear attack_open.
create or replace function public.credit_energy(p_id uuid, p_delta int, p_clear_open boolean)
returns void language sql as $$
  update public.colonies
     set data = case when p_clear_open
                  then jsonb_set(jsonb_set(data, '{energy}', to_jsonb(greatest(0, coalesce((data->>'energy')::int, 0) + p_delta))), '{attack_open}', '0')
                  else jsonb_set(data, '{energy}', to_jsonb(greatest(0, coalesce((data->>'energy')::int, 0) + p_delta))) end,
         rev = rev + 1
   where player_id = p_id;
$$;

-- Only the service role (Edge Functions) may call these.
revoke all on function public.adjust_player(uuid, int, int, timestamptz, int) from public, anon, authenticated;
revoke all on function public.consume_dots(uuid, int) from public, anon, authenticated;
revoke all on function public.credit_energy(uuid, int, boolean) from public, anon, authenticated;
grant execute on function public.adjust_player(uuid, int, int, timestamptz, int) to service_role;
grant execute on function public.consume_dots(uuid, int) to service_role;
grant execute on function public.credit_energy(uuid, int, boolean) to service_role;
