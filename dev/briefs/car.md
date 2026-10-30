# Task: make the car look like a real, modern sports coupe

Godot 4.7 project (Forward+, Metal). Working directory is the project root. The world around the car
has just been rebuilt with scanned foliage and now looks photographic; the car is the weakest thing
on screen. From behind it reads as a smooth red blob: no trunk lid, no bumper, no window frames.

## Scope
Only change `scripts/car/car_model.gd`, and add new shaders named `shaders/car_*.gdshader` if useful.
Do not touch any other file. Do not commit. Do not download anything; everything stays procedural.

## Keep this API (car.gd and others use it)
`class_name CarModel`, `extends Node3D`, `GROUND_Y`, `wheels` (Array of Node3D that car.gd spins and
steers), `headlights` (Array[SpotLight3D]), `tail_light`, `paint`, `glass`, `head_mat`, `tail_mat`,
`Car.MOUNTS` for wheel positions, and any public method currently called from car.gd or scripts/ui.
Read car.gd first and confirm nothing it uses disappears. Physics dimensions must not change:
wheelbase, track and overall length/width stay as they are.

## What it should look like
A low, wide, modern two-door grand tourer, in the spirit of a current Italian or British GT but not a
copy of any real model. Think clear surfaces and sharp character lines, not soft pebbles.
- Silhouette: long bonnet, cab set back, fast roofline, short rear deck with a small ducktail.
- Replace the single soft loft with distinct parts: bonnet, wings over the wheels, doors, roof, trunk
  lid, front and rear bumpers, sills. Sections should be boxier (superellipse exponent well above 2)
  with a crisp shoulder crease running from headlight to tail light.
- Visible panel gaps (thin dark lines) for doors, bonnet and trunk lid: real geometry or a shader.
- Wheel arches that are actually cut out, not painted on; dark arch liners so no sky shows through.
- Glasshouse: windscreen, side windows and rear window as separate dark glass with visible A, B and C
  pillars and a roof panel. Window frames in black trim.
- Rear view matters most because the camera is behind the car nearly all the time: full-width slim
  tail light with a darker lens housing and inner LED segments, trunk lid edge, rear bumper with
  license plate recess, dark lower diffuser with fins, two exhaust tips with visible inner darkness.
- Front: slim headlights with inner lens detail, grille opening with mesh pattern, splitter.
- Details: door mirrors on stalks attached to the doors, door handles, side skirt, fuel cap line.
- Wheels: tyres with a rounded shoulder and sidewall, multi-spoke alloy rims (10 to 14 spokes), dark
  inner barrel, brake disc with a caliper. Rims must rotate with the `wheels` nodes.
- Paint: deep red metallic with clearcoat (StandardMaterial3D `clearcoat`, low roughness). No bright
  outlines at the silhouette: the current model has a pale halo, find out why and remove it.

## Budget
Under 60 000 triangles in total, under 12 draw calls. Normals must be smooth on surfaces and hard on
creases (split vertices at creases). Make sure faces are wound correctly and nothing is inside out.

## How to check your work
Run `dev/check.sh` for parse errors, then render screenshots and look at them. Close views:

    cat > dev/out/shots_grok.json <<'J'
    [ {"time": 13.0, "weather": "pogodnie", "drive": 3, "mode": "chase", "car_cam": [0.0, 1.1, 5.5], "out": "/ABS/PATH/dev/out/car_rear.png", "frames": 12, "width": 1400},
      {"time": 13.0, "weather": "pogodnie", "drive": 1, "mode": "chase", "car_cam": [3.6, 0.9, 3.6], "out": "/ABS/PATH/dev/out/car_rq.png", "frames": 12, "width": 1400},
      {"time": 13.0, "weather": "pogodnie", "drive": 1, "mode": "chase", "car_cam": [4.2, 0.7, -3.0], "out": "/ABS/PATH/dev/out/car_fq.png", "frames": 12, "width": 1400},
      {"time": 18.5, "weather": "pogodnie", "drive": 1, "mode": "chase", "car_cam": [-5.5, 0.7, 0.0], "out": "/ABS/PATH/dev/out/car_side.png", "frames": 12, "width": 1400} ]
    J
    dev/run.sh 90 -- --shots=res://dev/out/shots_grok.json

(replace /ABS/PATH with the output of `pwd`). Keep iterating until the four images look like a car
from a modern racing game: at least three full rounds of render, critique, fix. Read the images.
Keep each render short and do not run benchmarks: another process is using the GPU at the same time.

## Report
Finish with a short list of what changed, the final triangle count, and anything you could not do.
