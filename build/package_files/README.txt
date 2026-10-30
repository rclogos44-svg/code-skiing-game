SUMMIT  -  Open-world mountain skiing
=====================================

Thanks for playing! SUMMIT is a standalone game: nothing else needs to be
installed. You only need an up-to-date graphics driver.

HOW TO START
------------
Windows : unzip the folder, open "SUMMIT" and double-click SUMMIT.exe.
          Keep SUMMIT.exe and SUMMIT.pck in the same folder.
          The game is not code-signed, so Windows SmartScreen may say
          "Windows protected your PC". Click "More info" -> "Run anyway".
macOS   : unzip, then right-click SUMMIT.app -> Open -> Open.
          (The app is not notarized by Apple, so a normal double-click is
          blocked the first time. If macOS says the app "is damaged", run
          this once in Terminal from the unzipped folder:
              xattr -cr SUMMIT.app
          then right-click -> Open.)
Linux   : unzip, then run ./SUMMIT.x86_64 (keep SUMMIT.pck next to it).

The first launch opens borderless fullscreen. Change resolution, window
mode, graphics quality, controls and audio in Settings. Settings and
progress are saved automatically.

SYSTEM REQUIREMENTS
-------------------
A 64-bit PC or Mac with a GPU that supports Vulkan 1.0 (most graphics cards
from 2016 onwards), or Direct3D 12 on Windows. Older GPUs fall back to
OpenGL 3.3 automatically with simpler lighting. Target: 1080p at ~60 FPS on
a reasonably capable gaming PC with the "High" preset; use "Medium" or "Low"
on laptops or integrated graphics.

CONTROLS (keyboard & mouse, all rebindable in Settings)
--------
W            Tuck (less air resistance) / pole-push on flat ground
S            Hockey stop (tap: check speed, hold: stop; + A/D picks the side)
A / D        Carve left / right
Left Shift   Aggressive edge carving (tighter turns, scrubs speed)
Space        Hold to crouch, release to jump (longer hold = bigger ollie)
Q / E        Spin left / right in the air
Z / X        Grab left / right ski in the air
Mouse        Look around      Scroll wheel   Zoom camera
C            Switch camera (standard / close chase)
F            First-person view
R            Respawn (in a race: back to the last gate)
T            Take skis off / put them on. On foot: WASD walk (camera-relative),
             Shift jog, Space hop - hike up to lines the lifts don't reach
G            Ride a chairlift: stand on the blue LOAD mat, the next chair picks
             you up; hold G while riding to skip to the top
Tab          Mountain map (click a drop zone to travel there, click anywhere
             else to set a waypoint - shown on the minimap and as a light beam)
P / Esc      Pause & settings
A gamepad also works: left stick steer/tuck/brake, A jump, LB/RB spin,
X/B grabs, Y respawn, right stick camera, Start pause, Back map,
D-pad up ride lift, D-pad down skis off/on.

HOW TO PLAY
-----------
- Start Game begins a career at the ski resort. Ride the lifts, explore,
  and unlock the rest of the range:
    * Look at a distant peak for a moment to SPOT its drop zone (a ring
      fills in the middle of the screen), or ski close to it.
    * Reach a VIEWPOINT (blue flag) to reveal all drop zones in its region.
- Free Ride: every drop zone open, no objectives.
- Challenges: races with bronze/silver/gold medals, freestyle score and
  trick challenges, and extreme no-fall descents.
- Tricks are scored from what you actually do in the air: measured spin
  (180/360/540/720...), grab hold time, airtime and landing quality.
  Land tricks within a few seconds of each other to build a combo
  multiplier; a combo is banked after ~3.5 s on the snow and lost if you
  crash. Land straight (or fully switch) - sideways landings crash.
- Physics tips: steep slopes accelerate you, deep powder slows you, ice has
  little grip, tucking is fastest, tight carving scrubs speed, and you can
  launch off any cliff or lip - but very hard landings end in a crash.

SAVE FILES
----------
Windows: %APPDATA%\Godot\app_userdata\SUMMIT
macOS  : ~/Library/Application Support/Godot/app_userdata/SUMMIT
Linux  : ~/.local/share/godot/app_userdata/SUMMIT
Delete that folder to reset settings and progress.

TROUBLESHOOTING
---------------
- Black screen or crash at start: update your graphics driver. On Windows
  you can also force Direct3D 12 or OpenGL from a command prompt:
      SUMMIT.exe --rendering-driver d3d12
      SUMMIT.exe --rendering-method gl_compatibility
- Low frame rate: Settings -> Graphics -> Quality preset "Medium" or "Low",
  or lower the Render scale.

CREDITS & LICENSES
------------------
All terrain, textures, 3D models, animation and sounds in SUMMIT were
generated procedurally for this game (see LICENSES/SUMMIT_CONTENT.txt).
Built with Godot Engine (MIT license) - see LICENSES/.
