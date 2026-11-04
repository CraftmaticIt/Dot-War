# Dot War — design spec

Data: 2026-11-03 · Status: do przeglądu

## 1. Cel i kryteria sukcesu

Komercyjna gra mobilna (Android + iOS), free-to-play. Łączy rój kropek (State.io/Galcon) z budową kolonii, ekonomią i obroną-łamigłówką (tower defense), z asynchroniczną rywalizacją PvP.

Sukces MVP:
- Soft launch Android: działa na telefonie klasy średniej (np. 4 GB RAM) w 60 FPS przy 2000 kropek.
- Pełna pętla: buduj → atakuj cudzą bazę → łup → liga, plus PvE.
- Zero pay-to-win w rankingu.
- Minimum ręcznej konfiguracji po stronie właściciela (decyzja nadrzędna przy wyborze narzędzi).

Decyzje właściciela: hybryda „rój węzłów + obrona-labirynt”, multiplayer asynchroniczny, grafika neon/minimal (kropki), Godot 4, komercja.

## 2. Pętla gry

1. **Kolonia** — graf węzłów (max 20 na start, rośnie z poziomem ratusza „Rdzeń”). Na węźle stawiasz jeden budynek. Krawędzie = ścieżki roju.
2. **Atak (async)** — matchmaking po trofeach daje snapshot cudzej kolonii. Atakujący ma 3 węzły startowe na krawędzi mapy, wysyła rój (tap węzeł → przeciągnij na cel, % strumienia suwakiem), używa do 3 boosterów. Czas 3 min. Wynik: 0–3 gwiazdki (50% węzłów, Rdzeń, 100%).
3. **Obrona** — gdy jesteś offline, inni atakują twój snapshot; obroną steruje deterministyczna AI wież. Dostajesz replay.
4. **PvE** — kampania łamigłówek (ręcznie zaprojektowane plansze z ograniczeniem budynków, 1–3 gwiazdki) + nieskończone fale AI-roju (rekord tygodniowy w rankingu).

## 3. Budynki (MVP)

| Budynek | Rola |
|---|---|
| Rdzeń | ratusz, cel główny, limit węzłów i poziomów |
| Kopalnia | produkuje Energię/h |
| Magazyn | limit Energii, % chroniony przed łupem |
| Generator roju | produkuje Kropki (armia ataku), limit pojemności |
| Wieża-laser | pojedynczy cel, duży zasięg |
| Wieża-puls | obszarowa, krótki zasięg |
| Ściana/węzeł-blokada | spowalnia/kieruje rój — element łamigłówki |
| Pułapka-mina | jednorazowa, ukryta przed atakującym |

Każdy budynek: 5 poziomów w MVP, koszt Energii + czas budowy.

### Decyzje etapu 2 (właściciel, 2026-11-03)

- Układ: heksagonalna siatka; węzeł na dowolnym wolnym polu przyległym do kolonii, krawędzie automatycznie między sąsiadami.
- Czas budowy: realny czas + przyspieszanie Kryształami.
- Offline: zasoby rosną po zamknięciu gry, max 8 h, do limitu magazynu.

### Decyzje etapu 3 (właściciel, 2026-11-04)

- Garnizon obrony stały wg typu i poziomu (nie zużywa zasobów obrońcy).
- Mur = twardy węzeł (duży garnizon). Pułapka = ukryta; pierwsza wroga grupa traci 10×poziom kropek, potem pusty węzeł.
- Przeciwnicy do czasu backendu: boty-kolonie generowane wg trofeów (seed → układ).

### Decyzje etapu 4 (właściciel, 2026-11-04)

- Ekonomia: klient wysyła zapis kolonii, serwer odrzuca niemożliwe skoki (limity produkcji od ostatniego zapisu); trofea, ataki i kryształy należą do serwera.
- Logowanie: anonimowe konto urządzenia; Google/Apple w etapie 7.
- Przeciwnicy: gracze ±200 trofeów bez tarczy; brak → bot. Tarcza 8 h po porażce obrońcy.
- Konfiguracja Supabase wyłącznie przez CI (sekrety GitHub); klucze klienta wstrzykiwane przy eksporcie APK.

### Decyzje etapu 5 (właściciel, 2026-11-04)

- Boostery celowane w węzeł: Szał/Tarcza/Rozszczepienie działają na grupy gracza lecące do wskazanego węzła, EMP wyłącza wrogie wieże w promieniu węzła. Max 3 na atak (z wybranego przed atakiem zestawu).
- Źródła boosterów: zadania dzienne, skrzynki, sklep za Kryształy.
- Liga: progi trofeów (Brąz/Srebro/Złoto/Platyna/Diament), sezon 14 dni, nagroda w Kryształach za ligę, miękki reset (nadwyżka ponad 1000 trofeów o połowę); rozliczenie leniwe przy pierwszym żądaniu po końcu sezonu.

## 4. Ekonomia

- **Energia** — z kopalń; budowa/ulepszenia. Łupiona w ataku (max 20% niechronionej).
- **Kropki** — z generatorów; zużywane w ataku.
- **Kryształy** — premium; przyspieszanie, kosmetyki, battle pass. Do zdobycia też grą (zadania, liga).
- Ochrona przed farmieniem: tarcza 8 h po porażce w obronie, limit łupu, matchmaking ±200 trofeów.

## 5. Bonusy, nagrody, boostery

- **Boostery ataku**: Szał (prędkość +50%, 8 s), Tarcza roju (−60% obrażeń, 6 s), EMP (wyłącza wieże w promieniu, 4 s), Rozszczepienie (każda kropka ×2 przy następnym celu). Max 3 na atak; w lidze limit poziomu boostera = brak pay-to-win.
- **Nagrody**: dzienne zadania, skrzynka za 3 gwiazdki, nagrody ligowe na koniec sezonu (2 tyg.), battle pass (darmowa + płatna ścieżka).
- **Bonusy w meczu**: losowe „rdzenie energii” na mapie ataku — przejęcie daje +Kropki.

## 6. AI

- **Obrona wież**: deterministyczne reguły (priorytet: najbliższa / najsłabsza / najgęstsza grupa — ustawiane przez gracza per wieża = element łamigłówki).
- **Boty**: generowane kolonie wg poziomu trofeów (seed → układ), wypełniają matchmaking przed bazą graczy i przy pustej kolejce.
- **Fale PvE**: generator proceduralny (seed tygodnia), rosnąca trudność, typy kropek: zwykła, szybka, pancerna, rozpryskowa.
- **Rój**: boidy uproszczone + przepływ po krawędziach grafu (bez pełnej fizyki), stały tick 20 Hz, matematyka stałoprzecinkowa → determinizm.

## 7. Architektura techniczna

Wybrane pod kątem minimum ręcznej konfiguracji:

- **Klient**: Godot 4.x (stabilny), GDScript. Render roju: `MultiMeshInstance2D` + shader glow.
- **Moduły klienta** (każdy testowalny osobno):
  - `sim/` — czysta symulacja (graf, rój, wieże, boostery, ekonomia tick). Bez zależności od scen. Wejście: stan + lista komend z tickiem; wyjście: stan + zdarzenia.
  - `ai/` — boty, generator fal, generator kolonii.
  - `game/` — sceny, input, kamera, render.
  - `meta/` — ekonomia, budowa, zadania, liga, sklep.
  - `net/` — klient backendu.
- **Backend**: **Supabase** (hostowane: Postgres + Auth + Edge Functions + Storage). Uzasadnienie: zero własnego serwera; właściciel zakłada tylko konto i przekazuje token, resztę (migracje, funkcje) wdraża Claude przez Supabase CLI.
  - Tabele: `players`, `colonies` (snapshot JSON + wersja), `attacks` (replay: seed + komendy), `leagues`, `inventory`.
  - Edge Function `verify_attack`: odtwarza replay portem `sim/` do TypeScript (decyzja właściciela; rozjazd pilnowany wspólnymi wektorami testowymi: te same pliki JSON seed+komendy → ten sam hash w GDScript i TS) i dopiero wtedy przyznaje łup/trofea. Anti-cheat.
  - Logowanie: anonimowe konto urządzenia → opcjonalnie Google/Apple.
- **Build/CI**: GitHub Actions — testy (GUT), eksport Android APK/AAB; iOS przez Codemagic lub GitHub macOS runner (później).
- **Monetyzacja/analityka** (etap 7): rewarded ads (AdMob przez plugin Godot), IAP (Google Play Billing / StoreKit plugin), analityka w Supabase (tabela zdarzeń) — bez dodatkowych usług.

## 8. Obsługa błędów

- Offline: kolonia i PvE działają lokalnie; ataki PvP wymagają sieci. Kolejka zapisu z ponawianiem.
- Konflikt snapshotu (gracz zmienia bazę podczas ataku na nią): atak zawsze na wersji pobranej na starcie.
- Odrzucony replay (niezgodność): atak nieważny, brak nagród, log do analizy.

## 9. Testy

- Jednostkowe `sim/` (GUT): przepływ kropek, obrażenia wież, boostery, ekonomia.
- Test determinizmu: ten sam seed + komendy → identyczny hash stanu (klient vs weryfikator).
- Testy balansu: boty atakują boty 1000× headless, raport win-rate per budynek/booster.
- Wydajność: scena benchmark 2000 kropek, próg 60 FPS.

## 10. Etapy MVP

1. Prototyp symulacji roju + render (2 tyg.)
2. Budowa kolonii i ekonomia (2 tyg.)
3. Atak na snapshot + boty AI (2 tyg.)
4. Backend Supabase: konta, snapshoty, matchmaking, weryfikacja replayu (3 tyg.)
5. Meta: boostery, nagrody, zadania, liga (2 tyg.)
6. PvE: kampania łamigłówek + fale (2 tyg.)
7. Monetyzacja, analityka, soft launch Android (2 tyg.), potem iOS.

## 11. Poza zakresem MVP

Klany, wojna terytoriów (podejście 3), czat, real-time PvP, pixel-art/stickman skiny (później jako kosmetyki).

## 12. Ręczne kroki właściciela (minimum)

1. Konto Supabase + token dostępu (etap 4).
2. Konto Google Play Console (etap 7), Apple Developer (iOS).
3. Konto AdMob (etap 7).
Wszystko inne (instalacja Godot, CI, migracje, eksport) — automatycznie.
