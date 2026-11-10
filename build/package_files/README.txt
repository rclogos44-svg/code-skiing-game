SUMMIT  -  Park skiing
======================

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
W            Pole push - only when slow (no tuck)
S            Hockey stop (tap: check speed, hold: stop; + A/D picks the side)
A / D        Carve left / right. On a rail or box: keep your balance
Left Shift   Aggressive edge carving (tighter turns, scrubs speed)
Arrows       Tricks, no jump key: hold an arrow to SET (crouch / coil), then press
             the OPPOSITE arrow to POP and do the trick:
               hold Up, press Down     = backflip
               hold Down, press Up     = front flip
               hold Right, press Left  = left spin
               hold Left, press Right  = right spin
             (hold two arrows to set a flip and a spin together). Let go of the
             set arrow without pressing the opposite one = a straight pop (ollie),
             e.g. onto a rail. Press at the lip; a moment after it still counts.
             In the air the pop arrow keeps rotating (keep holding Down for more
             backflips - the body tucks after the first one).
Q / E        Grabs (in the air). Q = Mute; Q + W = Tip; Q + S = Japan.
             E = Safety; E + W = Blunt; E + S = Tail. Q + E = Truck
             Driver. W / S can be pressed any time during the grab and stick. The
             arrows only flip and spin, so e.g. hold Up, press Down at the lip and
             Q + W in the air for a Backflip Tip. Hold longer for more points; let go
             before you land.
Difficulty   Settings > Controls: Easy (default: lots of air control,
             forgiving landings and rails), Normal, Realistic (rotation only
             from your takeoff, edges catch, rails need balancing)
Mouse        Look around      Scroll wheel   Zoom camera
C            Switch camera (standard / close chase)
X            Switch stance: a 180 on the snow into riding switch (and back out).
             Riding switch you look over a shoulder; landing a 180 keeps you switch.
Left / Right On a rail or box: a quick tap spins you 180 on it.
V            Skeleton view: hide the clothes and show the bones and joints
B            Slow motion on / off (quarter speed)
F            First-person view
R            Respawn on the snow
Tab          Back to the top of the park
P / Esc      Pause & settings (Choose Park to switch parks)
A gamepad also works: left stick steer/tuck/brake, A jump, LB/RB spin,
Y respawn, right stick camera, Start pause, Back: top of the park.

HOW TO PLAY
-----------
- Pick a park from the main menu: Main Park, Big Air Park or Jib Garden.
  Each has three lines, marked by signs at the top:
    * PROGRESSION (left): small jumps with tips, ride-on boxes.
    * JUMP LINE (middle): small, medium and large tabletops. The sign before
      each jump shows the speed to hit it with.
    * JIB LINE (right): boxes, rails and tubes.
- Orange lines mark each kicker's lip (take-off) and knuckle (start of the
  landing). Aim to land just past the knuckle, on the steep landing.
- Tricks: spins (180/360/540...), backflips and front flips, seven grabs,
  and rail / box slides. Land tricks within a few seconds of each other to build a combo
  multiplier; a combo is banked after ~3.5 s on the snow and lost if you
  crash. Land straight (or fully switch) - sideways landings crash.
- Crash? Press R to get back up, or Tab to go back to the top.

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
