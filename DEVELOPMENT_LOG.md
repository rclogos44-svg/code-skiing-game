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

## Phase 2/4 — terrain park: rails and boxes

- Jib line below the three kickers on Meadow Way (`scripts/world/park.gd`): 3 boxes and 3 rails
  in two lanes, placed along the piste on gentle ground, top lines kept clear of snow bulges.
  New "Terrain Park" drop zone and "Rail Session" challenge (4 rail/box slides in 150 s).
  Rails and boxes show on the mountain map when zoomed in.
- Physics (`Skier._try_mount/_grind_step`): low boxes can be ridden onto from the snow, raised
  rails need a pop. Stance comes from how you land: along it = 50-50, across it = slide
  (switch when landing backwards). Speed from gravity along the feature and sliding friction
  (more when sliding sideways). Balance is an inverted pendulum held with A/D (self-righting on
  Easy, unstable on Normal, more so on Realistic where falling off is a crash). Up/Down press the
  tips / tails. Space pops off; a spin wound up on the rail releases as you leave.
- Scoring: "180 On", "Switch", "50-50" / "Box Slide" / "Rail Slide", "to Nose/Tail Press",
  time on the feature; rails score more than boxes. Rail scrape sound.
- Tests (physics suite, 55 checks): ride onto a box and slide it to the end; can't ride onto a
  rail at snow level but can pop onto it; Realistic with no input falls off, balancing with A/D
  (simple controller) reaches the end; landing across a box gives a slide.

## Phase 3 — graphics: conditions, gear, effects

- **Time of day** (Morning, Midday, Golden hour, Dusk) and **weather** (Clear, Light snow,
  Snowstorm, Valley fog) in Settings > Graphics: sun colour and strength, sky gradient, cloud
  cover, fog colour/density/height, ambient light and falling snow (none / light / blizzard with
  wind). The sun keeps its direction because the long-distance terrain shadows are baked for it,
  so "golden hour" and "dusk" are lighting moods rather than a lower sun.
- **Gear colours** (Settings > Skier): jacket, pants, helmet.
- **Boot prints** in the snow when walking (ring buffer of 240 prints).
- **Speed streaks** on screen above ~65 km/h (off with Settings > Camera > speed effects).
- Checked by screenshots of every condition (desktop renderer).
- Not done in this pass: new tree models, a new skier mesh, jacket flutter, deeper powder trenches.

## Phase 4 wrap-up — races and ghosts

- **Race routes**: routing now heavily penalises uphill (a skier stalls on a climb; Timber Slalom
  had a 5 m rise) and Widowmaker Line is routed with a 40° limit instead of 46°; trees are
  cleared 10 m (was 7 m) either side of every race line. Terrain features are unchanged.
- **Race bot (test only)** tries four strategies (straight at gates, along the routed line,
  speed-checked on steep ground, slow) and respawns when stuck, like a player would.
  Result: Village Sprint 1:35 (gold), Powder Rush 3:38 (bronze), Timber Slalom 3:00 (just over
  bronze), Summit Downhill 2:14 (bronze) are finishable. **Widowmaker Line is not verified**: on
  its 40-49° sections the bot lands sideways off bumps or skis into a boulder after respawning;
  a player steering and braking may well get down, but that is untested. Medal times are the
  generator's estimates; human players were not measured.
- **Ghost of your best run** in races: positions are recorded every 0.1 s; a new best time is
  saved (rounded) and replayed as a translucent cyan skier next time. Tested by running a race
  through the challenge system twice.
- Challenge list shows the full description (was cut off).
- Physics suite now 57 checks, all passing.

## Park skiing — the game becomes a terrain-park game (on request)

The open mountain is kept as scenery, but the game is now about three terrain parks. Requested:
no map, parks, keep the ragdoll crashes, black baggy gear, only flips, spins and rails for now,
"kind of realistic" but easy by default, quick resets, a lower camera, lip markings, browser first.

- **Parks** (`build/parks.py`, built by `gen_terrain.py`): Main Park, Big Air Park and Jib Garden.
  The generator finds wide, even 11–16° slopes, regrades a 560 m × 120 m run (3° staging area,
  low side banks), grooms it and keeps trees and rocks out. Each has three lines, signed at the top:
  progression (small kickers with tip boards, ride-on boxes), jump line (small / medium / large
  tabletops) and jib line (boxes, rails, tubes). 13 kickers and 20 rails, boxes and tubes in all.
- **Kickers are exact shapes, not heightmap bumps.** On the 2 m grid a 1.2 m kicker came out
  with a ~9° lip and gave no air. `TerrainData.height()` now adds each kicker analytically
  (parabolic ramp to the lip angle, flat deck, 32° landing) and `park.gd` builds a matching snow
  mesh, so what you see is what you ride. On kickers the skier reads the snow normal over ±0.25 m
  instead of ±1.2 m, which kept averaging the lip with the deck. Deck lengths are designed from
  the lip speed the physics actually gives at the speed on the sign (S 36, M 47, L 58 km/h), so
  you touch down ~40% down the landing. Orange lines mark each lip and knuckle.
- **Menu**: one button per park. **Tab** = back to the top of the current park, **Esc** > Choose
  Park. The map, minimap, drop zones, viewpoints and region banners are off. The spawn is 14 m
  above the drop-in, so you roll straight in.
- **Skier**: all-black gear: long baggy hooded jacket, baggy pants flared over the boots, glossy
  helmet, orange goggles, chunky boots, charcoal twin-tip skis (tails turned up). Gear colour
  options were removed for now. Arms follow a spring so they swing loosely.
- **Tricks for now**: spins, back/front flips (hold ↓/↑ at the pop), rails / boxes / tubes
  (A/D balance). Grabs and corks are switched off behind flags (`Skier.GRABS`, `TrickSystem.CORKS`)
  to be turned back on later. Difficulty defaults to Easy.
- **Camera** lower and closer (target 1.1 m, 3.9 m back).
- **Tests** (`--test=physics`, 74 checks, all passing): every park kicker is jumped at its sign
  speed on Easy and must land on the landing, with no crash (air 1.0–2.1 s); tucking from each
  park's top rolls into the park; skis stay on the boots in 12 flip attitudes; box, rail and
  balance checks (the Realistic check now enters a box off-centre, as a player would).
  `--test=parks` takes screenshots of a park top, the outfit, a kicker and a backflip.
  `--test=gameplay`: all passing except the Widowmaker race autopilot (open-mountain content that
  can't be reached in this version; it was already unverified, see above).
- **Browser build** checked in headless Chromium (software WebGL): menu, entering Main Park,
  skiing, Tab back to the top. Frame rate in the browser was not measured on real hardware.
- Not done yet: grabs, corks, more outfit options, park-specific sounds, scoring per line.

## Spins, flips and the skier (from the player's 360 / triple-backflip reference videos)

- **No tuck.** W is a pole push that only works below 4 m/s; once moving it does nothing.
- **Spin wind-up fixed:** hold Left on the run-in and the shoulders coil left, which loads a
  RIGHT spin (mirrored for left). The wind-up key held after the pop is ignored until released;
  Right in the air adds to the right spin. Spins build up over 0.35 s (shoulders lead, hips
  follow) and top out at ~1 turn/s (was ~1.4); in-air spin authority lowered (Easy 20 -> 11).
- **Pop is realistic:** 1.6-3.5 m/s instead of up to 8 m/s, so a full charge no longer turns a
  jump into a triple. Rails lowered to 0.55 m (pop-on height), tubes 0.5 m.
- **Flips start laid out**; keep pulling past ~3/4 of a turn and the body tucks (hands to shins,
  ~1.6x rotation rate), let go and it opens up again - the layout-then-tuck of the reference.
- **Skier model:** shaped torso (chest, shoulder blades, broad shoulders), a defined hood lying on
  the back with a lighter lining, small backpack, joint caps at shoulders/elbows/knees, pants
  stacked over the boots, park helmet (lower back, brim, ear pads, vents, chin strap), larger
  goggles, mitts. Deeper athletic stance.
- **Skis:** lifted onto the highest of tip / middle / tail on both edges (+1.5 cm) so they always
  read as on top of the snow, and chatter slightly at speed, when skidding and on landings.
- Tests: physics 80/80; gameplay includes a right 360 off the medium kicker done the player's way
  (hold Left, pop, Right in the air) - lands clean. Powder Rush / Widowmaker race bots fail (they
  relied on the tuck; races aren't reachable in the park game).

## Layout flip, pole push, helmet and goggles, wider skis

- **Layout backflip:** while flipping (not tucked), the knees bend so the shins and boots fold
  back behind the thighs and the skis run parallel to the body; arms go wide. Near the end of
  the rotation the legs swing back under for a flat landing. Pulling into more flips still tucks.
- **Pole push:** a real double-pole cycle (quick reach, plant ahead with baskets angled back,
  crunch and drive the hands down past the hips until the poles trail, recover) instead of a bob.
- **Helmet & goggles** after the player's reference photo: grey matte shell down over the ears,
  curved brim, flush black vents, black ear pads and chin strap; big cylindrical blue-tinted
  lens in a black frame, black strap round the helmet. (The curved goggle/brim bands were wound
  inward and invisible from outside - now double-sided.)
- **Skis** wider: ~126 mm tips, ~104 mm underfoot.
- Physics 80/80. Checked by screenshots: helmet front/side, push strokes, double backflip frames.

## Grabs in the game

- Seven grabs, built from real joint angles: hip flexion / abduction / rotation and a hinge knee,
  each clamped to human range, with hamstring coupling (a straight knee limits hip flexion) and
  the ski locked to the shin by the boot (15 deg forward lean). A small solver moves the grabbing
  leg and the spine within those limits so the hand actually holds the ski; the preview renderer
  (`--test=grabs`) prints the hand-to-ski gap (0 for every grab).
- Controls: Z = left hand (Mute; + Up Tip; + Down Japan), X = right hand (Safety; + Up Blunt;
  + Down Tail), Z + X = Truck Driver. Gamepad X / B. When a grab starts without a flip, the arrows
  pick the grab instead of flipping. The pose blends in and out; landing while still grabbing
  hard can crash ("Held the grab too long").
- Scoring: the grab is named on the trick ("Right 360 Mute") and scores 200 + 400/s held (up to
  2 s) times a difficulty factor (Safety 0.9 ... Japan / Blunt 1.3).
- Tests: physics 84/84, including Mute, Japan, Truck Driver and Tail grabs off the medium kicker:
  held, named, no unwanted flip, clean landing.

## Real pole push and a more human skier

- **Pole push** is driven by the physics stroke (`Skier.push_phase`): reach with nearly straight
  arms, plant, drive back past the hips, recover. Acceleration only comes while the poles are
  planted (peak 9 m/s^2, fading toward the 18 km/h push limit, was 14 km/h). Each tip is planted
  on the actual snow just behind the hand and stays fixed in the world while the skier slides
  past it; the hand stays on the grip. Test: 8 plants in 3 s, tip within 4 cm of the snow,
  0.1 cm slide; 17 km/h after 3 s from a standstill.
- **Body:** shaped thighs / calves / upper arms / forearms (non-round cross-sections with quad,
  calf and biceps shape under baggy fabric), gloves with thumbs and gauntlets, a neck gaiter
  over the chin, ski-boot buckles, power strap and tongue, front zip and chest-pocket zips,
  cargo pockets, procedural fabric weave normal maps on jacket / pants / gloves / gaiter. The
  chest band that looked like a toy stripe is gone.
- Physics 86/86.

## Mute copied from a reference photo; skeleton view; slow motion

- The game's skeleton was drawn onto the player's mute reference photo (joints placed by eye,
  `build/pose_fit/keypoints.py`). An automatic 3D fit from the single photo
  (`build/pose_fit/fit_pose.py`) proved too ambiguous (depth), so the pose was set by hand from
  what the photo shows and compared side by side from a similar camera: upright spine curving
  toward the grab (new three-segment spine with sideways curve, `SkierBody.spine_bases`), chest
  turned to the grab, grab hand down the side to the ski just ahead of the boot, free arm straight
  up, knees tucked high, skis crossed flat under the boots, whole body tilted off-axis. Mirrored
  to the game's left-hand mute (the photo is right-handed). It is now the in-game Mute.
- V toggles a skeleton view (bones + joints, clothes hidden); B toggles quarter-speed slow motion.
- Physics 89/89, including all seven grabs off the medium kicker (held, named, clean landing).

## Grab timing and the mute's crossing animation

- Grabs take time: the pose starts on the key press and eases in (smoothstep) over 0.55 s
  (the mute 0.75 s), and lets go over 0.35 s. A grab scores once the hand is on the ski.
- Grabs run in stages: knees come up with the skis still parallel, then the hips sweep the skis
  across into the X (joint angles interpolated, so the skis visibly swing), then the hand reaches
  the ski as the cross completes; spine curve, twist and the off-axis tilt build throughout.
- `--test=grab_anim` renders the live grab every 0.1 s. Physics 91/91, including the timing
  (mute 0.27 in at 0.25 s, fully in at 0.78 s, out 0.37 s after letting go) and the cross
  (skis 0 deg apart at 0.2 s, 18 at 0.4 s, 45 at 0.6 s).

## Skeleton feet; tail grab copied from photos

- Skeleton view shows feet: heel and toe joints on each boot (foot triangle). Legs gain an optional
  fifth joint, ankle boot flex (-5..15 deg on top of the boot's 15 deg lean).
- Tail grab rebuilt from three reference photos (skeleton + feet drawn on each,
  `build/pose_fit/tail_keypoints.py`): knees up in front, shins folded back (knee ~140 deg) so the
  skis hang nearly vertical tips-down with the tails up behind at chest height; right hand on the
  end of the right tail with the shoulder pulled back; left arm forward and up; torso upright.
  Compared side by side with the photos from a matching side camera. Eases in over 0.6 s.
- Physics 91/91 (tail grab off the medium kicker held, named, clean landing).
- Tail grab: the head turns to look at the ski being grabbed (over the right shoulder; neck limited
  to 80 deg turn, -50..35 deg pitch) and turns first, before the hand reaches; the grabbing shoulder
  blade slides back and down, the other forward; the twist comes mostly from the upper back
  (spine twist shared 15 / 55 / 100 % lower to upper) with a slight lean toward the grab.
- Tail grab, from a fourth photo: the whole body lays over ~45 deg off-axis (head to his left) so
  the skis run sideways along the body; thighs nearly straight down and shins folded right up
  (ankle flex 10 deg) so the tail reaches up behind the right shoulder; the hand grabs near the
  tail end; free arm overhead.
- Tail grab revised on feedback: no off-axis body tilt; instead the skis stand upright out to his
  right side (right ski ~0.34 m out, hips rotated in 40 deg with the knees at 140 deg, boots flexed
  10 deg - found by searching the joint-limited leg angles), and the upper back turns and leans
  toward them while he looks back at them.
- Arms no longer pass through the skis: the tail grab holds the edge nearest the shoulder
  (`auto_grip`), and for every grab, if an arm would intersect a ski (arm and skis treated as
  rounded bars), the elbow swings around the shoulder-hand line to the clearest side. The grab
  preview prints the arm-to-ski clearance: all seven grabs 5-8 cm clear.
- Tail grab arm straightened (was folded to 37 deg at the elbow with the hand on the shoulder):
  the right ski sits a little further back while staying out to his side (right leg 30 / -5 / 30 /
  120 deg, boot flex 5, found by a joint-limited search against the game's shoulder position), the
  solver may move the grip point along the ski (0.35-0.55 m behind the boot) and aims for a nearly
  straight arm ("reach"), with the legs and the lean toward the skis held fixed. Grabbing elbow
  now 145 deg, pointing out and back. New physics check: every grab's grabbing elbow > 110 deg
  (worst now 142) and arms clear of the skis. Physics 92/92.

## Outfit after the player's park-skier reference; zip fix

- Removed the "stick" between the legs: the jacket's front zip still ran down to the old hem
  (the hem was raised 9 cm when the torso was shortened), so its last 9 cm hung below the jacket.
  The zip now ends at the hem.
- New colours / look after the reference the player sent: loose cream jacket (zip and pocket zips
  in a darker cream), baggy mid-grey pants with darker grey patches (procedural patch texture +
  twill normal), dark grey cargo pockets, dark navy helmet and neck gaiter, black gloves, dark grey
  boots, dark pole shafts with brown baskets; the backpack is no longer worn. Shapes unchanged.
- Physics 92/92; checked in close-ups (front / side / back) and the browser chase view.
- Pants after the player's pants reference: plain warm taupe, very wide straight legs (no taper,
  ~30 cm across each leg), widening at the hem where they pool over the boots; the patch texture is
  no longer used. Headwear: a navy knit beanie with a folded cuff replaces the helmet (helmet parts
  built but hidden), goggles scaled to sit on the face with the strap round the beanie.
- Pants smoothed after a second pants reference: each leg is one wide tube that blouses out above
  the boot and is gathered in at the ankle (soft folds above the cuff); the separate ankle "stack"
  rings and the cargo-pocket boxes are no longer shown, and the knee fill is smaller than the leg
  so the knees don't bulge.
- Jacket: boxier and wider (hem ~47 cm across) so it hangs over the baggy pants instead of the
  pants poking out from under its edge, with a drop-tail back hem 6 cm lower than the front
  (`shell` rings take an optional back-drop value). Loose sleeves gathered at the wrist; shoulder
  and elbow fills no bigger than the sleeve. Ripstop fabric: faint darker grid ~2.5 cm, mottling,
  and soft large wrinkles in the normal map (generated in code).

## Grab keys: Q / E with W / S (arrows only flip and spin)

- The arrows used to both flip and pick the grab variation, so e.g. a backflip (hold Down) turned
  a Tip grab into a Japan. Now: Q = left hand (Mute; + W Tip; + S Japan), E = right hand (Safety;
  + W Blunt; + S Tail), Q + E = Truck Driver. W / S reuse the push / brake actions (they do nothing
  in the air), can be pressed any time during the grab and stick. Arrows never pick grabs.
- Q / E no longer spin on the keyboard (the arrows do); gamepad spins stay on LB / RB.
- S doesn't brake in the air, and if it picked a grab it won't hockey-stop you on landing until
  it is pressed again.
- Tests: a grab leaves the flip unchanged; Backflip Tip off the large kicker lands clean; holding S
  through a landing after a Japan keeps full speed. Physics 95/95.

## Arrow tricks (no jump key), stronger push, smooth poles

- Space removed. Tricks in the style the player asked for: hold an arrow to SET (crouch and
  coil; charge builds), press the OPPOSITE arrow to POP into that trick - set Up then Down =
  backflip, Down then Up = front flip, Right then Left = left spin, Left then Right = right spin;
  two set arrows give a flip + spin. Letting go of the set arrow without the opposite = a straight
  ollie (e.g. onto rails). The pop counts for 0.12 s after rolling off a lip; set arrows still held
  after the pop are ignored until released, and rolling off a lip while set but not popped doesn't
  rotate. The pop arrow keeps rotating in the air (hold Down for more backflips). Gamepad keeps A
  to jump. Park tip signs, hints, page and README updated.
- Push: stronger stroke (peak 13 m/s^2, was 9) and works up to 23 km/h (was 18): 22 km/h after 3 s
  from a standstill (was 17).
- Poles: they plant where the swinging tip actually reaches the snow (or along their own line),
  the arm spring continues from the planted hand, and unplanted poles ease toward their target -
  max pole turn per frame 3.4 deg (was a 54 deg jump at the plant).
- Physics 100/100 incl. arrow ollie, arrow backflip (L kicker), arrow left 360 (M kicker), arrow
  rail ollie, Backflip Tip with arrows + Q/W.
- Push fix: with the stronger push the skier slid past a planted pole faster than arm + pole could
  stretch, so the planted-pole constraint dragged the hand beyond arm's reach - invisible on the
  skeleton (bones stretch) but the rigid sleeve and glove came apart. The planted hand now
  satisfies both arm reach and pole length; a pole that runs out of reach (or is left behind by a
  respawn) comes out of the snow for the rest of the stroke; the reaching hands are lower and the
  pole reaches straight down in the upright body frame so the tip meets the snow on its own.
  New check: hand within arm's reach all through the push (0.000 m over), pole turn <= 4.7 deg
  per frame. Physics 101/101.
- Japan rebuilt after the player's Japan photo (used as inspiration, no skeleton overlay): torso
  nearly upright (chest 9 deg forward, was 47), left knee up with the left ski pulled tail-up
  behind at ~35 deg while the right ski stays flat (an X from the side), left hand on the left ski
  behind the boot, chest turned toward it, right arm punching forward. A search over the joint-
  limited legs showed an opposite-hand grab can't reach a ski there with the body upright, so the
  Japan is now a same-side grab (still Q + S). Legs are fixed; the solver only moves the grip and
  upper body.
