# Overhaul validation

## Runtime and scope

Godot 4.6.3 stable, Debian 13 cloud environment, Intel Xeon Platinum 8573C, five exposed CPU cores, approximately 33 GiB RAM. No physical GPU is available. Rendered tests use Mesa 25.0.7 llvmpipe through Xvfb, with a separate XDG_DATA_HOME so test weather/settings do not replace player preferences. Audio uses the Dummy driver.

## Physics and resource checks

Final result: **89 physics checks passed, 0 failed**. Script/resource/layout validation passed (31 scripts, 15 drop zones).

The previous project baseline had 57 passing physics checks. The expanded suite exercises timed pushes, speed and contact limits, cooldown/spamming, uphill attenuation, 60/120/240 Hz consistency, partial ski support, chatter, suspension bounds, fast obstacle collision, combined aerial rotation, actual slope/flat landings, and all retained skiing/walking/lift/rail checks.

Tail-loading comparison now uses a deterministic planar ramp with the same relative-height assertion. A moving takeoff on the old mountain no longer samples equivalent terrain after the contact/terrain changes. Normal mountain jump tests remain.

All three curated routes are simulated at 12 m/s from 35 m above their features. Scout, Freeride and Expert each leave the snow and land without a crash in that test. The Expert landing was reshaped after its initial measured normal impact exceeded the crash threshold; the revised route's measured landing impact is about 14.2 m/s instead of 24.3 m/s. This validates the tested line and speed, not every possible approach.

The final validator checks script compilation, resources, inputs, terrain data, route/spawn consistency and heights. An intermediate Widowmaker spawn slope regression was caught and fixed by preserving relief around existing spawns.

## Rendered checks

The `upgrade` mode checks finite skeletal transforms and captures stance, pole pushing, layout, spin and landing poses, plus the three new drop approaches. OpenGL compatibility rendering completed all five pose checks and eight screenshots without script/shader errors. Captures are under `previews/final/` (ignored generated files).

A Vulkan 1.4 Forward+ run selected the llvmpipe device and built the world without reported script/shader errors, but did not complete a pose check in the 240-second budget. Main-renderer visual readiness therefore remains unverified on this machine; the completed rendering checks above use OpenGL compatibility.

## Performance measurements

Wall-clock frame times are measured after 20 warm-up frames, in 20-second gameplay samples. 960×540 viewport, Low preset, render scale 1, no AA, Low shadows, Low detail/view distance, VSync disabled. These are software-render measurements, not gaming-GPU benchmarks.

| Sample | Frames | Mean frame time | Mean FPS | P95 | Worst |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before art/terrain changes, light snow | 67 | 303.2 ms | 3.30 | 366.6 ms | 858.5 ms |
| Updated gameplay, light snow | 26 | 771.5 ms | 1.30 | 1498.6 ms | 1832.6 ms |
| Updated gameplay, snowstorm | 51 | 396.4 ms | 2.52 | 580.3 ms | 661.5 ms |

The updated light-snow sample is slower. Runs vary substantially on this shared CPU environment; the snowstorm sample being faster must not be interpreted as a weather optimization. No 60 FPS claim is supported. A dedicated GPU benchmark and profiling pass are still required to establish the intended hardware target. The change retains instancing/LOD/culling, fixed physics, bounded collision substeps, capped tracks and pooled effects, but does not guarantee a performance improvement.

## Reproduction

From the repository root:

    godot --headless --path project --import
    godot --headless --path project res://scenes/validate.tscn
    godot --headless --path project -- --test=physics
    godot --path project -- --test=upgrade --out=/tmp/ski-poses
    godot --path project -- --test=smoke --seconds=20 --out=/tmp/ski-profile

For a snowstorm stress run, add `--weather=storm` after `--`. Use an isolated user-data directory because that option changes weather settings. The cloud-local helper `/workspace/devtools/render-ski.sh` supplies the software display; run only one instance at a time.

## Remaining limitations

Human gameplay and art review are still needed. The skier is a procedural, rigid-weighted skeletal model with spring-driven posing, not simulated fabric or a fully physical articulated body. Existing ghost/save formats and customized gear bindings are retained. Races and medal estimates were not comprehensively re-certified. A Web release has been exported and packaged; see the park follow-up results below.


## Park follow-up verification

- Physics suite: **96 checks, 0 failures** (`--test=physics`). Includes actual box/rail approaches, off-center box contact, edge release, flat-down continuity, park spawn/boundary and nearest-jump retry.
- Resource/script validator: **31 scripts, 0 failures**.
- Rendered pose suite: **21 checks, 0 failures**, seven poses including inverted and sideways. Both skis remain attached and finite with no skin transform.
- Park entrance and three-row layout captured with OpenGL compatibility (`--test=park`). This is visual inspection, not a framerate benchmark.
- Shutdown still reports CanvasItem/ObjectDB leaks in the test harness. No runtime script errors occurred in passing suites.
- Actual weak-laptop framerate remains unmeasured. New Low defaults and disabled crowds reduce work, but no 30/60 FPS guarantee is made.

- Browser smoke test: Chromium/WebGL2 loaded the world and rendered the menu and park; Park Practice, R/B input and pause responded. Initial pointer-lock request was rejected because it followed a menu fade; browser entry now waits for a direct click on the slope. Remote font requests were blocked in the cloud; local game rendering continued. Browser hardware acceleration here is SwiftShader, so this is a functional check, not a laptop performance result.
