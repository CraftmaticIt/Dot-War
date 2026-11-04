# Stage 3: Attack on a Colony Snapshot + Bot Colonies — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gracz atakuje kolonię-bota (generowaną wg trofeów) rojem Kropek z własnych generatorów: 3 węzły wejścia, 3 minuty, 0–3 gwiazdki, łup Energii, trofea. Obrona = stałe garnizony, wieże z poziomem, Mur (twardy węzeł), ukryte Pułapki.

**Architecture:** `sim/` dostaje dwie cechy węzła (`trap`, `tower_lvl`) bez zmiany hashy istniejących wektorów. Nowy moduł `battle/` (czysta logika): `AttackSetup` składa `SimWorld` z `SimGraph` obrońcy + wejść atakującego, `BattleMatch` pilnuje końca bitwy i liczy wynik. `ai/bot_colony.gd` generuje deterministyczne kolonie. `game/battle_view` to UI nad `BattleMatch`.

**Tech Stack:** Godot 4.7.2, GDScript, GUT 9.7.1.

**Spec:** `docs/superpowers/specs/2026-11-03-dot-war-design.md` (sekcje 2.2, 2.3, 3, 4, 6, „Decyzje etapu 3”)

## Global Constraints

- `sim/` i `battle/`: tylko int, bez `Time`/`randf`; losowość tylko `SimRng`.
- Istniejące wektory `tests/vectors/v001..v004` muszą dalej przechodzić bez regeneracji (kontrakt TS).
- Czas ataku: `180 s = 3600` ticków.
- Gwiazdki: +1 za ≥50% węzłów obrońcy, +1 za przejęty Rdzeń, +1 za 100%.
- Garnizon: `core 30×L`, `wall 25×L`, `trap 0`, pozostałe `6×L`. Produkcja w bitwie (kropki/s): `core L`, `generator L`, reszta 0.
- Pułapka: obrażenia `10×L` kropek, jednorazowo, niewidoczna w UI atakującego.
- Wieże: `dmg = SPECS.dmg × (2 + tower_lvl) / 3` (poziom 1 = bazowe obrażenia).
- Trofea: wygrana (≥1★) `+10×★`; porażka (0★) `−8`, min 0.
- Minimum 10 Kropek, by zaatakować; wszystkie wysłane Kropki są zużywane.

## Review Focus

1. Pułapka i wroga grupa przylatują w tym samym ticku, co inna grupa → pułapka odpala raz, na grupie o niższym `id` (test w Task 1).
2. Atakujący nie ma już kropek (garnizony wejść 0, brak grup, brak własnych węzłów z produkcją) przed upływem czasu → bitwa kończy się od razu (test w Task 4).
3. Kolonia-bot z jednym węzłem (tylko Rdzeń) → setup i wynik działają; 100% = przejęty Rdzeń (test w Task 3 i 4).
4. Łup przy 0★ → 0 Energii, trofea nie spadają poniżej 0 (test w Task 4/5).
5. Zbyt mało Kropek (< 10) → atak zablokowany, stan kolonii bez zmian (test w Task 5).

---

### Task 1: Sim — pułapki i poziomy wież (+ wektor v005)

**Files:** Modify `sim/graph.gd`, `sim/world.gd`, `sim/towers.gd`, `tools/gen_vectors.gd`; Create `tests/vectors/v005_traps_levels.json`; Test `tests/unit/test_traps_levels.gd`

**Interfaces:**
- `SimGraph.add_node(id, x, y, owner, garrison, prod_per_sec, tower := "", trap := 0, tower_lvl := 1)`; `node()` ma klucze `trap`, `tower_lvl`; `to_dict` zawsze je zapisuje; `from_dict` domyślnie `trap 0`, `tower_lvl 1`.
- `SimWorld._arrive`: gdy `n.trap > 0` i `g.owner != n.owner` → `kill = min(n.trap, g.count)`, `g.count -= kill`, `n.trap = 0`, zdarzenie `{"type":"trap_triggered","node":id,"group":gid,"killed":kill}`; gdy `g.count == 0` → koniec (brak walki), inaczej normalna walka.
- `SimWorld.canonical()`: węzeł z `trap > 0` dopisuje `,t<trap>` na końcu swojego segmentu (węzły bez pułapki — format bez zmian → stare hashe bez zmian).
- `SimTowers`: `dmg = spec.dmg * (2 + n.tower_lvl) / 3`.

- [ ] **Step 1:** Testy: `test_trap_kills_and_disarms`, `test_trap_ignores_owner_groups`, `test_trap_kills_whole_small_group_no_fight` (garnizon bez zmian), `test_trap_same_tick_lower_id_only` (RF 1), `test_tower_lvl_scales_damage` (lvl 1 = 200, lvl 4 = 400 Fx/tick), `test_graph_dict_has_trap_and_lvl`, `test_old_vectors_unchanged` (istniejący `test_vectors` nadal zielony — bez kodu, tylko uruchomienie).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implementacja. **Step 4:** Dopisz v005 w `tools/gen_vectors.gd` (pułapka, mur 50, laser lvl 3, puls lvl 2; koniec w trakcie lotu), wygeneruj, sprawdź że v001–v004 mają te same hashe. Run → PASS.
- [ ] **Step 5:** Commit `feat(sim): hidden traps and tower levels`.

### Task 2: Garnizony i produkcja w bitwie + pełny snapshot

**Files:** Modify `meta/buildings.gd`, `meta/colony.gd`; Test `tests/unit/test_battle_stats.gd`

**Interfaces:**
- `Buildings.garrison(type, level) -> int`, `Buildings.battle_prod(type, level) -> int`, `Buildings.trap_dmg(type, level) -> int` (wartości z Global Constraints).
- `ColonyState.to_sim_graph(owner)` wypełnia: `garrison`, `prod_per_sec = battle_prod`, `trap = trap_dmg`, `tower_lvl = level` (dla wież), reszta jak w etapie 2.
- `ColonyState.to_sim_graph` zwraca też mapowanie: nowa metoda `snapshot_ids() -> Dictionary` (`node_id → Vector2i hex`) w tej samej kolejności co `to_sim_graph`.

- [ ] **Step 1:** Testy: `test_garrison_table`, `test_battle_prod_table`, `test_trap_dmg_table`, `test_snapshot_fills_battle_stats` (Rdzeń lvl2 → garrison 60, prod 2; laser lvl3 → `tower_lvl 3`; pułapka lvl1 → `trap 10`, garrison 0), `test_snapshot_ids_match_graph`.
- [ ] **Step 2–4:** FAIL → implementacja → PASS. **Step 5:** Commit `feat(meta): battle stats in colony snapshot`.

### Task 3: AttackSetup — wejścia atakującego

**Files:** Create `battle/attack_setup.gd`; Test `tests/unit/test_attack_setup.gd`

**Interfaces:**
- `class_name AttackSetup`
  - `const ATTACKER := 1`, `const DEFENDER := 2`, `const ENTRY_IDS := [1001, 1002, 1003]`, `const ENTRY_GAP := 6000`
  - `static func build(defender: SimGraph, attacker_dots: int, seed: int) -> SimWorld`
- Zasady: wejścia na lewo od kolonii: `x = min_x − ENTRY_GAP`, `y` równomiernie w `[min_y, max_y]` (przy jednym węźle: `y − 4000, y, y + 4000`). Każde wejście łączy się z 2 najbliższymi węzłami obrońcy (remis → niższe id; przy 1 węźle — z tym jednym). Kropki dzielone równo, reszta do pierwszego wejścia. Wejścia: `owner ATTACKER`, `prod 0`.

- [ ] **Step 1:** Testy: `test_three_entries_left_of_colony`, `test_dots_split_with_remainder` (10 → 4,3,3), `test_entry_links_two_nearest`, `test_single_node_colony` (RF 3), `test_defender_nodes_untouched`.
- [ ] **Step 2–4:** FAIL → implementacja → PASS. **Step 5:** Commit `feat(battle): attack setup with entry nodes`.

### Task 4: BattleMatch — koniec bitwy, gwiazdki, łup, trofea

**Files:** Create `battle/match.gd`; Test `tests/unit/test_battle_match.gd`

**Interfaces:**
- `class_name BattleMatch`
  - `const DURATION_TICKS := 3600`
  - `func _init(world: SimWorld, core_node: int, loot_pool: int)`
  - `func send(from: int, to: int, percent: int) -> void` (kolejkuje `send` jako ATTACKER na bieżący tick)
  - `func step() -> void`; `var over: bool`
  - `func progress() -> Dictionary` — `{"destroyed_pct":int, "core":bool, "stars":int, "ticks_left":int}`
  - `func result() -> Dictionary` — `{"stars":int, "destroyed_pct":int, "loot":int, "trophies":int}`; `loot = loot_pool * destroyed_pct / 100` przy ≥1★, inaczej 0; `trophies` wg Global Constraints (delta).
- Koniec gdy: czas minął, albo 100%, albo atakujący nie ma żadnych kropek (suma garnizonów jego węzłów + grup == 0 i żaden jego węzeł nie ma `prod_per_sec > 0`).
- `destroyed_pct = 100 × przejęte_węzły_obrońcy / wszystkie_węzły_obrońcy` (int).

- [ ] **Step 1:** Testy: `test_time_limit_ends`, `test_full_capture_three_stars`, `test_half_capture_one_star`, `test_core_only_star`, `test_no_dots_left_ends_early` (RF 2), `test_zero_stars_no_loot_trophies_minus` (RF 4), `test_loot_scales_with_destroyed`, `test_send_after_over_ignored`.
- [ ] **Step 2–4:** FAIL → implementacja → PASS. **Step 5:** Commit `feat(battle): match end conditions, stars, loot, trophies`.

### Task 5: Boty-kolonie, trofea i rozliczenie ataku w kolonii

**Files:** Create `ai/bot_colony.gd`; Modify `meta/colony.gd`; Test `tests/unit/test_bot_colony.gd`, `tests/unit/test_colony_attack.gd`

**Interfaces:**
- `class_name BotColony` — `static func generate(trophies: int, seed: int) -> Dictionary` → `{"colony": ColonyState, "loot_pool": int}`:
  - `core_level = clampi(1 + trophies / 200, 1, 5)`; liczba węzłów = `max_nodes(core_level) − rng.range_i(3)`; wzrost od (0,0): losowe wolne pole przyległe (lista kandydatów posortowana po `(q,r)`, wybór `rng.range_i`).
  - typy (wagi): mine 3, storage 1, generator 1, laser 2, pulse 2, wall 2, trap 1; poziom = `core_level − rng.range_i(2)`, min 1.
  - `loot_pool = 300 + 3 × trophies`.
- `ColonyState`: nowe pola `trophies := 0`, `attacks := 0` (w `to_dict/from_dict`, domyślnie 0 — stare zapisy działają).
  - `const MIN_ATTACK_DOTS := 10`
  - `func can_attack(now:int) -> String` (`""` / `"few_dots"`)
  - `func begin_attack(now:int) -> Dictionary` — `collect(now)`; przy błędzie `{"error":code}` bez zmian stanu (RF 5); inaczej zużywa wszystkie `dots`, `attacks += 1`, zwraca `{"dots":n, "seed": attacks * 7919 + trophies}`.
  - `func apply_result(r: Dictionary) -> void` — `energy += r.loot` (może przekroczyć limit), `trophies = max(0, trophies + r.trophies)`.

- [ ] **Step 1:** Testy: `test_bot_deterministic` (ten sam seed → ten sam `to_dict`), `test_bot_scales_with_trophies` (0 → Rdzeń 1; 900 → Rdzeń 5), `test_bot_connected` (każdy węzeł osiągalny z Rdzenia w `to_sim_graph`), `test_bot_within_node_limit`, `test_can_attack_few_dots` (RF 5), `test_begin_attack_consumes_dots`, `test_apply_result_loot_above_cap`, `test_trophies_floor_zero` (RF 4), `test_old_save_without_trophies_loads`.
- [ ] **Step 2–4:** FAIL → implementacja → PASS. **Step 5:** Commit `feat: bot colonies, trophies and attack accounting`.

### Task 6: Ekran bitwy + nawigacja

**Files:** Create `game/battle_view.tscn`, `game/battle_view.gd`; Modify `game/colony_view.gd` (przycisk „Atak”, trofea w HUD), `game/prototype.gd` (bez zmian funkcji — zostaje jako scena dev), `README.md`; Test `tests/unit/test_battle_view_logic.gd`

**Interfaces:**
- `battle_view.gd`: `static func fit_transform(bounds: Rect2i, screen: Vector2, margin: float) -> Transform2D` (Fx → px, mapa wpasowana w ekran); `var setup := {}` wstrzykiwany przed `_ready` (`{"colony": ColonyState, "now": int}`) — w trybie gry; `--shot <png>` tworzy demo (bot 300 trofeów, 60 kropek, bot-atakujący `SimpleBot` dla ownera 1).
- Zachowanie:
  - Kolonia → „Atak” (zablokowany z powodem przy < 10 kropek) → `begin_attack` → `BotColony.generate(trophies, seed)` → `AttackSetup.build` → `BattleMatch`.
  - Render: węzły jak `NodeView`, rój `SwarmRenderer`, wieże z poziomem; **pułapki rysowane jak zwykły węzeł** obrońcy; przeciąganie z własnego węzła = `send` z wybranym % (25/50/75/100).
  - HUD: czas `m:ss`, `★` zdobyte, `% zniszczeń`; przycisk „Poddaj się” → koniec.
  - Ekran końca: gwiazdki, łup, trofea, „Wróć” → `apply_result`, `SaveStore.save`, powrót do kolonii.
- [ ] **Step 1:** Testy: `test_fit_transform_maps_bounds_into_screen` (rogi bounds trafiają w `[margin, screen − margin]`), `test_fit_transform_keeps_aspect`.
- [ ] **Step 2:** FAIL → implementacja → PASS.
- [ ] **Step 3:** Screenshot `xvfb-run … res://game/battle_view.tscn -- --shot docs/screens/stage3.png` po ~15 s bitwy — obejrzyj.
- [ ] **Step 4:** CI zielone. **Step 5:** Commit `feat(game): battle screen with stars, loot and trophies`.
