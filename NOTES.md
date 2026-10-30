# Horyzont — notatki robocze

Spokojna gra o jeździe autem po wyspie. Najważniejsze jest światło: wschody,
zachody, chmury i pogoda. Prosty gameplay, cel 60 fps na MacBooku Air M4.

Silnik: Godot 4.7.2 (Forward+, Metal, Jolt, MetalFX temporal upscaling 0.58).

## Uruchamianie

```bash
godot --path .                       # gra
dev/run.sh 90 --windowed --resolution 1280x800 -- --shots=res://dev/shots_sky.json
```

Argumenty gry (po `--`): `--time=19.5`, `--weather=pogodnie`, `--cam=x,y,z`,
`--look=x,y,z`, `--shots=<json>` (renderuje listę ujęć do PNG i wychodzi),
`--dump_noise`, `--no_dome`, `--debug_sky`.

## Architektura

- `scripts/core/game.gd` — autoload `Game`: argumenty CLI i referencje
  (`Game.sky`, `Game.clock`, `Game.weather`, `Game.car`, `Game.world`).
- `scripts/core/main.gd` — buduje świat w kodzie (environment, niebo, światła).
- `scripts/sky/sky_system.gd` — LUT-y atmosfery (SubViewporty HDR), bake szumu
  chmur na GPU, kopuła nieba (opaque, unshaded, z motion vectors → MetalFX),
  materiał nieba Environment (ambient + odbicia, realtime 256).
- `scripts/sky/time_of_day.gd` — zegar, słońce/księżyc, kolor światła z
  transmitancji, krzywa ekspozycji (`env.tonemap_exposure`!), mgła.
- `scripts/sky/weather.gd` — presety pogody + płynne przejścia, wiatr, mokrość.
- `shaders/atmosphere.gdshaderinc` — Hillaire 2020 (km, środek planety w 0).
- `shaders/clouds.gdshaderinc` — chmury wolumetryczne (Schneider) + cirrusy.
- `shaders/sky_common.gdshaderinc` — złożenie nieba, gwiazdy, księżyc, słońce.

### Globalne uniformy shaderów (project.godot → shader_globals)
sun_direction, moon_direction, sun_illuminance, moon_illuminance, mie_scale,
cloud_* , cirrus_*, star_rotation, night_factor, frame_jitter, wetness,
rain_amount, world_wind. Ustawiane z GDScript przez
`RenderingServer.global_shader_parameter_set`. UWAGA: `global_shader_parameter_get`
nie działa w grze (tylko edytor) — trzymaj wartości po stronie skryptów.

### Lekcje
- Ekspozycja przez `CameraAttributes.exposure_multiplier` NIE działa na
  materiały unshaded → używamy `Environment.tonemap_exposure`.
- SubViewporty do bake'u: `use_hdr_2d = true` + `render_mode blend_disabled`,
  inaczej wartości są konwertowane sRGB i tracona jest alfa.
- Sky w trybie INCREMENTAL nie odświeżał się na zmianę globali → REALTIME.

## Interfejsy dla modułów (UI, audio)

Auto (`Game.car`, może być null): `speed_kmh: float`, `rpm: float`,
`gear: int`, `throttle: float`, `slip: float` (0..1), `is_reversing: bool`.
Zegar (`Game.clock`): `time` (godziny 0..24), `time_scale`, `paused`,
`sun_elevation_deg()`, `hours_until_elevation(deg, rising)`.
Pogoda (`Game.weather`): `current_id`, `preset_name()`, `set_preset(id, instant)`,
`PRESETS` (słownik id → {name, ...}), `auto_cycle`, `rain`, `wetness`.

## Świat
- `scripts/world/terrain_data.gd` — heightmap 4096² (2,5 m/texel, 10,24 km) baked na GPU
  (`shaders/bake/terrain_height.gdshader`), droga (pętla ~23 km) planowana i wcinana na CPU,
  cache `user://cache/terrain_v8.bin` (`--regen` wymusza). Kolizja: HeightMapShape3D co drugi texel + trimesh drogi.
  Mapa ekosystemu `terrain_eco.gdshader` (4096²): R trawa, G las, B krzewy, A suchość. Czyta ją teren, trawa i las.
- `terrain_renderer.gd` + `shaders/terrain.gdshader` — clipmap 7 poziomów, 6 materiałów 4K (łąka, ściółka, 2 skały,
  piasek, żwir), mieszanie po wysokości, tekstury rozgałęzione po wagach.
- `water_renderer.gd` + `shaders/water.gdshader` — ocean na clipmapie, Gerstner, głębokość z heightmapy.
- `grass_field.gd` + `shaders/grass.gdshader` — kafle źdźbeł (3 LOD). Co klatkę lista widocznych kafli idzie do tekstury-tabeli,
  z której vertex shader czyta pozycję po INSTANCE_ID. Bufory MultiMesh się nie zmieniają, więc motion vectors są poprawne.
  `shaders/meadow_decor.gdshader` — kłosy (skan) i kwiaty na tej samej tabeli.
- `forest.gd`, `tree_gen.gd`, `shaders/tree_*.gdshader` — ~200 tys. drzew i krzewów: LOD0 i LOD1 (siatki, tabela jak w trawie),
  impostory od 88 m (8 widoków na wariant, wypiekane przy starcie z tych samych siatek). Cienie: LOD1 do 46 m, bryły do 125 m.
- `props.gd` — murki, domy, barierki, latarnia, skanowane głazy i pnie (`assets/models/baked`), paprocie przy drodze.
- `road_builder.gd`, `shaders/road.gdshader`, `rain.gd`.
- `scripts/car/` — `car.gd` (raycast vehicle, autopilot), `car_model.gd` (proceduralne GT), `camera_rig.gd`.
- `scripts/core/postcards.gd` — 9 pocztówek (miejsce + warunek światła/pogody), album w `user://album`.
- `scripts/ui/*` i `scripts/audio/*` — napisane przez Groka (cursor-agent), zintegrowane w main.gd.

## Zasoby i narzędzia
- `dev/tools/fetch_assets.py` pobiera zasoby CC0, `dev/tools/fix_imports.py` ustawia kompresję VRAM i mipmapy.
- `godot --path . -- --bake_foliage` składa atlasy gałązek ze skanów liści (`assets/foliage/baked`).
- `godot --path . -- --bake_models` upraszcza skany do `assets/models/baked/*.res`.
- Po dodaniu pliku: `godot --headless --path . --import`, potem `fix_imports.py`, potem znowu `--import`.

## Niebo (cd.)
- Atmosfera i chmury liczą się w połowie rozdzielczości w `sky_lowres.gdshader` (dwa SubViewporty na zmianę, historia z
  reprojekcją po obrocie kamery). `sky_dome.gdshader` dokłada tylko słońce, księżyc i gwiazdy.
- `cloud_shadow_pass.gdshader` — mapa cieni chmur 256² wokół kamery (8 km), odświeżana co 3 klatki, czytana globalnie.

## Wydajność (MacBook Air M4, 2940×1846, MetalFX 0.58, preset „wysoka”)
WYDAJNOSC_PLACEHOLDER
Stały koszt (MetalFX, tonemapping) to ok. 6,2 ms, reszta klatki skaluje się z liczbą pikseli.
Przy szukaniu kosztów: `--perf_off=trees,grass,clouds,ssr,ssao,glow,shadow,treeshadow,impostors,sharpen`, a ławka w konkretnym
miejscu: `dev/run.sh 60 -- --bench=6 --mode=chase --uncapped --road_near=3200,0,1600 --time=13 --weather=cumulusy`.
Pomiary mają sens tylko gdy nic innego nie używa GPU.

## Lekcje (cd.)
- Gęstość mgły Godota: ~12× „podręcznikowej” (mnożnik w weather.gd).
- Nowe class_name wymagają `godot --headless --path . --import` przed uruchomieniem.
- `--check-only` nie widzi autoloadu `Game` → `dev/check.sh` filtruje te błędy.
- Kolor łąki pochodzi z palety w shaderze, wspólnej dla terenu i źdźbeł, żeby daleka trawa wtapiała się w bliską.
- Mipy alfy zjadają cienkie liście (`tree_alpha`), a daleko zamieniają impostor w pełny prostokąt (limit LOD w shaderze).
- W `light()` każdy człon niezależny od ATTENUATION musi być tylko dla świateł kierunkowych, inaczej reflektory świecą w całym klastrze.
- MultiMesh bez ustawionych transformacji ma macierze zerowe: nawet przy własnych pozycjach trzeba wpisać Identity.
- Przy interpolacji mapy ekosystemu liczy się rozdzielczość: 5 m/texel wynosiło trawę na asfalt, stąd 2,5 m i próg w shaderze.
- Dwie warstwy przenikania LOD muszą używać przeciwnych końców tego samego szumu, inaczej zostają dziury.

## Stan / następne kroki (30.10, wieczór)
- [x] Niebo, chmury (kopuły, półrozdzielczość), cykl dnia, pogoda, deszcz, mgła
- [x] Wyspa 2,5 m, łąka z kłosami i kwiatami, las, krzewy, skały, klify, paprocie
- [x] Auto, kamery, UI, audio, pocztówki, tryb foto w natywnej rozdzielczości
- [ ] Ręczny test jazdy na klawiaturze i odsłuch dźwięku
- [ ] Eksport .app (wymaga export templates, ~1 GB)
Zrzuty pokazowe: `screenshots/` (generuje `dev/shots_beauty.json`).
