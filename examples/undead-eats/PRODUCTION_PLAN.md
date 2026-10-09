# Undead Eats (tytuł roboczy): plan produkcji

## Założenia (nie pytałem, przyjąłem)
- **Zespół:** 3 osoby po ~15 h/tyg: **Skrypter (Sk)**, **Builder (Bd)** – mapa + modele w Blenderze + animacje zombie, **UI (Ui)** – UI + dźwięk + VFX + animacje graczy + publikacja.
- **Termin:** 8 tygodni. Prototyp w tyg. 2, vertical slice w tyg. 5, soft launch w tyg. 7, launch w tyg. 8.
- **Jednostka „dzień”** = 5 h pracy (15 h/tyg = 3 sesje). Na osobę: 8 tyg × 3 = **24 dni** brutto.
- **Styl:** low-poly cartoon, jedna paleta kolorów (tekstura 256×256 na wszystkie meshe), bez realistycznych tekstur.
- **Avatary:** własne avatary graczy **R15**. Animacje gracza muszą działać na każdym ciele (testy na blocky, slender, Rthro).
- **Platforma:** telefon najpierw, potem PC. Konsola/VR pominięte.
- **Konto właściciela:** **grupa**. Gra, animacje, audio i meshe wgrywane na grupę od pierwszego dnia (uprawnienia do assetów są wtedy automatyczne).
- **Skala:** 1–4 graczy na serwer, 1 mapa, 1 ciężarówka, run = 5 dni + 5 nocy.

## Pętla gry i systemy
**Pętla (czasowniki):** weź składnik → ugotuj → wydaj klientowi → zarób → kup/ustaw wieżyczki i pułapki z jedzenia → przetrwaj noc (załaduj wieżyczki, naprawiaj ciężarówkę) → ulepsz → następny dzień.

- **Dzień (~150 s):** klienci ustawiają się w kolejce przy okienku, każdy zamawia 1–3 dania z cierpliwością. Gracze dzielą się rolami: zaopatrzenie, grill, wydawanie. Zarobek = gotówka na noc.
- **Noc (~90–120 s):** zombie idą z 3 bram do ciężarówki. Gracze **nie strzelają**: stawiają wieżyczki i pułapki na slotach, noszą składniki jako amunicję do wież, naprawiają ciężarówkę. Porażka = HP ciężarówki 0.
- **Wieżyczki (3):** *Ketchup Gatling* (szybka, 1 cel), *Pie Cannon* (obszarowa), *Hot Sauce Sprayer* (krótki zasięg, DoT). **Pułapki (2):** *Grease Slick* (spowolnienie), *Chili Mine* (wybuch jednorazowy).
- **Zombie (3 typy):** Walker, Runner, Tank. Modele = rigi R15 z kolorami i podartymi ubraniami (bez własnego rigowania).
- **Systemy niewidoczne:** zapis danych, zakupy Robux, ustawienia, onboarding, anty-exploit na remote’ach, analityka.

## Macierz mechanika → assety
| Mechanika | Serwer | Feedback klienta | Animacja | Model | VFX | SFX | UI |
|---|---|---|---|---|---|---|---|
| Podniesienie składnika | walidacja dystansu i slotu, weld | podświetlenie skrzyni | hold-tray (idle/walk) | 6 składników | iskra pickup | „pop” | prompt, ikona noszonego |
| Gotowanie | postęp stacji, przepalenie | pasek postępu, dym | cook loop (wspólna) | 3 stacje | para/dym | sizzle, ding | pasek nad stacją |
| Wydanie dania | dopasowanie do zamówienia | danie leci do okienka | hand-over (cook loop) | 4 dania, tacka | monety | kasa | bilet znika, +$ |
| Klient (zamówienie) | spawn, kolejka, cierpliwość | dymek zamówienia | idle/walk NPC (domyślne R15) | 4 warianty NPC | emotka zadowolenia | dzwonek | bilety, pasek cierpliwości |
| Postawienie wieżyczki | koszt, slot, dystans | podgląd ghost | hammer | 3 wieże | kurz budowy | młotek | menu budowy |
| Postawienie pułapki | koszt, slot | podgląd ghost | hammer | 2 pułapki | kurz | plum | menu budowy |
| Ładowanie wieżyczki | amunicja += składnik | pasek amunicji | hold-tray | – | błysk | reload | ammo bar |
| Wieżyczka strzela | celowanie, obrażenia | pocisk, trafienie | – | pociski | splat, ogień | strzał, trafienie | – |
| Pułapka działa | trigger, efekt | slow/wybuch | – | – | plama, wybuch | slip, boom | – |
| Zombie atakuje | pathfinding, obrażenia ciężarówki | pasek HP, drżenie | walk, attack | 3 warianty zombie | pyłek trafienia | warczenie | HP ciężarówki |
| Zombie ginie | nagroda | znika w „poof” | (fade/ragdoll) | – | poof, monety | pop | – |
| Naprawa ciężarówki | HP += (hold interakcji) | iskry | hammer | – | iskry | młotek | pasek naprawy |
| Dzień ↔ noc | maszyna stanów | zmiana oświetlenia | cheer na świt | – | – | muzyka dzień/noc, róg | timer, baner |
| Ulepszenie | koszt, zapis | animacja zakupu | – | – | konfetti | kupno | sklep |
| Zakup za Robux | ProcessReceipt | prompt Roblox | – | skin ciężarówki | błysk | kupno | sklep Robux |

## Zadania wg dyscypliny
Rozmiar: S ≤ 1 dzień, M 1,5–3, L 3,5–7. Priorytet: **MVP** = potrzebne do testu pętli (M1–M2), **Launch** = publiczne wydanie (M3–M4), **Post** = pierwsze aktualizacje. ★ = lista „tnij najpierw”.

### Systemy i skryptowanie (Sk)
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| SYS-01 | Struktura projektu, moduł Remotes, tabele danych (Recipes, Turrets, Zombies, Nights) w ModuleScript | 0,5 | S | MVP | – |
| SYS-02 | Pętla gry: Ready → Dzień → Noc → Wyniki, run 5 dni, wygrana/porażka | 1,5 | M | MVP | SYS-01 |
| SYS-03 | Noszenie przedmiotu (1 slot, weld do RightHand R15, walidacja serwera) | 1 | S | MVP | SYS-01 |
| SYS-04 | 3 stacje gotowania + moduł przepisów (4 dania), postęp, przypalenie | 2 | M | MVP | SYS-03 |
| SYS-05 | Klienci: spawn, kolejka, zamówienia, cierpliwość, wydawanie, płatność i napiwek | 2,5 | M | MVP | SYS-04 |
| SYS-06 | Zombie: spawner z tabeli fal, PathfindingService do ciężarówki/wież, atak; Walker, Runner, Tank★ | 3 | L | MVP | SYS-02 |
| SYS-07 | Ciężarówka: HP, obrażenia, naprawa | 0,5 | S | MVP | SYS-06 |
| SYS-08 | Tryb budowy: sloty, postaw/sprzedaj, walidacja kosztu i dystansu | 1,5 | M | MVP | SYS-02 |
| SYS-09 | 3 wieżyczki (wspólna klasa: celowanie, pocisk, amunicja ze składników) | 2,5 | M | MVP | SYS-08, SYS-03 |
| SYS-10 | 2 pułapki (Grease Slick, Chili Mine★) | 1 | S | MVP | SYS-08 |
| SYS-11 | Ekonomia: gotówka, nagrody dnia/nocy, sklep ulepszeń (HP ciężarówki, tempo gotowania, +1 slot) | 1,5 | M | MVP | SYS-05, SYS-06 |
| DATA-01 | ProfileStore: schema v1 z wersją, session lock, zapis przy wyjściu/BindToClose/autosave | 1,5 | M | Launch | SYS-11 |
| SEC-01 | Przegląd każdego RemoteEvent: typy, zasięg, cooldown, rate limit | 1 | S | Launch | wszystkie SYS |
| SYS-12 | Skalowanie trudności 1–4 graczy★ | 0,5 | S | Launch | SYS-06 |
| **Razem Sk** | | **20** | | | |

### Modele 3D (Bd)
Zasady: ≤ 20 000 tri/mesh (celujemy w < 3 000), jedna paleta 256×256 jako SurfaceAppearance, jeden materiał na mesh, powtarzane meshe i te same ID, CollisionFidelity Box/Hull. Wszystko wgrywane na grupę.
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| MOD-01 | Ciężarówka (okienko, markiza, 6 widocznych slotów wokół) | 2,5 | M | MVP | – |
| MOD-02 | 3 stacje gotowania | 1,5 | M | MVP | – |
| MOD-03 | 6 składników, 4 dania, tacka | 1,5 | M | MVP | – |
| MOD-04 | 3 wieżyczki + pociski | 2 | M | MVP | – |
| MOD-05 | 2 pułapki | 1 | S | MVP | – |
| MOD-06 | Zestaw zombie ×3 (kolory, podarte ubrania z Parts/akcesoria) + 4 warianty klientów (HumanoidDescription) | 1,5 | M | MVP | – |
| ANI-01 | Animacje zombie: walk/run, attack, idle (Blender lub Animation Editor) | 1 | S | MVP | MOD-06 |

### Świat i mapa (Bd)
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| MAP-01 | Greybox: parking/stacja, strefa ciężarówki, 3 bramy zombie, sloty | 1 | S | MVP | – |
| MAP-02 | Dressing low-poly: wraki aut, barykady, drzewa, latarnie, budynki tła★ (można ściąć o 2) | 4 | L | MVP/Launch | MAP-01 |
| MAP-03 | Oświetlenie dzień/noc (Lighting, Atmosphere, tween), światła nocne | 1 | S | MVP | MAP-01 |
| MAP-04 | Optymalizacja: StreamingEnabled test, collision, instancing | 0,5 | S | Launch | MAP-02 |
| PUB-01 | Screenshoty i ujęcia pod miniatury | 0,5 | S | Launch | MAP-02 |
| **Razem Bd** | | **18** | | | |

### Postacie i animacje (Ui, ANI-01 u Bd)
Animacje R15 gracza: **Action** priority, działają na dowolnym ciele; nadpisanie domyślnego Animate tylko dla hold-tray.
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| ANI-02 | 4 animacje gracza: hold-tray idle/walk, cook/hand-over loop (1,2 s), hammer (budowa/naprawa), cheer. Wgranie na grupę, test na 3 typach ciał, animation events dla punktu trafienia | 1,5 | M | MVP | SYS-03 |

### UI (Ui)
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| UI-01 | Style kit: paleta, font, przyciski, ramki, 12 ikon | 1,5 | M | MVP | – |
| UI-02 | HUD: gotówka, timer, HP ciężarówki, dzień x/5 | 1,5 | M | MVP | UI-01 |
| UI-03 | Bilety zamówień nad okienkiem + lista na HUD, pasek cierpliwości | 1,5 | M | MVP | SYS-05 |
| UI-04 | Prompty interakcji, wskaźnik noszonego, ammo bar wież | 1 | S | MVP | SYS-03 |
| UI-05 | UI trybu budowy (wybór, koszt, podgląd) | 1 | S | MVP | SYS-08 |
| UI-06 | Sklep ulepszeń | 1,5 | M | Launch | SYS-11 |
| UI-07 | Ekran wyników dnia/nocy/runu | 1 | S | MVP | SYS-02 |
| UI-08 | Tutorial 5 kroków (UI + logika), kroki zapisane jako funnel | 1 | S | Launch | UI-02 |
| UI-09 | Ustawienia: suwaki Music/SFX (SoundGroups), opcja ograniczenia błysków | 0,5 | S | Launch | AUD-01 |
| UI-12 | Mobile pass: Scale + UIScale, ScreenInsets, emulator (mały telefon, tablet, 1080p), przyciski nie pod jumpem | 1,5 | M | MVP/Launch | UI-02..07 |

### Audio (Ui)
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| AUD-01 | ~25 SFX + 3 muzyki z Creator Store (menu/dzień, noc, wygrana); SoundGroups Music/SFX/UI; sprawdzić licencje i uprawnienia | 1 | S | MVP/Launch | – |

### VFX (Ui)
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| VFX-01 | 8 efektów: dym stacji, trafienie, ogień sosu, splat, wybuch, poof zombie, monety, ulepszenie. Budżet cząsteczek pod telefon★ (-3 efekty) | 1,5 | M | Launch | MOD-04 |

### Monetyzacja (Ui + Sk review)
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| MON-01 | 2 gamepassy (Double Tips, Złota Ciężarówka – kosmetyka) + 2 produkty (Cash Boost, Natychmiastowa naprawa). `ProcessReceipt` idempotentny, zapis przed PurchaseGranted. Darmowa ścieżka do każdej funkcji; bez losowych skrzynek | 1,5 | M | Launch | DATA-01 |

### Analityka (Ui)
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| AN-01 | Funnel onboardingu, LogEconomyEvent dla gotówki (źródła/ujścia), event „noc ukończona/przegrana”, funnel sklepu | 0,5 | S | Launch | UI-08 |

### Publikacja i zgodność (Ui)
| ID | Zadanie | Dni | Rozm. | Priorytet | Zależy od |
|---|---|---|---|---|---|
| PUB-02 | Kwestionariusz dojrzałości (zombie, cartoon violence, brak losowych płatnych przedmiotów), ikona 512×512 czytelna w 150×150, 5 miniatur 1920×1080, opis, linki do grupy, urządzenia | 1,5 | M | Launch | PUB-01 |

### QA i wydajność (wszyscy, z bufora)
- Team Test co tydzień (3 osoby + 1–2 znajomych), tracker błędów (lista w Notion/Trello).
- Testy: pierwsze wejście, ponowne wejście, zamknięcie serwera w trakcie zapisu, 2 urządzenia, zakupy w Studio, exploit na każdym remote, pełny serwer 4 graczy, niskie telefony, F9 i MicroProfiler.

### Launch i live-ops
| ID | Zadanie | Priorytet |
|---|---|---|
| LIV-01 | Dzienna nagroda + kody startowe (Sk/Ui) | Post (★ jeśli czas) |
| LIV-02 | Boss nocy 5 (model, animacje, logika) | Post |
| LIV-03 | Rewarded video ads (wymaga 2 000 unikalnych odwiedzających/mies. i weryfikacji) | Post |
| LIV-04 | Aktualizacje co 2 tyg.: nowe przepisy, wieże, mapa; pomiar D1/D7 | Post |

## Test mocy (capacity check)
| Rola | Zaplanowane | Brutto (8 × 15 h) | Wolne |
|---|---|---|---|
| Skrypter | 20 dni | 24 dni | 4 dni (17%) |
| Builder | 18 dni | 24 dni | 6 dni (25%) |
| UI | 19,5 dnia | 24 dni | 4,5 dnia (19%) |
| **Razem** | **57,5** | **72** | **14,5 (20%)** |

**To mniej niż 30% bufora**, więc plan jest ciasny. Dlatego mamy z góry ustaloną **listę cięć** (~6 dni, daje ~29%), którą stosujemy bez dyskusji, gdy koniec tyg. 5 pokaże poślizg:
1. MAP-02 dressing mapy: −2 dni (mniej rekwizytów).
2. Pie Cannon wycięta (model + logika): −1,5 dnia, zostają 2 wieże.
3. Tank zombie: −0,5; Chili Mine: −0,5; skalowanie trudności: −0,5.
4. VFX 8 → 5 efektów: −0,5.
5. Dzienna nagroda i kody: nie planowane.

**Co już uproszczono** (żeby w ogóle się zmieściło): zombie to rigi R15 (bez własnego rigowania), jedna mapa, jedna ciężarówka, brak mechaniki obalenia/reanimacji gracza (gracze nie giną), brak bossa i progresji przepisów, jedna wspólna animacja gotowania, wszystko sterowane tabelami danych, dźwięk z Creator Store. Skrypter jest wąskim gardłem: reszta zespołu nie może go zablokować, więc modele i UI idą na placeholderach, dopóki systemy nie stoją.

## Kamienie milowe
| Tydz. | Etap | Kryterium wyjścia |
|---|---|---|
| 1–2 | **M1 Prototyp/greybox**: SYS-01..07, MAP-01, kostki zamiast modeli, UI z Textlabeli | 3 osoby grają 10+ min bez pytania „co robić” |
| 3–5 | **M2 Vertical slice**: noc 1–2 z finalną sztuką: MOD-01..06, ANI-01/02, UI-01..05/07, MAP-03, SYS-08..11 | wygląda i działa jak gra; 4 graczy przechodzi dni 1–2 |
| 6–7 | **M3 Soft launch (znajomi, grupa)**: DATA-01, SEC-01, MON-01, AN-01, UI-06/08/09/12, kwestionariusz, ikona | zapis działa po rejoin; D1/D7 i długość sesji mierzalne; zero błędów w F9 na telefonie |
| 8 | **M4 Launch**: PUB-01/02, MAP-04, poprawki z danych, post na social | otwarta publicznie, grupa i linki gotowe |
| 9+ | **Live-ops**: aktualizacja co 2 tyg., LIV-02..04 | każda aktualizacja ma cel (np. podnieść D7) |

## Ryzyka
1. **Skrypter jako wąskie gardło (20/24 dni).** Mitygacja: lista cięć, placeholdery dla reszty, ProfileStore zamiast własnego zapisu, dane w tabelach.
2. **Ciężarówka bez „zabawy” w nocy, gdy gracze tylko czekają.** Mitygacja: ładowanie amunicji i naprawa to ciągła praca; test w M1, zanim powstanie sztuka. Jeśli nuda: skrócić noc, dodać zdarzenie (Runner z flanki).
3. **Animacje R15 nie działają na części avatarów** (duże akcesoria, Rthro). Mitygacja: testy ANI-02 na 3 ciałach, items przypięte do dłoni, tacka mała.
4. **Brak uprawnień do assetów w produkcji** (animacje, audio, meshe działają w Studio, w grze nie). Mitygacja: wszystko wgrywane na grupę od dnia 1, test publiczny w tyg. 5, nie 8.
5. **Rozjazd stylu** przy trzech osobach. Mitygacja: wspólna paleta kolorów w tyg. 1 (UI-01 + modele z tej samej palety), jedna osoba (Bd) zatwierdza wygląd.
6. **Bałagan z losowymi płatnymi przedmiotami i prawami do audio.** Mitygacja: bez skrzynek; tylko Creator Store lub własne.

## Pierwszy tydzień
- **Skrypter:** SYS-01 (struktura, Remotes, tabele danych), SYS-02 (maszyna stanów dzień/noc z timerem i ekranem testowym), start SYS-03 (noszenie). Cel: do niedzieli da się wziąć składnik i zobaczyć zmianę dnia na noc.
- **Builder:** MAP-01 greybox (bramy, slots, strefa ciężarówki) w 2 dni, żeby skrypter miał gdzie testować. Potem MOD-01 (ciężarówka) i ustalenie palety 256×256 razem z UI. Eksport testowy do Roblox: skala i jednostki.
- **UI:** UI-01 (paleta, font, przyciski, ikony), UI-02 (HUD z placeholderami), dołożyć testowe bilety (UI-03). Założyć grupę, ustawić uprawnienia, wgrać pierwsze dźwięki z Creator Store.
- **Wspólnie (sesja 1):** 1 h: lista przepisów (4 dania z 6 składników), liczby (cena dania, HP ciężarówki, koszty wież), nazwa i skala świata. Sesja 3: pierwszy Team Test.
