-- Dot War schema. Clients only read their own rows; every write goes through
-- Edge Functions with the service role (RLS bypass), which validate it.

create table if not exists public.players (
  id uuid primary key references auth.users (id) on delete cascade,
  trophies int not null default 0 check (trophies >= 0),
  attacks int not null default 0,
  crystals int not null default 50 check (crystals >= 0),
  shield_until timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists players_trophies_idx on public.players (trophies);

create table if not exists public.colonies (
  player_id uuid primary key references public.players (id) on delete cascade,
  data jsonb not null,
  synced_at timestamptz not null default now()
);

create table if not exists public.attacks (
  id uuid primary key default gen_random_uuid(),
  attacker uuid not null references public.players (id) on delete cascade,
  defender uuid references public.players (id) on delete set null,
  bot jsonb,
  snapshot jsonb not null,
  dots int not null check (dots >= 0),
  seed int not null,
  loot_pool int not null,
  status text not null default 'open' check (status in ('open', 'done', 'abandoned')),
  commands jsonb,
  result jsonb,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index if not exists attacks_attacker_idx on public.attacks (attacker, status);
create index if not exists attacks_defender_idx on public.attacks (defender, status);
-- Race guard: a defender can be under at most one open attack.
create unique index if not exists attacks_one_open_per_defender on public.attacks (defender) where status = 'open';

alter table public.players enable row level security;
alter table public.colonies enable row level security;
alter table public.attacks enable row level security;

create policy players_select_own on public.players for select to authenticated using (id = auth.uid());
create policy colonies_select_own on public.colonies for select to authenticated using (player_id = auth.uid());
create policy attacks_select_involved on public.attacks for select to authenticated
  using (attacker = auth.uid() or defender = auth.uid());
