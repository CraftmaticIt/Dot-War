# Stage 4: Supabase Backend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Konta anonimowe, kolonia zapisywana na serwerze z kontrolą wiarygodności, matchmaking (gracze ±200 trofeów, inaczej bot), ataki weryfikowane serwerowo przez odtworzenie komend w porcie TS symulacji, tarcza i dziennik obrony.

**Architecture:** `server/` to czysty TypeScript (bez zależności od Deno/Node API) — port `sim/`, części `meta/`, `battle/`, `ai/bot_colony` oraz logika serwera (`server/core/`) z repozytorium danych za interfejsem. `supabase/functions/*` to cienkie wrappery Deno (supabase-js, service role) nad `server/core`. Wdrożenie wyłącznie przez GitHub Actions z sekretami. Klient Godot dostaje `net/` (HTTP + auth) z trybem offline jako fallback (lokalne boty z etapu 3).

**Tech Stack:** TypeScript (Node 22 `--experimental-strip-types` + `node:test` lokalnie i w CI; Deno w Edge Functions), Supabase (Postgres, Auth anonymous, Edge Functions, CLI), Godot 4.7.2 `HTTPRequest`.

**Spec:** `docs/superpowers/specs/2026-11-03-dot-war-design.md` (sekcje 4, 7, 8, „Decyzje etapu 4”)

## Global Constraints

- Port TS: `/` → `Math.trunc`, `%` jak JS, hash/RNG `Math.imul(...) >>> 0` i `>>> 0` po przesunięciach (kontrakt z `sim/fx.gd`). Wszystkie wektory `tests/vectors/*.json` i nowe `tests/battle_vectors/*.json` muszą dawać identyczne wyniki w GDScript i TS.
- `server/` nie importuje nic spoza siebie (działa w Node i Deno).
- Pola należące do serwera: `trophies`, `attacks`, `attack_open`, `crystals` (klient może tylko wydawać). Serwer nadpisuje je przy każdym `sync`.
- Matchmaking: `|Δtrofea| ≤ 200`, obrońca bez aktywnej tarczy, nie jest atakowany (otwarty atak < 10 min), nie sam siebie; losowo spośród max 20 kandydatów; brak → bot (`BotColony`, seed z serwera).
- Tarcza obrońcy 8 h po ataku z ≥1★. Łup z gracza: `min(niechroniona Energia, loot_pool × %)`, niechroniona = 80% Energii obrońcy.
- Otwarty atak starszy niż 10 min = porażka atakującego (0★, −8) przy następnym `find_opponent`/`sync`.
- Sekrety tylko w GitHub Actions: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`. URL i klucz anon pobierane w CI (`supabase projects api-keys`) i wpisywane do `net/config.json` przed eksportem APK. Nic z tego nie trafia do repo ani czatu.
- Brak sieci → gra działa offline jak w etapie 3 (ataki na lokalne boty, bez zmian trofeów serwerowych).

## Review Focus

1. Klient wysyła zawyżoną Energię/Kropki/Kryształy lub zmienione trofea → serwer odrzuca i zwraca swój stan (test w Task 4).
2. Replay z komendami po końcu czasu / od cudzego ownera / zły JSON → komendy odrzucone jak w symulacji, wynik deterministyczny, brak crasha (test w Task 2 i 4).
3. Dwóch atakujących wybiera tego samego obrońcę naraz → drugi dostaje innego (blokada atakiem otwartym; test w Task 4).
4. Token wygasł → klient odświeża sesję raz i ponawia żądanie; brak sieci → tryb offline (test w Task 6).
5. `finish_attack` wysłane dwa razy → wynik naliczony raz (idempotencja po `attack_id`; test w Task 4).

---

### Task 1: Port TS symulacji + wektory

**Files:** Create `server/sim/fx.ts`, `rng.ts`, `graph.ts`, `world.ts`, `towers.ts`, `replay.ts`, `server/test/vectors.test.ts`, `server/package.json` (`"type":"module"`, skrypt `test`: `node --experimental-strip-types --test test/`), `.github/workflows/server.yml` (job `server-test`)

**Interfaces:**
- `Fx.mul/div/isqrt/dist`, `SimRng(seed).nextU32()/rangeI(n)`, `SimGraph` (`addNode(id,x,y,owner,garrison,prod,tower?,trap?,towerLvl?)`, `link`, `node`, `nodeIds`, `neighbors`, `path`, `toDict`, `static fromDict`), `SimWorld` (`TICK_HZ`, `queue`, `step`, `groups`, `events`, `canonical()`, `stateHash()`, `groupPos`), `SimTowers.apply`, `SimReplay.run(vector)` — 1:1 z GDScript (nazwy camelCase).

- [ ] **Step 1:** `vectors.test.ts`: dla każdego `tests/vectors/*.json` → `SimReplay.run(v).stateHash() === v.expected_hash` oraz `canonical()` porównane z wartością zapisaną przez nowy `tools/gen_vectors.gd` w polu `expected_canonical` (dopisać generowanie; hash bez zmian).
- [ ] **Step 2:** `npm test` (w `server/`) → FAIL. **Step 3:** Port. **Step 4:** PASS dla v001–v006.
- [ ] **Step 5:** Commit `feat(server): TypeScript port of the swarm simulation`.

### Task 2: Port TS meta/battle/bot + wektory bitew

**Files:** Create `server/game/buildings.ts`, `hex.ts`, `colony.ts` (tylko: `fromDict`, `toDict`, `snapshotIds`, `toSimGraph`, `collect`, `energyCap`, `dotsCap`), `attack_setup.ts`, `match.ts`, `bot_colony.ts`; `tools/gen_battle_vectors.gd`; `tests/battle_vectors/*.json`; Test `server/test/battle_vectors.test.ts`, `server/test/colony.test.ts`

**Interfaces:**
- Wektor bitwy: `{"defender": <ColonyState.to_dict>|null, "bot": {"trophies":int,"seed":int}|null, "dots":int, "seed":int, "commands":[{"tick","from","to","percent"}], "expected": {"result": {...}, "hash": int}}`. Komendy aplikowane przez `BattleMatch.send` na wskazanym ticku; bitwa do `over`.
- `tools/gen_battle_vectors.gd` generuje ≥5 wektorów: bot 0 i 600 trofeów, kolonia gracza z pułapką i murem, poddanie (komendy kończą się wcześnie), komendy z nieprawidłowymi polami (RF 2).

- [ ] **Step 1:** Testy: wszystkie `battle_vectors` → identyczny `result` i `hash` w TS; `colony.test.ts`: `collect` dla przypadków z `test_colony_economy.gd` (1 h, 8 h cap, budowa w środku okna, cofnięty zegar), `BotColony.generate(250,42)` = JSON zapisany przez GDScript w wektorze.
- [ ] **Step 2–4:** FAIL → port → PASS. **Step 5:** Commit `feat(server): port battle rules and bot colonies, battle vectors`.

### Task 3: Projekt Supabase — konfiguracja, schemat, RLS

**Files:** Create `supabase/config.toml` (`[auth] enable_anonymous_sign_ins = true`), `supabase/migrations/20261104000000_init.sql`; Test `server/test/schema.test.ts` (statyczny: SQL zawiera RLS dla każdej tabeli)

**Schemat:**
- `players(id uuid pk references auth.users, trophies int default 0, attacks int default 0, crystals int default 50, shield_until timestamptz, created_at timestamptz default now())`
- `colonies(player_id uuid pk references players, data jsonb not null, synced_at timestamptz not null)`
- `attacks(id uuid pk default gen_random_uuid(), attacker uuid references players, defender uuid null references players, bot jsonb null, snapshot jsonb not null, dots int, seed int, loot_pool int, status text check (status in ('open','done','abandoned')), commands jsonb, result jsonb, created_at timestamptz default now(), finished_at timestamptz)`; indeks `(defender, status)`.
- `defense_log` = widok `attacks` gdzie `defender = auth.uid()` i `status='done'`.
- RLS: włączone na wszystkich; `select` własnych wierszy `players`/`colonies`; `attacks` select gdzie `attacker = auth.uid() or defender = auth.uid()`; brak insert/update z klienta (tylko service role w funkcjach).

- [ ] **Step 1:** `schema.test.ts`: każda `create table` ma `enable row level security`; brak polityk `insert/update` dla `authenticated`.
- [ ] **Step 2–4:** FAIL → SQL → PASS. **Step 5:** Commit `feat(supabase): schema, RLS, anonymous auth config`.

### Task 4: Logika serwera (czysta, testowana)

**Files:** Create `server/core/repo.ts` (interfejs `Repo` + `MemoryRepo` do testów), `server/core/sync.ts`, `server/core/matchmaking.ts`, `server/core/finish.ts`; Test `server/test/core.test.ts`

**Interfaces:**
- `syncColony(repo, uid, clientColony, now) -> {colony, accepted: boolean, reason?}`:
  - brak zapisu → przyjmij (pola serwerowe z `players`);
  - inaczej `elapsed = now − synced_at` (≥0); dozwolone: `energy ≤ stored.energy + maxEnergyGain(stored, client, elapsed) + creditedLoot`, `dots ≤ stored.dots + maxDotsGain(...)`, `crystals ≤ players.crystals`, poziomy budynków rosną max o 1 względem zapisu, a koszt każdego nowego poziomu odjęty (suma `energy + Σcost` nie rośnie ponad limit produkcji); `maxEnergyGain` liczone z wyższego z poziomów (zapis vs klient) × `min(elapsed, 8h)`;
  - odrzucenie → zwróć zapis serwera; pola `trophies/attacks/attack_open/crystals` zawsze z `players`.
- `findOpponent(repo, uid, now, rand) -> {attack_id, snapshot, loot_pool, seed, dots, bot?}` — rozlicza porzucone ataki (>10 min), zużywa Kropki atakującego (z zapisu serwera, min 10, inaczej błąd `few_dots`), wybiera obrońcę wg Global Constraints, zapisuje `attacks(status open)` ze snapshotem.
- `finishAttack(repo, uid, attack_id, commands, now) -> {result}` — tylko właściciel i `status open`; replay `AttackSetup+BattleMatch` (TS) z komendami; drugi raz → zwraca zapisany wynik (RF 5); nalicza łup/trofea atakującemu; obrońcy: `−loot` Energii (z jego `colonies.data`), `−trofea` (połowa zysku atakującego, min 0), tarcza 8 h przy ≥1★.

- [ ] **Step 1:** Testy (`MemoryRepo`): `test_first_sync_accepted`, `test_inflated_energy_rejected` (RF 1), `test_inflated_crystals_rejected`, `test_server_fields_overwritten`, `test_level_jump_rejected`, `test_legit_progress_accepted` (8 h kopalni), `test_match_within_200`, `test_skips_shielded_and_open`, `test_two_attackers_get_different_defenders` (RF 3), `test_fallback_bot`, `test_abandoned_attack_resolved`, `test_finish_replays_and_scores`, `test_finish_twice_idempotent` (RF 5), `test_finish_foreign_attack_forbidden`, `test_defender_shield_and_loss`, `test_malformed_commands_ignored` (RF 2).
- [ ] **Step 2–4:** FAIL → implementacja → PASS. **Step 5:** Commit `feat(server): sync, matchmaking and attack verification core`.

### Task 5: Edge Functions + wdrożenie CI

**Files:** Create `supabase/functions/_shared/supa_repo.ts` (`Repo` na supabase-js, service role z env funkcji), `supabase/functions/sync_colony/index.ts`, `find_opponent/index.ts`, `finish_attack/index.ts`, `.github/workflows/supabase.yml`, `scripts/smoke_backend.mjs`

**Zachowanie:**
- Każda funkcja: `Authorization: Bearer <jwt>` → `auth.getUser()` → `uid`; JSON body; błędy jako `{error}` z kodem 400/401/403/409.
- `supabase.yml` (on push do `main` zmieniający `supabase/**` lub `server/**`, oraz `workflow_dispatch`): `supabase/setup-cli` → `supabase link --project-ref $SUPABASE_PROJECT_REF -p $SUPABASE_DB_PASSWORD` → `supabase db push` → `supabase config push` → `supabase functions deploy` (funkcje kopiują `server/` przez import względny) → `smoke_backend.mjs` (anonimowe konto → sync → find_opponent → finish_attack z pustymi komendami → oczekiwany wynik 0★).
- Gdy sekretów brak → job kończy się komunikatem „Supabase not configured” bez błędu (repo działa zanim właściciel założy projekt).
- `android.yml`: krok przed eksportem pobiera URL + anon key (`supabase projects api-keys --project-ref … -o json`) i zapisuje `net/config.json`; bez sekretów → plik z pustymi wartościami (tryb offline).

- [ ] **Step 1:** Test `server/test/functions_shape.test.ts`: każda funkcja eksportuje handler `(req, deps) => Response`, testowany z `MemoryRepo` i fałszywym `getUser` (401 bez tokenu, 200 z tokenem).
- [ ] **Step 2–4:** FAIL → implementacja → PASS. **Step 5:** Commit; po pushu CI: `server-test` zielony, `supabase` = „not configured” albo zielony smoke test (gdy sekrety są).

### Task 6: Klient Godot — konto, sync, atak online

**Files:** Create `net/config.json` (puste wartości w repo), `net/backend.gd` (`class_name Backend`), `net/transport.gd` (interfejs + `HttpTransport` na `HTTPRequest`, `FakeTransport` do testów); Modify `game/colony_view.gd`, `game/battle_view.gd`, `meta/colony.gd`; Test `tests/unit/test_backend.gd`

**Interfaces:**
- `Backend` (autoload): `func is_configured() -> bool`, `func ensure_session() -> bool` (anonimowy signup przy pierwszym starcie, `user://auth.json`, odświeżenie tokenu przy 401 — raz, potem ponów żądanie; RF 4), `func sync(colony: ColonyState) -> ColonyState` (zwraca stan serwera; offline → wejście bez zmian), `func find_opponent() -> Dictionary`, `func finish_attack(id: String, commands: Array) -> Dictionary`; wszystkie `async` (`await`).
- `BattleView`: tryb online — snapshot z serwera zamiast `BotColony` lokalnie, zapis komend gracza (`{tick, from, to, percent}`), po końcu `finish_attack` i wynik serwera (gdy różni się od lokalnego → pokaż serwerowy).
- `ColonyView`: `sync` przy starcie, po akcji (z debounce 3 s) i przy pauzie; HUD pokazuje „online/offline”; toast „Twoja kolonia została zaatakowana: −E energii” z `defense_log` od ostatniego logowania.
- [ ] **Step 1:** Testy z `FakeTransport`: `test_signup_once_and_reuse_token`, `test_refresh_on_401_then_retry`, `test_offline_returns_local_state`, `test_sync_adopts_server_state`, `test_battle_records_commands`.
- [ ] **Step 2–4:** FAIL → implementacja → PASS. **Step 5:** Screenshot kolonii z „offline” (brak konfiguracji w kontenerze) i CI zielone. Commit `feat(net): anonymous account, server sync and online attacks`.
