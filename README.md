# Horyzont

![Złota godzina przy drodze](docs/shots/01_golden_bok.jpg)

Spokojny road trip po wyspie na Atlantyku. Jeździsz krętą drogą wzdłuż klifów, plaż i
przełęczy, czekasz na idealne światło i robisz zdjęcia-pocztówki. Niebo, chmury, pogoda,
teren, auto i dźwięk są w całości proceduralne (Godot 4.7, Metal).

## Ujęcia
Statyczna scena: auto stoi, a obraz ma czas się ustabilizować. Preset Ultra w pełnej rozdzielczości (2940×1846), klatki z gry bez retuszu.

| | |
|---|---|
| ![Golden hour od tyłu](docs/shots/02_golden_tyl.jpg) | ![Pod słońce](docs/shots/03_golden_pod_slonce.jpg) |
| ![Koło w złotym świetle](docs/shots/04_golden_kolo.jpg) | ![Droga przez las](docs/shots/05_golden_las.jpg) |
| ![Zachód nad morzem](docs/shots/06_golden_morze.jpg) | ![Klify](docs/shots/07_golden_klify.jpg) |
| ![Wyspa z lotu](docs/shots/08_golden_wyspa.jpg) | ![Poranna mgła](docs/shots/09_poranna_mgla.jpg) |
| ![Burzowy zachód](docs/shots/10_burza.jpg) | ![Jazda w złotej godzinie](screenshots/01_zlota_godzina.png) |

## Uruchomienie
Wymaga Godota 4.7 (Forward+). Gra powstała i była testowana na macOS z Metal. Po sklonowaniu raz zaimportuj zasoby:
```bash
godot --headless --path . --import
```
Potem dwuklik `Horyzont.command` albo:
```bash
godot --path .
```

## Wydajność
MacBook Air M4, 2940×1658, render w 58% rozdzielczości i MetalFX. Pełny ekran jest o około 1 ms na klatkę wolniejszy.

| Preset | Otwarta trasa | Las |
|---|---|---|
| Wysoka | 46 fps | 40 fps |
| Średnia | 65 fps | 54 fps |
| Niska | 78 fps | 60 fps |

## Sterowanie
| Klawisz | Akcja |
|---|---|
| W / S lub strzałki | gaz / hamulec (przytrzymaj S na postoju = wsteczny) |
| A / D | skręt |
| Spacja | ręczny |
| C | zmiana kamery (pościg, daleko, maska) |
| K | tryb Kino (autopilot + filmowe ujęcia) |
| T (przytrzymaj) | przyspieszenie czasu — czekanie na zachód słońca |
| F | zdjęcie (pocztówka, jeśli jesteś w miejscu i światło się zgadza) |
| Tab | następna pocztówka |
| P | tryb foto (wolna kamera: WASD, Q/E góra-dół, Shift szybciej, Spacja zdjęcie; pełna rozdzielczość ekranu) |
| L | światła ręcznie (domyślnie same się włączają o zmroku) |
| R | powrót na drogę |
| H | ukryj HUD, Esc — pauza (pora dnia, pogoda, tempo czasu) |

## Pocztówki
Dziewięć miejsc na wyspie wymaga konkretnego światła albo pogody, np. złotej godziny na
klifach, niebieskiej godziny albo mgły w dolinie. Na miejsce prowadzi świetlny słup i
kompas w HUD. 3 gwiazdki dostajesz, gdy warunki się zgadzają, a słońce jest w kadrze.
Zdjęcia trafiają do albumu (menu → Album).

## Zasoby
Tekstury, liście i modele są na licencji CC0, źródła w [assets/CREDITS.md](assets/CREDITS.md).
