# Horyzont — notatki robocze

Spokojna gra o jeździe autem po wyspie. Najważniejsze jest światło: wschody,
zachody, chmury i pogoda. Prosty gameplay, cel 60 fps na MacBooku Air M4.

Silnik: Godot 4.7.2 (Forward+, Metal, Jolt, MetalFX temporal upscaling 0.62).

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

## Stan / następne kroki
- [x] Niebo, chmury, cykl dnia, pogoda
- [ ] Teren wyspy (heightmap GPU, clipmap), droga (spline, wycięcie w terenie)
- [ ] Woda (ocean), roślinność (Poly Haven CC0)
- [ ] Auto (raycast vehicle), kamery, autopilot „Kino”
- [ ] Gameplay: pocztówki, tryb foto, album
- [ ] UI (menu, HUD, ustawienia), audio silnika
- [ ] Wydajność na M4, presety jakości
