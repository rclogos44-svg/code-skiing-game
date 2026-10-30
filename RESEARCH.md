# Reference research: Grand Mountain Adventure 2, Steep, Riders Republic

Goal: learn what players and critics like / dislike about the map, HUD, skiing feel, lifts,
on-foot movement and graphics of three well-known open-mountain games, and turn that into
design decisions for SUMMIT. Only ideas are borrowed; all code, art and audio stay original.

Method: web search (Oct 2026). Many game sites (Steam store, 148apps, ludo.guide) are not
reachable from the build environment, so findings come from search-result summaries of reviews,
store pages and guides, plus ski-instruction and ski-lift engineering sources for the
real-world details. Sources are listed at the end.

## What the sources say

**Grand Mountain Adventure 2 (Toppluva)**
- Praised for crisp, soothing graphics, small details such as the tracks you leave in the snow,
  and the snow physics and NPC skiers that make the resort feel alive.
- Non-linear resorts: follow pistes, ride lifts, hit the park or freeride a chute; a variety of
  lifts and transport to reach the summits; you ride a lift, open the map and choose a line.
- A review of the first game complained that its hockey stop at the end of turns looked
  abrupt and unnatural and asked for a progressive braking turn instead.
- Common complaint: performance (stutter, frame drops at higher settings).

**Steep (Ubisoft)**
- The 3D mountain map is admired (fly over the peaks, pick a drop point, fast-travel), but
  reviewers found it hard to locate specific events in it.
- On foot: you can switch between walking and the sports; walking through deep snow is slow and
  hiking to a drop point can feel like a chore.
- Several reviews call the controls imprecise and the open world lifeless (few other people).

**Riders Republic (Ubisoft)**
- Core controls are easy to pick up (accelerate and steer); the HUD has a speedometer and can be
  customised.
- Players complain about too many pop-ups and world-space labels cluttering the screen, and an
  accessibility review flags small UI text.

**Real-world references**
- Hockey stop (PSIA instructor task): from a taller stance, quickly flex lower so the skis pivot
  underneath a quiet upper body that keeps facing down the fall line; the edge set comes from
  the legs and feet, not from swinging the upper body.
- Chairlifts: loading interval of roughly 6-10 s per chair (capacity = 3600 / interval x seats);
  detachable lifts run about twice as fast as fixed-grip ones; loading points are clearly
  marked, with the chair arriving from behind at seat height.

## Decisions for SUMMIT

| Area | Decision |
|---|---|
| Braking | S is a hockey stop: skis pivot ~80° across the direction of travel (toward the hill, or the side you steer), edges set, snow sprays forward. It is progressive: a tap is a speed check, holding it stops you. Animation follows the PSIA description: quick unweight, drop into a low flexed stance, skis pivot under an upper body that keeps facing downhill, lean into the hill. The snowplow ("pizza") is gone. |
| On foot | T takes the skis off / puts them on. Camera-relative walking, Shift to jog, Space to hop; slower uphill and in deep powder, impossible above ~40° - but quicker than Steep's slog so hiking a short way to a line is not a chore. Skis carried on the shoulder. |
| Lifts | Chairs every 36 m (~7 s apart) instead of 22 m, up and down lines further apart, colour-coded chairs per lift with riders on the way up, terminals with bull wheels, a marked loading point and a lift sign (name, vertical, ride time). You actually sit on a chair and ride up (hold the key to skip ahead). |
| Minimap | Small, clean, round minimap top-right (rotates with the camera; north-up option; can be turned off) - pistes, lifts, drop zones, challenge markers, next race gate and waypoint; notifications moved below it to avoid clutter. |
| Map | Click anywhere to set a waypoint (shown on the map, minimap, in the world and as a distance), so finding a challenge or spot is easy - the main complaint about Steep's map. |
| World life | NPC skiers on the pistes and riders on the chairs (GMA2's lively resort vs. Steep's "lifeless" world). |
| Graphics / UI | Keep the crisp look; keep HUD text large; avoid world-space label clutter. |

## Sources
- GMA2 reviews and listings: https://gamebrain.co/game/grand-mountain-adventure-2 ,
  https://www.pocketgamer.com/grand-mountain-adventure-2/app-army-assemble ,
  https://legacy.prod.metacritic.com/game/ios/grand-mountain-adventure-2 ,
  https://apps.apple.com/us/app/grand-mountain-adventure-2/id6475040075 ,
  https://play.google.com/store/apps/details?id=com.toppluva.grandmountain2&hl=en ,
  https://unofficialnetworks.com/2020/10/19/grand-mountain-adventure/ ,
  https://justuseapp.com/en/app/1468010739/grand-mountain-adventure/reviews
- Steep: https://www.pcgamer.com/steep-review/ , https://www.gamesradar.com/steep-review ,
  https://www.newgamenetwork.com/article/1586/steep-review , https://twinfinite.net/?p=238364 ,
  https://medium.com/dreamsportsjournal/steep-ps4-2019-review-c34d04868186
- Riders Republic: https://steamcommunity.com/app/2290180/discussions/0/3817410454880410616 ,
  https://caniplaythat.com/2021/10/29/riders-republic-accessibility-review-can-i-play-that/ ,
  https://uat4.www.digitaltrends.com/gaming/riders-republic-review
- Hockey stop: https://www.psia-nw.org/video-galleries/alpine-level-i-tasks/hockey-stop
- Chairlifts: https://en.wikipedia.org/wiki/Chairlift ,
  https://www.saminfo.com/archives/2010-2017/2018/july-2018/know-your-capacity ,
  https://liftblog.com/old-homewood-express-homewood-ca
