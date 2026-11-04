# Skiing overhaul

The original user brief is preserved in UPGRADE_BRIEF.md. The original overhaul was published to GitHub Pages. The park follow-up below supersedes its open-world entry flow.

## Implemented

- **Contact and movement:** three longitudinal probes per ski; independent support and foot alignment; bounded damped leg suspension; footprint filtering of chatter; partial-contact grip; supported ski holds the body at ledges; bounded collision substeps for fast movement. Existing slope gravity, edge carving, skidding, braking, pop loading, difficulty levels and impact/rotation-based landings remain.
- **Pole pushing:** anticipation, plant, drive, recovery; thrust only during drive; assistance fades to zero at the speed limit; uphill attenuation, contact requirements, brake/air/crash cancellation, cooldown and anti-spam behavior. Arms/body follow stroke phase, with reachable planted pole-tip targets. The speed stance is automatic. Internal `tuck` binding is retained to preserve saved controls and walking; player labels now say Pole push.
- **Skier:** real hierarchical Skeleton3D with weighted mesh surfaces, IK-driven joints and existing ragdoll support; black default outfit, roomier folded sleeves/pants, fabric detail, jacket zipper/pockets, dark boot hardware, and differentiated material roughness. Existing saved gear choices are respected. This is an original procedural model, not an imported licensed character or full cloth simulation.
- **Trick expression:** shoulder lag/counterrotation, asymmetric arms, extended layout pose, slight back arch, clearance/closing-speed landing preparation, and impact compression. Physics still determines rotation and trajectory; grabs retain compact-body rotation effects.
- **Mountain:** reduce short-wavelength chatter on faster snow faces while protecting original features and kickers; smooth three progression approaches/recoveries; reshape Expert landing into a matching slope; clear landing corridors; rock flanks and route signs. Scout Drop, Freeride Drop and Expert Drop are accessible drop zones. Existing route IDs and save schema remain. Terrain collision, packed GPU height data, normals, light bake and map were rebuilt together.
- **Visuals/effects:** snow roughness variation, wind ripples, stable sparse sparkle, restrained grading/glow; close tree branch fans with existing LOD/instancing; support/load-weighted individual ski spray; reduced obscuring powder; contact-aware tracks and quality-dependent track caps. Existing pooled landing bursts, weather, shadows and scalable settings remain.

## Validation and limits

See UPGRADE_VALIDATION.md for final command outcomes and rendering measurements. Tested software rendering is not evidence of 60 FPS on gaming hardware. Human playtesting is still needed to judge feel and artistic polish. Existing race medal estimates and the Widowmaker race's playability were not re-certified by this pass.

Run from the repository root:

    godot --path project
    godot --headless --path project --import
    godot --headless --path project -- --test=physics
    godot --headless --path project res://scenes/validate.tscn
    godot --path project -- --test=upgrade --out=/tmp/ski-showcase
    godot --path project -- --test=smoke --seconds=20 --out=/tmp/ski-performance

Use a separate XDG_DATA_HOME for test runs that change weather/settings. The cloud's local software-render helper is /workspace/devtools/render-ski.sh; it uses downloaded, package-verified Xvfb and system Mesa llvmpipe. It must run alone because its display number is fixed. It is an environment helper, not a game runtime dependency.

## Tuning

`project/scripts/player/skier.gd` exports push_max_speed (7 m/s), push_duration (1.05 s), push_acceleration (8 m/s²), suspension_travel (0.22 m), suspension_stiffness (80), suspension_damping (16), edge_grip (1), air_control (1).
`project/scripts/fx/ski_fx.gd` exports spray_strength and track_chunk_limit. Quality settings impose an additional track cap; the existing tree LODs, culling and fixed 120 Hz physics remain.

## Terrain reproducibility

`python3 build/polish_mountain.py project` upgrades an original generated world once and does nothing when the version marker is present. Full generation calls the same polish and object-dressing routines before baking. Do not apply terrain stamps repeatedly or regenerate the complete original landscape just to run the game. The native generator helper is compiled with:

    mkdir -p build/.cache
    gcc -O3 -march=x86-64-v2 -shared -fPIC -o build/.cache/libterrain.so build/terrain_kernels.c -lm

Each cloud task is isolated; use the existing checkout. Progress cannot resume automatically after a usage limit without a new user message.

## Web publication follow-up

User authorized publishing updates. Verified official Godot 4.6.3 export-template SHA512, installed Web templates, exported Web successfully, and packaged `dist/web_artifact/` plus `dist/SUMMIT-web.zip` (51 MiB compressed). ZIP integrity test passes. Chromium fetched all engine/game chunks from a local HTTP server; full interactive browser validation is not established by those downloads.

Publishing access recovered: api.github.com is now allowed and repository API confirms push/admin access. Existing GitHub Pages source is gh-pages (/). Published the updated web package to that branch in commit baf72eb1d597e486f289c566fd325b204af5c551; deployment run 41792317421. Play URL: https://rclogos44-svg.github.io/code-skiing-game/ . That initial release published web assets only; the park follow-up subsequently committed and pushed the complete source overhaul to main. Old hashed pack assets were retained to avoid breaking cached pages.


## Park follow-up (November 4)

- Reviewed the uploaded Jibbers frame sequences for takeoff extension, folded/asymmetric grabs, upright camera framing and landing follow-through. The result is an original procedural interpretation, not copied animation assets or an exact physics reconstruction.
- Start/Continue/Practice enter Terrain Park above the existing three increasing kickers. Three rows of three jibs provide wide boxes, narrow rails, a tube and a continuous flat-down rail. Clear bypass space separates lanes. Other mountain content is retained in the data; normal play is bounded to the park.
- R returns to the entrance; B resets uphill of the nearest jump or jib. Settings exposes the new binding. Menus show the available park practice/challenge instead of sending users to unavailable routes.
- Skis and bindings retain independent foot transforms outside the body Skin. Flex deformation remains in local mesh coordinates, with bounded bending and two-sided surfaces. Inverted/sideways rendering confirms visible, attached skis.
- Boxes preserve lateral entry position, lateral momentum and physical edge exits. Their wide deck supports a centered skier without the narrow-rail balance-failure rule. Flat-down joins preserve accumulated trick time and balance.
- New browser defaults use Low graphics and 85% render scale; existing saved settings remain. Compatibility uses supported bilinear scaling. Crowds are disabled in park play. Physics stays at 120 Hz.
- Compatibility lighting is tuned separately because the previous tone mapping clipped the snow into a uniform grey surface. Native Forward+ keeps its tone mapping.

## Park release

Source implementation: `4b3212e` on `main` (including overhaul commit `a6d07b6`). Web release: `d442534` on `gh-pages`, pack `acb10640e2`, GitHub Pages deployment run `41887037555`. Prior hashed packs remain available for cached pages.

Play: https://rclogos44-svg.github.io/code-skiing-game/
