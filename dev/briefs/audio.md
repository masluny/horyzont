You are working in a Godot 4.7.2 project at /Users/macbookkacper/dev/horyzont (GDScript 2.0, static typing, TABS for indentation, English code comments, sparse comments). Read NOTES.md first for the architecture and the `Game` autoload interfaces.

TASK: procedural audio for a calm car game (no audio files exist, everything is synthesized).

RULES: only create files under scripts/audio/ and scenes/test/. Do NOT edit any other file. Do NOT use git. Do not download anything.

1. scripts/audio/car_audio.gd — `class_name CarAudio extends Node3D`.
   Uses AudioStreamPlayer3D children with AudioStreamGenerator streams (mix_rate 22050, buffer_length 0.12), filled in _process from get_stream_playback() using push_buffer(PackedVector2Array) for frames_available.
   Layers:
   - Engine: inline-4 four-stroke, firing frequency = rpm / 60 * 2. Harmonic stack (fundamental + 2nd..6th with decreasing amplitude, slight detune between two voices for warmth), plus intake noise (one-pole low-passed white noise) modulated at the firing frequency. Throttle raises loudness and brightness (more upper harmonics); off-throttle at high rpm gives a softer, slightly crackly overrun. Smooth all parameter changes (one-pole smoothing) to avoid clicks.
   - Wind: band-limited noise, loudness ~ (speed/150)^2.
   - Road rumble: low-passed noise, loudness ~ speed, stronger when `wet` (more hiss).
   - Tyre squeal: tone 700-900 Hz with noise-modulated pitch, loudness ~ slip.
   - Rain on the roof: crackle (sparse random clicks + filtered noise) scaled by `rain`.
   Public vars: `rpm := 800.0`, `throttle := 0.0`, `speed_kmh := 0.0`, `slip := 0.0`, `rain := 0.0`, `wet := 0.0`, `master_volume := 1.0`, `muted := false`, `auto_from_game := true`. When auto_from_game is true, each frame read Game.car (if not null: speed_kmh, rpm, throttle, slip) and Game.weather (rain, wetness) — guard everything against null.
   Performance budget: < 0.8 ms per frame total. Use phase accumulators, a precomputed 2048-entry sine table, no per-sample function calls in the inner loop, no allocations per frame (reuse PackedVector2Array).
2. scripts/audio/ambient_audio.gd — `class_name AmbientAudio extends Node`. Procedural ambience on a non-positional AudioStreamPlayer with a generator: sea waves (slowly swelling filtered noise, 6-10 s cycles), birds (short random chirps, FM sine sweeps) when Game.clock.time is 4.5..9.5, crickets (fast amplitude-modulated 4-5 kHz tone bursts) when time is 21..4, gentle wind gusts always. Public vars: `sea_amount := 0.5`, `enabled := true`, `master_volume := 1.0`.
3. scenes/test/audio_test.tscn + scripts/audio/audio_test.gd: a Node that creates CarAudio (auto_from_game = false) and AmbientAudio and sweeps rpm 800 -> 6500 and speed 0 -> 160 over 6 seconds, then quits.

VERIFY: run `godot --headless --path /Users/macbookkacper/dev/horyzont --check-only --script res://scripts/audio/car_audio.gd` (and for the other scripts) and `godot --headless --path /Users/macbookkacper/dev/horyzont res://scenes/test/audio_test.tscn --quit-after 600` — there must be no SCRIPT ERROR / Parse Error lines. Fix everything until clean. Never run a command without a timeout guard longer than 60 s.
Finish by printing a short summary of the files and public API.
