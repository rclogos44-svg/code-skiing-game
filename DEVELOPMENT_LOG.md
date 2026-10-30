# SUMMIT — Development Log

Open-world extreme skiing game built with **Godot 4.6.3** (official build, checksum-verified),
exported as native desktop builds for Windows x64, macOS (universal) and Linux x64.

## Workspace layout

```
summit_dev/
  project/            Godot project (game source)
    scripts/core/      Settings (persistent + rebinding), Game (save/progress), Sfx
    scripts/world/     TerrainData, CDLOD TerrainRenderer, Atmosphere, Vegetation, Resort, Obstacles, World
    scripts/player/    Skier (physics), SkierBody (procedural animation + IK), SkierModel (meshes),
                       SkierRagdoll (verlet), SkierAudio
    scripts/camera/    CameraRig (third-person / chase / first-person / menu orbit)
    scripts/gameplay/  TrickSystem, ChallengeManager, POIManager (spotting & discovery)
    scripts/ui/        HUD, Menus, SettingsMenu, MapScreen, UITheme
    scripts/tools/     test_runner.gd (automated tests), validate.gd
    shaders/           terrain, sky, rock
    world/             generated heightmaps, normal/surface/bake maps, trees/rocks, layout.json
    assets/            generated textures and audio
  build/              automated pipeline (see below), generators, C terrain kernels
  tools/              portable Godot editor + export templates, Mesa lavapipe (tests only)
  dist/               exported builds and packaged ZIPs
  previews/           screenshots produced by automated tests
```

## Build pipeline (`build/build_all.sh`)

| Step | Script | What it does |
|---|---|---|
| 1 | `00_check_env.sh` | OS/arch/tool report |
| 2 | `01_get_tools.sh` | Downloads Godot 4.6.3 editor + export templates from the official GitHub release, verifies SHA-512, installs in self-contained mode inside `tools/`; fetches Mesa lavapipe for software-Vulkan testing |
| 3–4 | `02_gen_assets.sh` | Compiles C terrain kernels, generates world, textures, audio, icons |
| 5 | `03_import.sh` | Headless import + texture compression parameters |
| 6–7 | `04_validate_and_test.sh` | Script/resource/input/layout validation, physics tests, rendered smoke test |
| 8 | `05_export.sh` | Native release exports for all three platforms + exported-binary test |
| 9 | `06_package.sh` | `SUMMIT/` folder + README + licenses → ZIP per platform |

Nothing is installed system-wide; everything lives under `summit_dev/`.

## Environment notes / blockers encountered

- Development container: Linux x86_64 (Ubuntu 24.04), 4 cores, no GPU.
- The network policy blocks Poly Haven, ambientCG, Quaternius and tuxfamily, so **no external art
  assets could be downloaded**. All content (terrain, textures, models, animation, sounds) is
  generated procedurally — no Blender.
- GitHub releases are reachable, so the official Godot binaries and templates were used.
- No GPU: visual tests render through Mesa lavapipe (software Vulkan). Frame times measured here
  are CPU-rendered and **not representative of real GPU performance**; only CPU-side costs, draw
  calls and primitive counts are meaningful.
- The user's OS could not be detected from a cloud container, so all three desktop targets are built.

## Phase 1 — Playable prototype (done)

**World generation** (`build/gen_terrain.py` + `terrain_kernels.c`)
- 6.1 × 6.1 km playable core at 2 m resolution (3073² heightmap) plus an 18 km backdrop ring.
- Macro relief: tectonic uplift + implicit stream-power fluvial erosion (Braun & Willett) on a
  513² grid → realistic dendritic valleys with no closed basins; smoothed, scaled, slope-clipped
  with per-region talus angles, and re-incised so rivers breach dams.
- Detail: warped ridged multifractal, region-specific cliff terraces, 3.5 M-droplet hydraulic
  erosion, thermal erosion, snow-fill smoothing, priority-flood depression filling.
- Six regions (Alpine Summit, Powder Valley, Pinewood Forest, Rocky Ridge, Mountain Resort,
  Extreme Backcountry) with their own roughness, powder, ice, tree and cliff parameters.
- Baked products: normal map, surface map (powder depth / groomed / ice / tree density), baked sun
  visibility + AO, stylised map image, 77 k tree and 12 k rock placements.
- Adaptive layout: drop zones on skiable slopes, lifts auto-placed above the village, pistes and
  race lines routed by a slope-aware Dijkstra pathfinder, viewpoints on reachable knolls.

**Terrain rendering**: CDLOD quadtree, one MultiMesh of 16×16 patches, vertex-shader geomorphing,
heights fetched from the same heightmap the physics samples. Snow/ice/rock material with slope
blending, triplanar rock, detail normals, groomed corduroy, sparkle, baked long-distance shadows.

**Skier physics** (`skier.gd`, 120 Hz custom integrator)
- Gravity on slope, sidecut carving (R = R_sidecut·cos(edge)) limited by edge grip, lossless
  redirection while the edge holds, skid friction when it does not.
- Surface types: groomed / powder (drag + sink) / ice (low grip) / rock.
- Aerodynamic drag (upright vs tuck), carving speed scrub, snowplow, edge braking (hockey stop),
  pole push on flats, static friction.
- Ballistic ground constraint: takeoffs happen naturally off lips and convex rolls.
- Charged ollie, air spins with damping, grabs, landing evaluation (impact speed, alignment,
  switch landings with revert), crashes (hard landing, sideways landing, late grab, trees, rocks,
  buildings, cliff faces), safe-point respawn.

**Skier visuals**: procedural model (jacket, pants, helmet, goggles, gloves, boots, skis, poles),
IK legs/arms, inclination + angulation, tuck, snowplow, crouch, grabs, pole plants,
landing/bump absorption, verlet ragdoll with ski release on crashes.

**Camera**: smooth follow, speed-based distance/FOV, turn roll, terrain collision, chase and
first-person modes, mouse/right-stick look, scroll zoom.

### Phase 1 test results
- Validation: 27 scripts compile, all resources/audio/inputs present, layout sane — **OK**.
- Physics tests: **16/16 pass** (acceleration, tuck < drag, snowplow, edge brake > snowplow,
  gradual turning, carving, ollie airtime, landing, spin, flat deceleration, cliff-drop crash,
  respawn, tree collision).
- Exported Linux binary runs standalone and passes the same 16 physics tests.
- Rendered smoke test (software Vulkan): runs without script errors; ~420 draw calls,
  ~3.5 M primitives per frame at a resort spot (terrain shadows in 4 cascades dominate).
- OpenGL 3 fallback verified to render.

## Phases 2–5 status (implemented so far)
- Tricks: measured-rotation spins, grabs, air time, landing quality, combos with multipliers.
- HUD: speed, altitude/slope, region banner, trick popups, combos, challenge panel,
  notifications, crash message, spotting reticle, lift prompt, control hints.
- Challenges: 5 races (gates, medals), 5 freestyle (score / specific / combo), 2 extreme.
- Exploration: drop-zone spotting, viewpoints revealing regions, map with teleport.
- Resort: village chalets, 3 animated rideable chairlifts, 6 marked pistes, terrain park kickers.
- Menus: main (live 3D backdrop), pause, settings (graphics presets, resolution, window mode,
  shadows, render scale/FSR, view distance, AA, SSAO, bloom, vsync, FPS cap; sensitivity, invert,
  key rebinding; camera; audio), challenge list, free-ride picker.
- Audio: procedurally synthesized loops and one-shots mixed from physics state.
- Saves: settings (`settings.cfg`), progress (`save.json`), both automatic.

## Known limitations
- No external rigged character could be downloaded (network policy); the skier is a procedural
  segmented model, animated procedurally.
- Real-GPU performance has not been measured (no GPU in the build environment).
- Builds are not code-signed (SmartScreen / Gatekeeper prompts, see README).

## Browser version (added on request)

The Windows build was blocked by SmartScreen ("might have malware" — the exe is unsigned), so the
game now also runs as a web page: https://claude.ai/artifact/Bu3JkcUPegNmxL4FEZ1J4n

- Godot web export, single-threaded (no cross-origin isolation needed), WebGL 2 compatibility renderer.
- Hosting allows ≤15 MB per file, so `SUMMIT.wasm` and `SUMMIT.pck` are split into 14 MB `.wasm`
  chunks; a fetch shim in the page reassembles them as a stream (keeps the progress bar working).
- Two WebGL issues found and fixed by testing the build in headless Chromium:
  1. float (R32F) heightmap textures read back clamped to 1.0 → heights now stored as 16-bit
     values in RG8 texels, decoded in the shader and on the CPU (≤1.3 cm error, also halves size);
  2. block-compressed (BC5) textures read as black → all textures imported lossless.
- Web defaults: Medium preset, in-page window with a Fullscreen option, no Quit button,
  mouse-drag camera look if the browser refuses pointer lock.
- Download ≈ 85 MB (37.7 MB engine + 47.8 MB world data); verified loading and rendering in
  Chromium (SwiftShader). Not verifiable from here: real-GPU frame rate and the hosting page's
  security policy for WebAssembly (the loader shows a clear message if it is blocked).

## Phase 2 — turn animation rework
- Lean now follows the *measured* sideways acceleration of the path (not the ski rotation rate),
  through a critically damped spring, capped at ~50°: smooth roll-in and edge changes.
- Angulation: legs take the full inclination, torso ~40%, head keeps the eyes level and looks
  into the turn. (The old torso roll had the wrong sign and over-leaned the upper body.)
- Upper body faces the direction of travel and lags ski pivots instead of snapping with them;
  hips follow at 45%.
- Flex through the turn / extend through the edge change; wider stance and inside-ski lead at
  high edge angles; inside hand forward, outside hand back.
- Legs absorb small bumps (skis pressed back to the snow; partial grip just above it).
- Measured carve radius (sim): 10 m @ 34 km/h, 18 m @ 55, 33 m @ 77, 54 m @ 100 km/h.
  An earlier "weak high-speed steering" result was a test bug (skier launched off the slope).

## Phase 4 — a less plain mountain (world features) and a real trail map

**Terrain features** (`build/features.py`, stamped into the heightmap after erosion)
- 25 named cliff bands (3–17 m drops; biggest in Rocky Ridge / Extreme Backcountry, small
  "starter" drops in Powder Valley, Pinewood and the resort), 10 natural kickers / wind lips,
  3 halfpipe gullies, a frozen lake in a natural basin, a mogul field on the black run, 3 glade
  trails cleared through the forest.
- Landmarks with procedural models: summit cross on a cairn, backcountry cairn, mountain hut,
  weather station (spinning anemometer), trapper's cabin ruin. All features and landmarks are
  discoverable (counted as "Discoveries").
- Trees and rocks are kept out of each cliff's and kicker's run-in / landing corridor; boulder
  fields sit on the flanks of cliff bands instead of in the landing.
- Terrain shader: snow-bounce fill light on steep faces (cliffs were rendering almost black),
  less AO on rock, frozen-lake ice with less mirror-like reflection so it reads as ice.

**Feature test** (`--test=features`): skis a straight tuck line over every cliff and kicker and
rides each gully. Result: every cliff and kicker launches the skier (0.7–3.0 s of air); small
drops land cleanly; the biggest (13–17 m) cause hard-landing crashes when hit straight at
75–90 km/h, as intended; gullies ride without crashing (walls 45–50°). Remaining crashes in that
test are trees hit 60–170 m further down the straight line, well past the landings.
(An earlier "kickers don't launch" result was the test ending before the skier landed.)

**Mountain map** (`build/map_render.py` + `scripts/ui/map_screen.gd`)
- New 2048² painted map image: NW-lit multi-directional hillshade with blue snow shadows,
  grey rock with strata, every tree drawn individually with a drop shadow, frozen lake, 50 m /
  250 m contours, named summits (stored in `layout.json` → `peaks`).
- Map screen: clipped zoomable view (scroll, +/-, drag, trackpad gestures), pistes with
  difficulty colours, lifts with towers, summits with elevations, region names, cliff/kicker/
  gully/trail/landmark symbols for discovered spots, binoculars for viewpoints, flag/star/bolt
  icons for races/freestyle/extreme, race route preview on hover, player arrow with view cone,
  compass and scale bar, label collision avoidance, hover cards (elevation, distance, best
  medal, "click to travel"), side panel with progress bars and a legend. HUD hidden while open.
- Verified by screenshots in the desktop build (Xvfb) and in the web build (headless Chromium).

## Phase 4b — on foot, real chairlifts, minimap, hockey stop (research-driven)

Research notes on Grand Mountain Adventure 2, Steep and Riders Republic are in `RESEARCH.md`
(ideas only; nothing copied). What came out of it:

- **Hockey stop replaces the snowplow** (S). The skis pivot ~82° across the direction of travel
  (toward the hill, or the side you steer), edges set, snow sprays forward, with an edge-scrape
  sound. Progressive: a tap checks speed, holding stops. Animation after the PSIA description:
  quick unweighting pop, drop into a low flexed stance, the upper body keeps facing downhill
  while the skis pivot underneath (up to ~70° of separation), lean into the hill.
  Tests: 37 km/h -> stopped in 1.95 s on a 24° slope; skis reach 82° to the direction of travel;
  a 0.3 s tap only checks speed (10.2 -> 9.2 m/s); the stopped skier holds on the slope.
- **On foot** (T): skis come off at rest, then camera-relative walking (1.8 m/s), jogging (Shift,
  3.4 m/s) and hopping (Space); slower uphill and in powder, impossible above ~40°, sliding
  back off steeper ground. Gait animation in ski boots with heel-to-toe feet, skis over the right
  shoulder, poles in the left hand used as a hiking stick; binding click and footstep sounds.
- **Chairlifts rebuilt for clarity**: chairs every ~36 m (~6.5 s) instead of 22 m, lines 6.8 m
  apart, colour-coded quad chairs per lift (seat, back, safety bar, footrest), riders on the
  way up and empty chairs coming down, coloured terminal housings with bull wheels, towers with
  sheave trains, a blue LOAD HERE mat, an UNLOAD sign and a lift sign with vertical and ride
  time. You really ride: stand on the mat, the next chair arrives from behind, you sit and ride
  (side-on camera, look around with the mouse), and get off at the unloading ramp. The lift runs
  "express" (3x) while you are on it; holding G skips to the top.
- **Minimap** (top-right, can be turned off; turns with the camera or north-up): pistes, lifts,
  open drop zones, next race gate and waypoint pinned to the rim with their distance.
  Notifications moved below it.
- **Map waypoints**: click anywhere on the map that is not a drop zone/challenge to set a
  waypoint (click it again to remove). It shows on the map, the minimap and as a cyan light beam
  with its distance in the world, and clears when you reach it.
- **NPC skiers**: 18 skiers carving S-turns down the pistes (visual only).
- Physics test suite now 31 checks (hockey stop, walking/hiking, lift boarding/riding/unloading),
  all passing. The gameplay simulation's 360 test was made robust (it released the spin too late
  for the new terrain's air time).
- Open issue: the gameplay test's simple race autopilot cannot finish three backcountry races
  (Powder Rush, Timber Slalom, Widowmaker Line) - it tucks straight at gates across 40-48° terrain
  and keeps crashing. The races are skiable by choosing a line, but their medal times are not
  verified by simulation yet.

## Phase 2 — physics-based skiing (inspired by Jibbers; see RESEARCH.md)

Hybrid approach: the proven snow/edge model stays; the body now drives pop and rotation.
- **Weight shift (Up/Down arrows)**: forward = crisper turn entry; back = tips wash out (less
  grip). Crouching (Space) with the weight back loads the tails: let go of Down just before the
  pop for a bigger ollie (tested 1.68 m vs 1.31 m), keep holding it for a backflip (Up: front flip).
  Popping off a compression (landing, bump) adds pop too.
- **Spins from the wind-up (Left/Right arrows on the ground)**: shoulders counter-rotate; at
  takeoff the wind-up becomes spin (186° in 0.5 s with no air input). Carving rotation still
  carries over. Kicker lips and rollovers add their own pitch rotation.
- **In the air**: arrows (and Q/E) adjust spin and flip; tucking or grabbing spins ~30% faster.
  Grabs while leaning become tip / tail grabs. Knees tuck during flips.
- **Landings** judged on yaw, flip pitch and impact: "Landed on your back / head", hard and
  sideways landings; close calls trigger a short recovery (arms windmill, less grip).
- **Skis flex** visibly under load (shader), and spring back in the air.
- **Three difficulties** (Settings > Controls): Easy (strong air control, auto-levelling,
  forgiving landings), Normal, Realistic (rotation essentially from the takeoff, tight landing
  tolerance, edges can catch when skidding sideways fast on a flat ski).
- **Tricks**: flips (Backflip/Frontflip, Double, Triple), corks (off-axis spins), tip/tail grabs.
- Tests: physics suite 48 checks (pop loading, backflip start, wind-up spin, tuck spin rate,
  per-difficulty air control, upside-down landing crash) and trick naming unit tests, all
  passing; all natural kickers that landed before still land on Normal.
