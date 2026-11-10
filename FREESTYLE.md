# Freestyle: tricks, grabs and Ridgeline Park

This is how the arrow-key trick system, off-axis rotations, grabs and the new Ridgeline Park
work, why they're built that way (with the research), and where the tuning lives.

## Research and what it decided

Web pages could not be opened from this build environment (the network blocks those sites), and
no video could be watched. The research below comes from search-engine summaries of the linked
pages, plus the grab photos studied earlier for the grab poses (see DEVELOPMENT_LOG.md, "Grab
timing" / "tail grab copied from photos"). Motion details that no source pins down are marked
*(assumption)*.

| Source (via search summaries) | What it informed |
|---|---|
| [Ski.com: X Games freeskiing dictionary](https://ski.com/blog/x-games-dictionary-freeskiing-tricks-explained), [NBC Olympics freestyle glossary](https://www.nbcolympics.com/news/freestyle-skiing-101-glossary), [Cork Bible dictionary](https://www.digezz.ch/projekte/cork-bible/dictionary.html) | Definitions: cork = off-axis spin, the feet never go above the head; rodeo = off-axis **backflip** with a spin, feet do go over the head; misty = the forward counterpart of the rodeo; bio = a cork "corked forward", not fully inverted; D-spin / flatspin are more inverted relatives |
| [Freeskier: Michael Olenick rodeo 540](https://www.freeskier.com/trick-tip-tuesday-michael-olenick-rodeo-540), [Freeskier: TJ Schiller switch rodeo 540](https://www.freeskier.com/trick-tip-tuesday-tj-schiller-switch-rodeo-540), [Whitelines: backside rodeo 540](https://whitelines.com/snowboarding-advice/trick-tips/kicker/how-to-backside-rodeo-540-melon.html) | Rodeo takeoff: pop and roll back over the shoulder, head thrown over the trailing shoulder looking back; blind for the first ~270 deg of a 540, then spot the landing; hold the grab until the landing is close, let go and look downhill to land |
| [US Sports Camps: 540s and 720s](https://www.ussportscamps.com/tips/how-to-spin-540s-and-720s-on-skis), [Ski Mag: D-spin 720](https://www.skimag.com/uncategorized/how-to-d-spin-720), [Newschoolers cork 720 help](https://newschoolers.com/forum/thread/812913/Cork-720-help), [J-STAGE study: cork 720 vs 720 takeoff](https://www.jstage.jst.go.jp/article/jskisciences/15/1/15_93/_article/-char/ja) | Cork takeoff: set the spin hard and drop the **lead** shoulder a little (on skis a small dip is enough); tuck, the skis cross naturally in a tuck; spot the landing during the first turn then keep head and chest still while the hips finish; the study found cork takeoffs have more back tilt and earlier shoulder / hip rotation than flat 720s |
| [Ubisoft: Riders Republic Q&A](https://www.ubisoft.com/en-us/game/riders-republic/news-updates/2HFvoOtBvWRtrlXOF8ZXjo/answering-your-riders-republic-questions), [ccstartup RR guide](https://ccstartup.com/blog/?p=97064), [GameSkinny RR controls](https://gameskinny.com/?p=70609) | Riders Republic: "flip-to-spin" (a flip that turns into a spin) and "spin-to-flip" (fully inverted) rotation styles; flips and spins from a stick flick, rodeos from a quarter-circle; landings possible every 180 deg; an auto-landing assist without the score bonus. Decision: prepare with one direction, initiate with another; flip-led vs spin-led families; a bounded landing help that can be off (Realistic) |
| [Backcountry Access: freestyle grabs](https://backcountryaccess.com/blog/p/backcountry-ski-tricks-101-stylish-freestyle-grabs), skipass / newschoolers grab threads | Grab contact points: safety = same-side hand under the boot; mute = opposite hand, crossed skis, near the binding (sources differ on the exact spot); Japan = opposite hand behind the knee to the other ski's inside edge at the back of the binding; tail = the last few inches of the ski, crossed skis |

### Terminology used in the game
Names vary between sources. SUMMIT uses:
- **Cork** / **Bio**: spin-led off-axis rotations, back-tilted (cork) or forward-tilted (bio). The
  number counts the **spin**: Cork 720 = two full spins with one off-axis roll. A cork must tip at
  least 80 deg from upright (a bio 60 deg), never fully inverted.
- **Rodeo** / **Misty**: flip-led off-axis rotations, backward (rodeo) or forward (misty), feet
  over head (at least 120 deg from upright). The number counts the **flip plus the spin**:
  Rodeo 540 = an off-axis backflip with a half-turn of spin (lands switch).
- Directions are the way the spin turns (Right = clockwise seen from above).
- Names come from what the body actually did in the air (flip completed past 320 deg, how far
  he really tipped, the measured spin), never just from the keys pressed. An off-axis that didn't
  tip far enough is called "Off-axis 540" etc.

## Controls

Arrows, all four. **Prepare** = hold an arrow on the snow: he loads into it (crouch; Up/Down lean,
Left/Right coil the shoulders), the charge ring fills in 0.55 s and stays full however long you
hold it. **Initiate** = press a second arrow while preparing. The prepared arrow coils you the
*opposite* way; the second one snaps you in *its* direction.

| Sequence | Result |
|---|---|
| Up, then Down | Backflip |
| Down, then Up | Front flip (always tucked) |
| Left, then Right | Right spin (coil left, release right) |
| Right, then Left | Left spin |
| Up, then Right / Left | Rodeo right / left (backward, flip-led, feet over head) |
| Down, then Right / Left | Misty right / left (forward, flip-led) |
| Left, then Down | Cork right (spin-led, lead shoulder drops back) |
| Right, then Down | Cork left |
| Left, then Up | Bio right (spin-led, forward) |
| Right, then Up | Bio left |
| Hold an arrow, let go of it alone | Straight pop (ollie); a tap under 0.1 s does nothing |
| Keep the second arrow held in the air (plain flips / spins) | Rotates faster that way (within a limit) |
| Off-axis, in the air: press Left / Right again | One more half-turn the trick's way (if there's time), the other arrow one fewer; arrows still held from the takeoff do nothing |
| Opposite arrow in the air | Slows the rotation (never reverses it) |
| Up / Down in the air during a flip or off-axis | Flip faster / slower in that direction (limited) |
| Q / E (+ W / S) in the air | Grabs: Mute / Safety, Tip / Japan, Blunt / Tail, both = Truck Driver |
| X | Switch stance (a 180 on the snow) |
| F3 | Developer view (input state, charge, trick, grab phase, rotation, landing prediction) |
| B | Slow motion (scales physics, animation and input timing together) |

Rules for the edge cases:
- **Same arrow again**: while held it can't be pressed again; after letting go it starts a new
  preparation (the ollie from letting go already happened).
- **Two arrows pressed on the same frame**: Up/Down is taken as the prepared one; the other only
  initiates once it's pressed again (a second arrow counts only after 0.06 s of preparation).
- **No preparation**: the first arrow always prepares; nothing rotates from a single key.
- **Charge past the maximum**: capped at 1; holding longer changes nothing.
- **Near a kicker** (a lip within ~0.7 s ahead): the initiated trick waits ("at the lip") and
  starts at the takeoff with a small pop, for up to 0.9 s; with no lip it pops right away.
- **Initiating late**: within 0.3 s of leaving a lip, holding one arrow and pressing another still
  starts the trick at 65 % strength. After that the arrows only adjust rotation.
- **On a rail or box**: a quick tap of Left / Right (under 0.3 s) is a rail spin; a full
  prepare + second arrow pops off the rail into the trick.
- **Landing / crash**: 0.25 s after touchdown new presses are ignored; a crash clears everything.
- **Leaving a jump while prepared but not initiated**: a straight air (the held arrow is ignored
  until let go).
- **Low air**: an off-axis off a jump with less than 1.2 s of predicted air becomes a flat spin
  that way ("TOO LOW · SPIN"); flips from flat ground stay small because the pop is small.
- **Losing focus** (alt-tab, clicking outside the browser game): every held key is released and a
  half-prepared trick is dropped without popping. The web page never scrolls with the arrows.
- Remapping: Settings > Controls (the arrow actions are lean_forward / lean_back / lean_left /
  lean_right).

## Off-axis families (Skier.OFFAXIS)

Each is a **spin** about the takeoff vertical (kept in `heading`, so the chase camera, switch
landings and naming work as for spins; the camera follows the travel direction, not the body)
plus **one off-axis flip** about a diagonal axis in the body frame that turns with the spin. A
full off-axis flip plus any whole number of half-turns of spin always ends upright, so 540s land
as well as 720s. The body rotation is a single angle about one axis (a quaternion / Basis built
from axis-angle each frame) on top of the yaw: no Euler accumulation, no gimbal lock.

| Family | Axis (body frame) | Timing | Body | Lands |
|---|---|---|---|---|
| Cork | backflip axis rolled 60 deg toward the lead shoulder, raised 42 deg toward the spin axis | spin at once, off-axis drops in over 0.25 s | lead shoulder dips at the pop, tight tuck (0.85) | opens up after 270-330 deg, ~85 deg max tip |
| Bio | front-flip axis rolled 55 deg, raised 36 deg | spin-led | tuck 0.8 | ~100 deg max tip |
| Rodeo | backflip axis rolled 28 deg, nearly flat | flip at once, spin grows over 0.35 s | arches back, head thrown over the trailing shoulder | feet over head (~160 deg) |
| Misty | front-flip axis rolled 30 deg, nearly flat | flip-led | curls forward over the chest, tuck 0.9 | feet over head |

Timing is fitted to the jump, so they never whip round: at the takeoff the predicted air time sets
the off-axis flip rate so it comes round about 0.2 s before the snow (2.2-7 rad/s, the slow end on
big jumps), and the spin is a whole number of half-turns spread over the flight. Charge picks how
many half-turns (each family has an aim speed, `spin_rate`, at no / full charge: cork and bio
3.4-5 rad/s, rodeo and misty 1.4-2.2), not a faster spin. Off Ridgeline's XL that is a Cork 540 and
a Rodeo 540; pressing the spin arrow again in the air makes it a 720. Ramp times, tucks and the top
spin speed are in OFFAXIS.
Grabs work through all of them: the off-axis rotation is applied to the whole body around its
centre of mass, and the grab is a pose in the body's own frame whose hand target is recomputed
from the ski every frame.

Landing: the error between the body's up and the finished flip (from the off-axis angle and axis)
replaces the plain flip error in the landing check; within tolerance he lands (a sketchy landing
below the crash limit), past it he crashes ("landed on your back / head"). Help, only on Easy /
Normal: after 300 deg he opens up just enough to finish the flip at the predicted touchdown, and
the spin is steered onto its half-turn at touchdown (on Realistic it keeps its takeoff speed).

## Grabs

Phases (shown in the F3 view): **reach** (the knees come up first, the skis cross, the hand
arrives last: SkierBody stages `_gw_legs`, `_gw_cross`, `_gw_hand`, `_gw_body`), **contact**,
**hold** (over the first half-second the grab is pulled in a little more: twist and spine curve,
`_tweak`), **release** (the hand lets go first, then the legs, back toward a landing-ready
stance), **landing prep**. Letting go before contact blends out from wherever the reach got to.
The hand target is the grip point on the ski, recomputed from the ski's transform in the same
frame, so the hand can't slide or lag. The arm uses two-bone IK with the elbow pole swung to the
side that clears the skis, and limbs are never stretched (out-of-reach targets bend the spine).
The grabbing hand's pole swings out and back; the free arm's pole hangs back and down. On Easy /
Normal a grab lets go by itself 0.3 s before the snow (from the landing probe, i.e. the real
terrain), Skier.GRAB_AUTO_RELEASE; on Realistic you must let go yourself.

## Ridgeline Park

Choose it from the main menu, or from the pause menu's Choose Park, which also lists its quick
drops: Progression, Flow line, Big line, Jib lane, Step-up. Tab takes you back to the start of
whichever you picked. It is a fifth park; the other four parks and every natural feature on the
mountain are unchanged (build/parks.py applies it after the features and on clear ground).

- **Progression** (left): low rollers, three forgiving small tables, wide boxes side by side
  with regular boxes, space beside every feature to skip it.
- **Flow**: rollers in a row, a banked wall on the right then one on the left, side hits that
  kick you back into the lane, a hip that transfers toward the big line, a step-up, more rollers.
- **Big line** (center-right): M, L and two XL tables sized for the speed you carry from the one
  before (measured riding it, build/parks.py), 1.3-2 s of air for off-axis tricks, then a hip that
  transfers back left and a step-down.
- **Jib lane** (right): a wide box beside a flat-down rail, a down rail, a kinked rail, a flat-down
  box, a rainbow, an S-rail, a gap-to-rail, a tabletop box and a tube.
- Snow shapes are exact profiles added to the slope in the game (TerrainData.shape_offset), so
  physics and visuals agree: rollers (cosine bumps), banks (curved wall + narrow top + back slope,
  growing in and out over 7 m), step-ups (takeoff, gap, face, raised deck, rollout).
- The step-up (flow line, quick drop "Step-up"): a 1.5 m lip, a short gap and a face up to a deck about 0.7 m above the lip; ridden from its drop he lands about 4 m onto the 7 m deck.
- The park is regraded at 10 deg (the hillside is 13 deg): even at 10 deg a straight-running rider
  carries 12-16 m/s, which is why the progression tables have long decks.

## Tuning: where things live

- Trick input: `Skier` constants PREP_MIN, TAKEOFF_BUFFER, LATE_WINDOW, RECOVER_TIME; `resolve_trick`
  is the mapping; charge time 0.55 s in `_arrow_tricks`.
- Flip / spin pop: Skier.FLIP_POP, WIND_SPIN, SPIN_MAX, UNWIND_TIME.
- Off-axis: Skier.OFFAXIS, OFF_MIN_AIR, OFF_FLIP_RATE, OFF_FLIP_END; air control rates use the difficulty's `air_spin` /
  `air_flip`; landing help uses `level` (Skier.DIFFICULTIES).
- Grabs: Skier.GRAB_IN / GRAB_OUT / GRAB_AUTO_RELEASE; poses in SkierBody.GRAB_POSES.
- Off-axis body shapes: SkierBody._compute_pose (search "off-axis takeoff shapes").
- Landing tolerance / impact limits: Skier.DIFFICULTIES `land_tol`, `impact`.
- Park layout and jump sizes: build/parks.py (DESIGNS "Ridgeline Park", STEPUP, KICKERS).
- Cloth: SkierBody.CLOTH_SPRING.
