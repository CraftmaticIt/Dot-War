# Stage 1: Swarm Simulation + Render — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deterministyczna symulacja roju kropek na grafie węzłów (przepływ, przejmowanie, wieże) + render neon 2000 kropek w 60 FPS + CI z testami.

**Architecture:** `sim/` to czysty GDScript bez scen i bez floatów (stały przecinek, skala 1000), krok 20 Hz, wejście = komendy z tickiem, wyjście = stan + zdarzenia + hash. Rój w symulacji to *grupy* (owner, count, pozycja na ścieżce) — pojedyncze kropki istnieją tylko w renderze (`game/`). Wektory testowe JSON (seed + komendy → hash) są kontraktem dla przyszłego portu TS (etap 4).

**Tech Stack:** Godot 4 (najnowszy stable 4.x, przypięty w Task 1), GDScript, GUT 9.x, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-03-dot-war-design.md` (sekcje 6, 7, 9, 10.1)

## Global Constraints

- Tick symulacji: 20 Hz (`SimWorld.TICK_HZ = 20`).
- W `sim/` zakaz `float`, `randf`, `randi`, `Time`, iteracji po `Dictionary` bez sortowania kluczy — wszystko int, losowość tylko `SimRng`.
- Stały przecinek: `Fx.ONE = 1000`.
- Wydajność: 2000 kropek, 60 FPS (benchmark, Task 7).
- Grafika: neon/minimal — kropki z glow, kolor = owner.
- Owner: `0` = neutralny, `1..4` = gracze/AI.
- Ręczna konfiguracja właściciela: zero w tym etapie (Godot i GUT instalowane skryptem).

## Review Focus

1. Komenda `send` z węzła nie należącego do gracza / `percent` 0 lub >100 / brak ścieżki → komenda ignorowana, zdarzenie `cmd_rejected`, brak crasha (test w Task 4).
2. Węzeł zmienia właściciela, gdy grupa gracza jest w drodze do niego → grupa po dotarciu walczy z nowym garnizonem (test w Task 5).
3. Remis w wyborze celu przez wieżę (dwie grupy w tej samej odległości) → wybór deterministyczny: niższe `group.id` (test w Task 6).
4. Dwie grupy różnych właścicieli docierają do neutralnego węzła w tym samym ticku → rozstrzygane w kolejności `group.id`, wynik stały (test w Task 5).
5. Grupa zredukowana do 0 kropek przez wieżę w trakcie lotu → usunięta w tym samym ticku, bez artefaktów w renderze (test w Task 6).

---

### Task 1: Projekt Godot + GUT + skrypt instalacji + CI

**Files:**
- Create: `project.godot`, `.gitignore`, `scripts/install_godot.sh`, `scripts/test.sh`, `.github/workflows/test.yml`, `.gutconfig.json`, `tests/unit/test_smoke.gd`, `addons/gut/` (vendored)

**Interfaces:**
- Produces: `scripts/test.sh` — uruchamia wszystkie testy headless, kod wyjścia ≠0 przy porażce. Używany przez każdy kolejny task.

- [ ] **Step 1:** `scripts/install_godot.sh` — pobiera Godot 4.x stable linux headless (wersja w zmiennej `GODOT_VERSION`, ustaw na najnowszy stable z github.com/godotengine/godot/releases) do `.tools/godot`, oraz GUT 9.x do `addons/gut`. Idempotentny.
- [ ] **Step 2:** `project.godot` z nazwą „Dot War”, renderer `mobile`, orientacja landscape, `.gitignore` z `.godot/`, `.tools/`.
- [ ] **Step 3:** Test `test_smoke.gd`: `assert_eq(1 + 1, 2)`.
- [ ] **Step 4:** `scripts/test.sh` = `.tools/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`. Run → Expected: `1 passed`.
- [ ] **Step 5:** Workflow `test.yml`: on push/PR, ubuntu, `install_godot.sh` + `test.sh`.
- [ ] **Step 6:** Commit `chore: godot project, GUT, CI`.

### Task 2: Fx (stały przecinek) + SimRng

**Files:**
- Create: `sim/fx.gd`, `sim/rng.gd`
- Test: `tests/unit/test_fx.gd`, `tests/unit/test_rng.gd`

**Interfaces:**
- Produces: `class_name Fx` — `const ONE := 1000`; `static func from_int(i:int)->int`; `static func mul(a:int,b:int)->int` (obcięcie do zera); `static func div(a:int,b:int)->int`; `static func dist(ax:int,ay:int,bx:int,by:int)->int` (całkowity sqrt, metoda Newtona na int).
- Produces: `class_name SimRng` — `func _init(seed:int)`; `func next_u32()->int` (xorshift32, seed 0 → 2463534242); `func range_i(n:int)->int` (0..n-1).

- [ ] **Step 1: Testy**
```gdscript
func test_mul(): assert_eq(Fx.mul(1500, 2000), 3000)
func test_mul_neg(): assert_eq(Fx.mul(-1500, 1000), -1500)
func test_div(): assert_eq(Fx.div(3000, 2000), 1500)
func test_dist_345(): assert_eq(Fx.dist(0, 0, 3000, 4000), 5000)
func test_rng_repeatable():
    var a := SimRng.new(42); var b := SimRng.new(42)
    for i in 100: assert_eq(a.next_u32(), b.next_u32())
func test_rng_range_bounds():
    var r := SimRng.new(7)
    for i in 1000: var v := r.range_i(5); assert_true(v >= 0 and v < 5)
```
- [ ] **Step 2:** `scripts/test.sh` → FAIL (brak klas).
- [ ] **Step 3:** Implementacja. `next_u32` maskuje `& 0xFFFFFFFF` po każdym przesunięciu.
- [ ] **Step 4:** `scripts/test.sh` → PASS.
- [ ] **Step 5:** Commit `feat(sim): fixed-point math and deterministic rng`.

### Task 3: SimGraph — węzły, krawędzie, ścieżki

**Files:**
- Create: `sim/graph.gd`
- Test: `tests/unit/test_graph.gd`

**Interfaces:**
- Consumes: `Fx.dist`.
- Produces: `class_name SimGraph`
  - `func add_node(id:int, x:int, y:int, owner:int, garrison:int, prod_per_sec:int, tower:String = "") -> void` (x,y w Fx; `tower` ∈ `""`, `"laser"`, `"pulse"`)
  - `func link(a:int, b:int) -> void` (nieskierowana)
  - `func node(id:int) -> Dictionary` — klucze `id,x,y,owner,garrison,prod_per_sec,tower,prod_acc`
  - `func node_ids() -> PackedInt32Array` (posortowane rosnąco)
  - `func neighbors(id:int) -> PackedInt32Array` (posortowane)
  - `func path(from:int, to:int) -> PackedInt32Array` — Dijkstra po `Fx.dist`, remis → niższe id poprzednika; brak ścieżki → pusta tablica; zawiera `from` i `to`.
  - `static func from_dict(d:Dictionary) -> SimGraph` / `func to_dict() -> Dictionary` (format: `{"nodes":[...], "links":[[a,b],...]}`)

- [ ] **Step 1: Testy:** `test_path_prefers_shorter` (romb 1-2-4 krótszy niż 1-3-4 → `[1,2,4]`), `test_path_none_when_disconnected` (→ `[]`), `test_path_tie_lower_id` (dwie równe ścieżki → przez niższe id), `test_roundtrip_dict` (`from_dict(g.to_dict()).to_dict() == g.to_dict()`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implementacja.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(sim): node graph with deterministic pathfinding`.

### Task 4: SimWorld — tick, produkcja, komenda `send`, hash

**Files:**
- Create: `sim/world.gd`
- Test: `tests/unit/test_world_send.gd`

**Interfaces:**
- Consumes: `SimGraph`, `SimRng`, `Fx`.
- Produces: `class_name SimWorld`
  - `const TICK_HZ := 20`, `const GROUP_SPEED := 150` (Fx/tick, czyli 3 jednostki/s)
  - `func _init(graph:SimGraph, seed:int)`
  - `var tick:int`, `var groups:Array[Dictionary]` — grupa: `{id, owner, count, path:PackedInt32Array, seg:int, progress:int}` (progress w Fx wzdłuż odcinka `path[seg]→path[seg+1]`)
  - `var events:Array[Dictionary]` — czyszczone na początku każdego `step()`
  - `func queue(cmd:Dictionary) -> void` — `{"tick":int,"type":"send","owner":int,"from":int,"to":int,"percent":int}`
  - `func step() -> void` — kolejność: (1) komendy z `tick == self.tick` w kolejności dodania, (2) produkcja, (3) ruch, (4) przyloty, (5) wieże [Task 6], (6) `tick += 1`
  - `func state_hash() -> int` — FNV-1a 32-bit po `var_to_str` kanonicznego stanu (węzły po id, grupy po id)
- Reguły:
  - Produkcja: `prod_acc += prod_per_sec`; gdy `prod_acc >= TICK_HZ` → `garrison += 1`, `prod_acc -= TICK_HZ`. Węzły neutralne nie produkują.
  - `send`: odrzuć (zdarzenie `{"type":"cmd_rejected","reason":...}`) gdy owner węzła ≠ `cmd.owner`, `percent` ∉ 1..100, brak ścieżki, lub wynikowe `count = garrison*percent/100 == 0`. Inaczej odejmij z garnizonu, utwórz grupę (`id` = rosnący licznik), zdarzenie `group_spawned`.

- [ ] **Step 1: Testy:** `test_production_one_per_sec` (prod 1, 20 ticków → garrison +1), `test_neutral_no_production`, `test_send_half` (garrison 10, 50% → grupa 5, węzeł 5), `test_send_rejected_not_owner`, `test_send_rejected_percent_0_and_101`, `test_send_rejected_no_path`, `test_hash_same_for_same_input` (dwa światy, te same komendy, 200 ticków → równe hashe), `test_hash_differs_on_different_cmd`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implementacja (bez kroków 4–5 z `step()` poza ruchem — przyloty w Task 5).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(sim): world tick, production, send command, state hash`.

### Task 5: Ruch, przyloty, walka i przejęcie węzła

**Files:**
- Modify: `sim/world.gd`
- Test: `tests/unit/test_world_arrival.gd`

**Interfaces:**
- Produces: zdarzenia `{"type":"node_captured","node":int,"owner":int}`, `{"type":"group_arrived","group":int,"node":int}`.
- Reguły:
  - Ruch: `progress += GROUP_SPEED`; po przekroczeniu długości odcinka → `seg += 1`, nadmiar przechodzi dalej. Węzeł pośredni wrogi → grupa zatrzymuje się i walczy jak przy przylocie (nie przelatuje przez wroga).
  - Przylot (grupy w kolejności `id`): ten sam owner → `garrison += count`. Inny → `garrison -= count`; gdy `< 0` → `owner = group.owner`, `garrison = -garrison`, `prod_acc = 0`, zdarzenie `node_captured`. Równo 0 → węzeł zostaje u obrońcy z 0.

- [ ] **Step 1: Testy:** `test_group_reaches_target_after_expected_ticks` (odległość 3000 → przylot w ticku 20), `test_reinforce_own_node`, `test_capture_enemy_node` (10 vs garrison 4 → owner zmieniony, garrison 6), `test_tie_defender_keeps`, `test_owner_changed_midflight` (Review Focus 2), `test_same_tick_two_attackers_order_by_id` (Review Focus 4: neutralny garrison 5, grupa id0 owner1 count 7, grupa id1 owner2 count 4 → owner1 przejmuje z 2, potem owner2 atakuje: 2-4<0 → owner2, garrison 2), `test_stops_at_enemy_intermediate_node`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implementacja.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(sim): group movement, arrival combat, node capture`.

### Task 6: Wieże laser i puls

**Files:**
- Create: `sim/towers.gd`
- Modify: `sim/world.gd` (krok 5 w `step()`)
- Test: `tests/unit/test_towers.gd`

**Interfaces:**
- Produces: `class_name SimTowers` — `const SPECS := {"laser":{"range":4000,"dmg":200}, "pulse":{"range":2000,"dmg":60}}` (dmg w Fx kropek/tick: 200 = 4 kropki/s, 60 = 1.2 kropki/s na każdą grupę). `static func apply(world:SimWorld) -> void`.
- Pozycja grupy: interpolacja int między węzłami odcinka. Laser: jedna najbliższa wroga grupa w zasięgu (remis → niższe `id`). Puls: każda wroga grupa w zasięgu. Grupa trzyma `dmg_acc`; gdy `>= Fx.ONE` → `count -= dmg_acc / Fx.ONE`, reszta zostaje. `count <= 0` → grupa usunięta, zdarzenie `group_destroyed`. Wieża strzela tylko gdy węzeł ma ownera ≠ 0.

- [ ] **Step 1: Testy:** `test_laser_kills_4_per_sec`, `test_laser_out_of_range_no_dmg`, `test_laser_tie_lower_id` (RF 3), `test_pulse_hits_all_in_range`, `test_tower_ignores_own_groups`, `test_group_destroyed_removed_same_tick` (RF 5).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implementacja.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(sim): laser and pulse towers`.

### Task 7: Wektory determinizmu (kontrakt dla portu TS)

**Files:**
- Create: `tests/vectors/v001_basic.json`, `v002_capture.json`, `v003_towers.json`, `tools/gen_vectors.gd`
- Test: `tests/unit/test_vectors.gd`

**Interfaces:**
- Produces: format wektora `{"graph": <SimGraph.to_dict>, "seed":int, "commands":[cmd...], "ticks":int, "expected_hash":int}`. Etap 4 (TS) czyta te same pliki.

- [ ] **Step 1:** `tools/gen_vectors.gd` (uruchamiany `godot --headless -s`) tworzy 3 scenariusze i zapisuje `expected_hash`.
- [ ] **Step 2:** Test: dla każdego pliku w `tests/vectors/` odtwórz i `assert_eq(world.state_hash(), expected_hash)`.
- [ ] **Step 3:** Wygeneruj, run → PASS. Uruchom drugi raz → hashe bez zmian (`git diff --exit-code tests/vectors`).
- [ ] **Step 4:** Commit `test(sim): determinism vectors`.

### Task 8: Render neon + input + scena prototypu

**Files:**
- Create: `game/swarm_renderer.gd`, `game/node_view.gd`, `game/glow.gdshader`, `game/prototype.tscn`, `game/prototype.gd`, `game/input_send.gd`
- Test: `tests/unit/test_swarm_layout.gd`

**Interfaces:**
- Consumes: `SimWorld`, `SimGraph`.
- Produces: `class_name SwarmRenderer extends MultiMeshInstance2D` — `func sync(world:SimWorld, alpha:float) -> void` (alpha = interpolacja między tickami); `static func dot_offset(group_id:int, i:int) -> Vector2` (deterministyczny rozrzut kropki w grupie, promień ≤ 12 px, z hasha `group_id*7919+i`).
- Kolory ownerów: 0 `#808080`, 1 `#00E5FF`, 2 `#FF2E88`, 3 `#B6FF00`, 4 `#FFB300`. Tło `#0B0E14`.
- Input: przeciągnięcie z własnego węzła na inny → `send` 50%; suwak % w rogu (25/50/75/100).
- `prototype.gd`: mapa 12 węzłów, gracz vs prosty bot (co 3 s wysyła 50% z najsilniejszego węzła na najsłabszy sąsiedni wrogi/neutralny).

- [ ] **Step 1:** Test `test_dot_offset_deterministic_and_bounded` (te same argumenty → ten sam wektor; `length() <= 12` dla 1000 próbek).
- [ ] **Step 2:** Run → FAIL. Implementacja. Run → PASS.
- [ ] **Step 3:** Ręczny check: uruchom scenę (`.tools/godot game/prototype.tscn`), screenshot do `docs/screens/stage1.png`.
- [ ] **Step 4:** Commit `feat(game): neon swarm renderer and playable prototype`.

### Task 9: Benchmark 2000 kropek + eksport Android w CI

**Files:**
- Create: `game/benchmark.tscn`, `game/benchmark.gd`, `export_presets.cfg`, `.github/workflows/android.yml`

**Interfaces:**
- Consumes: `SwarmRenderer`, `SimWorld`.

- [ ] **Step 1:** `benchmark.gd`: 40 grup × 50 kropek w ruchu, 10 s, wypisuje `avg_fps` i `p95_frame_ms`, kończy z kodem 1 gdy `avg_fps < 60` (tylko w trybie `--benchmark`; w CI headless sprawdza tylko czas `step()` < 2 ms/tick dla 40 grup).
- [ ] **Step 2:** Run headless → Expected: `sim_step_ms < 2`.
- [ ] **Step 3:** `export_presets.cfg` (Android, debug keystore generowany w CI), `android.yml` buduje APK i publikuje jako artifact. Zero sekretów w tym etapie.
- [ ] **Step 4:** Ręczny check właściciela (jedyny w etapie): pobierz APK z Actions, zainstaluj na telefonie, uruchom benchmark → odczyt FPS.
- [ ] **Step 5:** Commit `ci: android debug apk and benchmark`.
