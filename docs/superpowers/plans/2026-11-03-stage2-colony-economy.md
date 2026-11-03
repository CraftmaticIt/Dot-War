# Stage 2: Colony Building + Economy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gracz buduje kolonię na siatce heksów (8 typów budynków, 5 poziomów), zbiera Energię i Kropki w czasie rzeczywistym (także offline, max 8 h), przyspiesza budowy Kryształami; kolonia zapisuje się lokalnie i eksportuje do `SimGraph` (snapshot do ataków w etapie 3).

**Architecture:** Nowy moduł `meta/` — czysta logika bez scen, int-only, czas wstrzykiwany jako `now: int` (sekundy unix) → w pełni testowalne i gotowe do weryfikacji serwerowej. `game/colony_view` to cienka warstwa UI nad `ColonyState`. Stage 1 (`sim/`) bez zmian poza konsumpcją snapshotu.

**Tech Stack:** Godot 4.7.2, GDScript, GUT 9.7.1 (jak etap 1).

**Spec:** `docs/superpowers/specs/2026-11-03-dot-war-design.md` (sekcje 2.1, 3, 4, „Decyzje etapu 2”)

## Global Constraints

- `meta/` jak `sim/`: tylko int, bez `Time`/`randf` wewnątrz logiki; czas zawsze parametrem `now`.
- Startowy stan: Rdzeń poz. 1 na (0,0), Kopalnia poz. 1 na (1,0), Energia 500, Kryształy 50, Kropki 0.
- Limit węzłów (łącznie z Rdzeniem) wg poziomu Rdzenia: `[6, 9, 12, 16, 20]`; maks. poziom innych budynków = poziom Rdzenia.
- Offline: okno naliczania max `8 * 3600` s; ujemny upływ czasu (cofnięty zegar) = 0.
- Przyspieszenie: `ceil(pozostałe_s / 60)` Kryształów, min 1.
- Budowniczowie: 2 równoległe budowy/ulepszenia.
- Ręczna konfiguracja właściciela: zero.

## Review Focus

1. Zegar cofnięty (now < last_collect) → nic nie naliczone, `last_collect` nie cofa się (test w Task 4).
2. Budowa kończy się w środku okna offline → produkcja do `build_end` po starym poziomie, potem po nowym (test w Task 4).
3. Magazyn pełny → nadwyżka tracona, bez ujemnych/overflow (test w Task 4).
4. Uszkodzony/obcy plik zapisu → start ze stanem domyślnym + zdarzenie, bez crasha (test w Task 5).
5. Próba budowy bez Energii / na zajętym polu / nieprzyległym / ponad limit / przy 2 zajętych budowniczych → kod błędu, stan bez zmian (test w Task 3).

---

### Task 1: Hex — współrzędne osiowe

**Files:** Create `meta/hex.gd`; Test `tests/unit/test_hex.gd`

**Interfaces:**
- Produces: `class_name Hex`
  - `const SIZE := 2000` (Fx, promień heksa; pointy-top)
  - `static func key(q:int, r:int) -> String` → `"q,r"`; `static func parse(k:String) -> Vector2i`
  - `static func neighbors(q:int, r:int) -> Array[Vector2i]` — kolejność stała: `(+1,0),(+1,-1),(0,-1),(-1,0),(-1,+1),(0,+1)`
  - `static func to_fx(q:int, r:int) -> Vector2i` — `x = SIZE*(1732*q + 866*r)/1000`, `y = SIZE*(1500*r)/1000` (int, √3≈1.732)
  - `static func distance(a:Vector2i, b:Vector2i) -> int` (odległość w heksach)

- [ ] **Step 1:** Testy: `test_key_roundtrip` (`parse(key(-3,2)) == Vector2i(-3,2)`), `test_neighbors_order`, `test_to_fx_origin` (`(0,0)`), `test_to_fx_q1` (`Vector2i(3464, 0)`), `test_to_fx_r1` (`Vector2i(1732, 3000)`), `test_distance` (`(0,0)`→`(2,-1)` = 2).
- [ ] **Step 2:** `./scripts/test.sh` → FAIL (script errors).
- [ ] **Step 3:** Implementacja.
- [ ] **Step 4:** `./scripts/test.sh` → PASS.
- [ ] **Step 5:** Commit `feat(meta): axial hex coordinates`.

### Task 2: Definicje budynków

**Files:** Create `meta/buildings.gd`; Test `tests/unit/test_buildings.gd`

**Interfaces:**
- Produces: `class_name Buildings`
  - `const TYPES := ["core","mine","storage","generator","laser","pulse","wall","trap"]`
  - `const MAX_LEVEL := 5`
  - `static func cost(type:String, level:int) -> int` (Energia za zbudowanie/ulepszenie DO `level`)
  - `static func build_secs(type:String, level:int) -> int`
  - `static func energy_per_hour(type:String, level:int) -> int` (tylko mine, inne 0)
  - `static func dots_per_hour(type:String, level:int) -> int` (tylko generator)
  - `static func energy_cap(type:String, level:int) -> int` (core i storage dodają pojemność)
  - `static func dots_cap(type:String, level:int) -> int` (tylko generator)
  - `static func max_nodes(core_level:int) -> int`
  - `static func tower(type:String) -> String` (`laser`→`"laser"`, `pulse`→`"pulse"`, reszta `""`)
- Wartości (indeks = poziom-1):

| typ | cost | build_secs | efekt |
|---|---|---|---|
| core | 0, 1000, 4000, 12000, 30000 | 0, 300, 3600, 14400, 43200 | energy_cap 1000, 2000, 4000, 8000, 15000 |
| mine | 100, 300, 800, 2000, 5000 | 10, 60, 300, 1800, 7200 | energy_per_hour 100, 200, 350, 550, 800 |
| storage | 150, 400, 1000, 2500, 6000 | 10, 90, 600, 2400, 7200 | energy_cap 1500, 3000, 5000, 8000, 12000 |
| generator | 200, 500, 1200, 3000, 7000 | 20, 120, 600, 2400, 9000 | dots_per_hour 60, 120, 200, 300, 450; dots_cap 50, 80, 120, 170, 230 |
| laser | 250, 600, 1500, 3500, 8000 | 30, 180, 900, 3600, 10800 | (sim: etap 3 skaluje) |
| pulse | 250, 600, 1500, 3500, 8000 | 30, 180, 900, 3600, 10800 | — |
| wall | 50, 150, 400, 1000, 2500 | 5, 30, 180, 900, 3600 | — |
| trap | 100, 250, 600, 1500, 3500 | 10, 60, 300, 1200, 3600 | — |

- [ ] **Step 1:** Testy przypinające tabelę: `test_costs_table` (wszystkie wiersze `cost`), `test_build_secs_table`, `test_mine_rates`, `test_generator_rates_and_caps`, `test_energy_caps_core_storage`, `test_max_nodes` (`[6,9,12,16,20]`), `test_tower_mapping`, `test_unknown_type_returns_zero`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implementacja (jeden `const TABLE := {type: {field: [..5]}}`).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(meta): building definitions`.

### Task 3: ColonyState — budowa, ulepszanie, przyspieszanie

**Files:** Create `meta/colony.gd`; Test `tests/unit/test_colony_build.gd`

**Interfaces:**
- Consumes: `Hex`, `Buildings`.
- Produces: `class_name ColonyState`
  - pola: `cells: Dictionary` (`Hex.key` → `{"type":String,"level":int,"build_end":int,"target_level":int}`; `build_end == 0` = brak budowy), `energy:int`, `crystals:int`, `dots:int`, `last_collect:int`, `energy_rem:int`, `dots_rem:int` (reszty z dzielenia przez 3600, by nic nie ginęło)
  - `const BUILDERS := 2`
  - `static func new_default(now:int) -> ColonyState`
  - `func core_level() -> int`
  - `func can_place(type:String, q:int, r:int, now:int) -> String` — `""` lub kod: `bad_type`, `occupied`, `not_adjacent`, `node_limit`, `no_energy`, `no_builder`, `core_unique`
  - `func place(type:String, q:int, r:int, now:int) -> String` — przy sukcesie: `energy -= cost(type,1)`, komórka `level 0, target_level 1, build_end = now + build_secs(type,1)`; Kopalnia/Generator na poziomie 0 nic nie produkuje
  - `func can_upgrade(q:int, r:int, now:int) -> String` — kody: `empty`, `busy`, `max_level`, `core_limit` (nie-core > poziom Rdzenia), `no_energy`, `no_builder`
  - `func upgrade(q:int, r:int, now:int) -> String` — budynek działa na starym poziomie do `build_end`
  - `func speedup_cost(q:int, r:int, now:int) -> int`; `func speedup(q:int, r:int, now:int) -> String` — kody `not_building`, `no_crystals`; sukces → `build_end = now`
  - `func finish_builds(now:int) -> void` — każda komórka z `0 < build_end <= now` → `level = target_level`, `build_end = 0`
  - `func busy_builders(now:int) -> int`
- Zasady: `collect(now)` (Task 4) jest wołane na początku każdej z mutacji (`place/upgrade/speedup`), żeby produkcja była naliczona przed zmianą stanu.

- [ ] **Step 1:** Testy: `test_default_state`, `test_place_ok_charges_energy_and_starts_timer`, `test_place_errors` (każdy kod z `can_place`, stan niezmieniony — RF 5), `test_third_build_needs_free_builder`, `test_upgrade_ok`, `test_upgrade_errors` (każdy kod), `test_non_core_capped_by_core_level`, `test_finish_builds_levels_up`, `test_speedup_cost_rounding` (61 s → 2, 60 s → 1, 1 s → 1), `test_speedup_finishes_now`, `test_speedup_no_crystals`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implementacja (na tym etapie `collect` jako pusta metoda, wypełniona w Task 4).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(meta): colony placement, upgrades, speedups`.

### Task 4: Ekonomia — naliczanie w czasie i offline

**Files:** Modify `meta/colony.gd`; Test `tests/unit/test_colony_economy.gd`

**Interfaces:**
- Produces: `func collect(now:int) -> Dictionary` — zwraca `{"energy":int,"dots":int,"secs":int}` (ile naliczono); `func energy_cap() -> int` (suma z core+storage, ich bieżące `level`); `func dots_cap() -> int`; `const OFFLINE_CAP_SECS := 28800`.
- Algorytm (int, deterministyczny):
  1. `if now <= last_collect: return zera` (RF 1, `last_collect` bez zmian).
  2. `start = max(last_collect, now - OFFLINE_CAP_SECS)`.
  3. Punkty podziału = posortowane `build_end` z przedziału `(start, now]` + `now`. Dla każdego odcinka `[t0, t1)`: stawki z bieżących poziomów → `energy_rem += rate_e * (t1 - t0)`; `energy += energy_rem / 3600`; `energy_rem %= 3600`; analogicznie kropki; potem `finish_builds(t1)` (RF 2).
  4. Po każdym odcinku: `energy = min(energy, energy_cap())`, `dots = min(dots, dots_cap())`; przy limicie reszta `*_rem = 0` (RF 3).
  5. `last_collect = now`.

- [ ] **Step 1:** Testy: `test_one_hour_mine_lvl1` (+100), `test_partial_seconds_carry_remainder` (2× 1800 s = +100, nie 0), `test_offline_cap_8h` (24 h offline mine lvl1 → +800), `test_clock_backwards_no_gain` (RF 1), `test_build_finishing_mid_window` (upgrade mine 1→2 kończy się po 1800 s z 3600 → 50 + 100 = +150; RF 2), `test_storage_cap_clamps` (RF 3: energy nie przekracza 1000 przy samym Rdzeniu lvl1), `test_generator_dots_and_cap`, `test_place_collects_first` (produkcja naliczona przed odjęciem kosztu).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implementacja.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(meta): real-time and offline economy`.

### Task 5: Snapshot do SimGraph + zapis lokalny

**Files:** Create `meta/save_store.gd`; Modify `meta/colony.gd`; Test `tests/unit/test_colony_snapshot.gd`, `tests/unit/test_save_store.gd`

**Interfaces:**
- Produces:
  - `ColonyState.to_dict() -> Dictionary` / `static func from_dict(d:Dictionary) -> ColonyState` (int-cast wartości z JSON; nieznany typ budynku → komórka pominięta)
  - `ColonyState.to_sim_graph(owner:int) -> SimGraph` — węzeł na komórkę z `level >= 1`; id = indeks w posortowanej liście kluczy (sort po `(q, r)`); pozycja `Hex.to_fx`; `garrison` = 0 (etap 3 ustala obronę), `prod_per_sec` = 0; `tower` = `Buildings.tower(type)`; krawędź między każdą parą sąsiednich zbudowanych komórek
  - `class_name SaveStore` — `const PATH := "user://colony.json"`; `static func save(c:ColonyState, path:String = PATH) -> Error` (zapis do `path + ".tmp"`, potem `DirAccess.rename_absolute`); `static func load_or_default(now:int, path:String = PATH) -> ColonyState` (brak pliku / zły JSON / brak kluczy → `new_default(now)`, `push_warning`)
- [ ] **Step 1:** Testy: `test_dict_roundtrip_through_json`, `test_snapshot_nodes_and_links` (Rdzeń+Kopalnia+Laser w trójkącie → 3 węzły, 3 krawędzie, laser ma `tower == "laser"`), `test_snapshot_skips_unbuilt`, `test_snapshot_ids_stable` (dwa wywołania → identyczny `to_dict()`), `test_save_load_roundtrip` (plik w `user://test_colony.json`), `test_load_missing_file_default`, `test_load_corrupt_file_default` (RF 4), `test_load_unknown_building_skipped`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implementacja.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(meta): colony snapshot to sim graph and local save`.

### Task 6: Ekran kolonii (UI)

**Files:** Create `game/colony_view.tscn`, `game/colony_view.gd`, `game/hex_cell_view.gd`, `game/build_menu.gd`; Modify `project.godot` (`run/main_scene="res://game/colony_view.tscn"`); Test `tests/unit/test_colony_view_logic.gd`

**Interfaces:**
- Consumes: `ColonyState`, `Buildings`, `Hex`, `SaveStore`, `SwarmRenderer.OWNER_COLORS`, `SwarmRenderer.to_px`.
- Produces: `colony_view.gd` — `static func cell_at(px:Vector2, origin:Vector2) -> Vector2i` (piksel → heks, zaokrąglenie cube-round); `static func format_secs(s:int) -> String` (`"45s"`, `"3m 05s"`, `"2h 00m"`).
- Zachowanie:
  - Siatka heksów w promieniu 4 od (0,0), kamera wyśrodkowana; zbudowane = neon w kolorze gracza `#00E5FF` z ikoną-literą typu (C/M/S/G/L/P/W/T) i poziomem; w budowie = przerywany obrys + timer; wolne przyległe = słaby obrys „+”.
  - Tap wolnego przyległego pola → `build_menu` (lista typów z kosztem i czasem, nieaktywne gdy `can_place != ""`, z powodem).
  - Tap budynku → panel: poziom, efekt, „Ulepsz (koszt, czas)”, „Przyspiesz (N 💎)” gdy w budowie.
  - HUD: Energia `x / cap`, Kropki `x / cap`, Kryształy, budowniczowie `zajęci/2`; przycisk „Bitwa” → `prototype.tscn`.
  - `collect(now)` co 1 s i przy `NOTIFICATION_APPLICATION_RESUMED`; `SaveStore.save` po każdej mutacji i przy `NOTIFICATION_APPLICATION_PAUSED` / `WM_CLOSE_REQUEST`. `now` = `int(Time.get_unix_time_from_system())` tylko w tej warstwie.
  - Po powrocie z offline: toast „Zebrano +E energii, +K kropek” gdy > 0.
- [ ] **Step 1:** Testy: `test_cell_at_center` (`origin` → `(0,0)`), `test_cell_at_neighbor` (piksel środka `(1,0)` → `(1,0)`), `test_cell_at_edge_rounding`, `test_format_secs`.
- [ ] **Step 2:** Run → FAIL. Implementacja. Run → PASS.
- [ ] **Step 3:** Ręczny check: `xvfb-run` ze screenshotem `-- --shot docs/screens/stage2.png` (tryb shot: postaw automatycznie generator na (0,1) i laser na (-1,0), odczekaj 2 s) — obejrzyj obraz.
- [ ] **Step 4:** CI zielone (test + android) po pushu.
- [ ] **Step 5:** Commit `feat(game): colony screen with build menu and HUD`.
