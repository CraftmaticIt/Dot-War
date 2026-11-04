# Etap 6 — PvE: kampania łamigłówek + arena fal

Data: 2026-11-04 · Status: zaakceptowany projekt (właściciel)

## Decyzje właściciela

- Kampania = obrona z limitem: stała mapa, gracz rozstawia ograniczony zestaw budynków na wolnych slotach,
  potem AI-rój atakuje. ★ Rdzeń przetrwał, ★★ stracone ≤ 1 węzeł gracza, ★★★ nic nie stracone.
- Arena tygodnia: mapa i fale z seeda tygodnia, budżet punktów zamiast limitu sztuk, fale bez końca;
  wynik = liczba przetrwanych fal; ranking tygodniowy weryfikowany replayem na serwerze.
- 4 typy wrogich kropek: zwykła, szybka, pancerna, rozpryskowa.
- 15 poziomów w 3 rozdziałach; kryształy za każdą nowo zdobytą gwiazdkę (raz); top 10% tygodnia areny
  dostaje stałą nagrodę.

## 1. Symulacja (GD `sim/` + TS `server/sim/`, ten sam kontrakt)

- Grupa ma pole `kind` (int): 0 zwykła, 1 szybka, 2 pancerna, 3 rozpryskowa. Grupy z `send` mają kind 0.
  - szybka: ruch `GROUP_SPEED * 3 / 2` na tick (kumuluje się z Szałem: `* 3 / 2` dwukrotnie).
  - pancerna: obrażenia od wież `dmg / 2` (po Tarczy, jeśli aktywna).
  - rozpryskowa: gdy zginie od wież, każdy węzeł innego właściciela niż ona (owner > 0) w promieniu
    `SPLASH_RANGE = 2000` traci `SPLASH_DMG = 5` garnizonu (min 0, bez przejęcia). Kolejność: węzły po id.
- Komenda `spawn {tick, type:"spawn", owner, node, to, count, kind}`: tworzy grupę `count` kropek typu `kind`
  na węźle `node` (musi należeć do `owner`), ścieżką do `to`; nie zmienia garnizonu węzła. Odrzucenia jak w
  `send` (bad_owner, bad_node, not_owner, no_path, empty dla count ≤ 0, bad_kind dla kind spoza 0..3).
  Generuje ją wyłącznie skrypt fal (PvE), nigdy wejście gracza; PvP odrzuca komendy innych typów jak dotąd.
- `canonical()`: segment grupy dostaje `,k<kind>` tylko gdy kind ≠ 0 → wektory v001–v007 i b001–b006
  zachowują hashe.

## 2. Definicje (`server/game/pve_levels.json`, czytane przez TS i `pve/pve_defs.gd`)

```json
{
  "star_crystals": 5,
  "weekly": {"epoch": 1793577600, "top_pct": 10, "reward": {"crystals": 30, "boosters": {"split": 1}}},
  "arena": {"budget": 12, "costs": {"laser": 3, "pulse": 3, "wall": 2, "trap": 2}, "wave_gap": 300, "max_waves": 60},
  "levels": [{
    "id": 1, "chapter": 1, "name": "Pierwszy laser",
    "nodes": [{"id": 1, "x": 0, "y": 0, "role": "core"}, {"id": 2, "x": 6000, "y": 0, "role": "slot"},
              {"id": 9, "x": 14000, "y": 0, "role": "spawn"}],
    "links": [[1, 2], [2, 9]],
    "allowed": {"laser": 1},
    "level": 1,
    "waves": [{"tick": 40, "node": 9, "count": 12, "kind": 0}]
  }]
}
```

- Role węzłów: `core` (Rdzeń gracza, garnizon wg `Buildings.garrison("core", level)`), `slot` (wolne pole:
  puste = neutralny węzeł garnizon 0; z budynkiem = węzeł gracza wg tabel budynków), `spawn` (węzeł wroga,
  owner 2, garnizon 0, produkcja 0).
- `allowed`: ile sztuk każdego typu (laser/pulse/wall/trap) można rozstawić. Poziom budynków = `level`.
- Fale: komendy `spawn` w podanym ticku, cel zawsze Rdzeń.
- Arena: generator z seeda tygodnia (SimRng): mapa 1 Rdzeń, 8 slotów, 2–3 węzły spawn; fala i startuje w
  ticku `40 + i*wave_gap`, liczba kropek i typy rosną z i. Budżet punktów `arena.budget`, koszt wg `costs`.

## 3. Reguły meczu PvE (`pve/pve_match.gd` + `server/game/pve.ts`)

- Wejście: definicja poziomu (lub areny tygodnia) + rozstawienie `placement: [{slot, type}]`.
- Walidacja rozstawienia (klient i serwer, ta sama funkcja): slot istnieje i ma rolę `slot`, bez duplikatów,
  typ w `allowed` (kampania) lub w `costs` (arena), liczba sztuk ≤ limit / suma kosztów ≤ budżet.
  Błąd → `bad_placement`, brak meczu.
- Gracz może w trakcie meczu wysyłać kropki ze swoich węzłów (`{tick, from, to, percent}`, jak w ataku),
  ale nigdy do ani przez węzeł spawn (inaczej przejęcie spawnu zatrzymałoby fale). Replay = rozstawienie + komendy
  (max 2000). Decyzja właściciela po teście na telefonie (2026-11-04).
- Koniec kampanii: Rdzeń przejęty (porażka, 0★) albo wszystkie fale wypuszczone i brak wrogich grup.
  Limit bezpieczeństwa 12000 ticków. Gwiazdki: 1 + (stracone ≤ 1) + (stracone == 0), gdy Rdzeń żyje;
  „stracone” = węzły gracza na starcie (Rdzeń + budynki) przejęte przez wroga.
- Koniec areny: Rdzeń przejęty albo `max_waves` fal wypuszczonych i brak wrogich grup.
  Wynik = liczba fal, które wystartowały przed upadkiem Rdzenia, minus 1 (min 0); bez upadku = max_waves.

## 4. Backend

- Migracja: `pve_progress(player, level, stars, primary key(player, level))`,
  `pve_weekly(player, week, score, primary key(player, week))`, `pve_weeks_settled(week primary key)`.
  RLS: select własnych wierszy; zapisy tylko przez RPC (revoke public/anon/authenticated, grant service_role).
- RPC `pve_record(player, level, stars, crystals_per_star)`: atomowo stars = max(stare, nowe), kryształy
  = (nowe − stare)+ × crystals_per_star do `players.crystals` (z mirrorem do kolonii); zwraca zdobyte gwiazdki.
- RPC `pve_week_record(player, week, score)`: score = max.
- RPC `settle_pve_week(week, top_pct, crystals, boosters)`: raz na tydzień (insert do `pve_weeks_settled`
  on conflict do nothing); przyznaje nagrodę graczom z wynikiem ≥ próg top_pct% (co najmniej 1 gracz, wynik > 0).
- Edge Function `finish_pve` `{level}` lub `{week}` + `{placement}`: waliduje, robi replay, zapisuje,
  zwraca `{stars|score, gained, crystals, profile}`. Arena przyjmuje tylko bieżący tydzień.
- Edge Function `pve_ranking`: leniwie rozlicza poprzedni tydzień, zwraca top 20 (`Gracz #xxxx` z id)
  + wynik i pozycję gracza. Profil (`sync`/`finish_pve`) zawiera `pve: {level: stars}`.

## 5. Klient

- Menu: „Kampania” i „Arena tygodnia”.
- Kampania: siatka 15 poziomów z gwiazdkami; poziom n odblokowany przy ≥ 1★ na n−1 (1 zawsze).
- Scena `game/pve_view`: mapa (te same widoki węzłów co bitwa), paleta dozwolonych budynków z licznikami
  (arena: z kosztem i budżetem), tap slot → postaw / zdejmij, „Start”, potem symulacja na żywo, ekran końca
  z gwiazdkami/wynikiem i nagrodą. Offline: gra działa, nagroda „wymaga połączenia”.
- Opisy w „Jak grać” rozszerzone o PvE i typy kropek.

## 6. Testy

- Wektory determinizmu: nowe v008 (kind: szybka/pancerna/rozpryskowa) i v009 (spawn + odrzucenia) — GD = TS.
- Wektory PvE `tests/pve_vectors/`: poziom + rozstawienie → gwiazdki, hash (GD = TS), arena tygodnia → wynik.
- Każdy z 15 poziomów ma rozwiązanie referencyjne (`tests/pve_solutions.json`) dające 3★, a brak rozstawienia
  daje < 3★ (poziom jest łamigłówką).
- Serwer: kryształy tylko za nowe gwiazdki, równoległe zgłoszenia przyznają raz, `bad_placement`, arena tylko
  bieżący tydzień, rozliczenie tygodnia raz.
- Smoke: przejście poziomu 1 rozwiązaniem referencyjnym na żywym backendzie.
