Upgrade my existing skiing game with a major overhaul of its gameplay, physics, character, terrain, animations, and graphics. I want a polished modern skiing game with expressive movement, believable snow, and a mountain that is fun to explore.

Use Riders Republic as a reference for the low-speed pushing mechanic, and Jibberish/Jibbers as a reference for the loose, reactive skier movement I’m describing. These are references for feel; preserve my game’s own identity.

First, inspect the existing project, engine, movement code, assets, and rendering setup. Then implement the improvements in stages. Work directly on the game, test your changes, and preserve existing working features and saves.
1. Much more physical skiing
The current movement feels stiff, especially when crossing uneven terrain. Rework it around momentum, ski contact, balance, and suspension.
- Calculate contact for each ski, preferably at multiple points along its length. Align the skis naturally with the snow while keeping the body’s motion smooth.
- Make gravity, slope angle, friction, edge grip, and sideways slipping meaningfully affect movement.
- Let the skier carve through turns, with appropriate body lean and weight transfer. Turning should depend on speed and edge engagement.
- Add damped leg suspension so the knees absorb bumps and compress through transitions. Small terrain irregularities should not repeatedly launch the entire character.
- Preserve momentum across terrain transitions. Avoid sudden velocity changes, excessive ground snapping, and unexplained bouncing.
- Support partial contact: one ski can lose contact before the other.
- Make landings depend on the relationship between velocity, ski direction, slope, and body balance. A landing into a matching downhill slope should feel different from hitting flat ground.
I want a loose, “jelly-like” body that responds to forces while remaining controllable. Use a stable physical controller with a procedural skeleton or active ragdoll where appropriate. Let the torso, hips, knees, and arms react with controlled spring and damping. Avoid making the skier floppy, unstable, or constantly close to falling over.
2. Replace tucking with low-speed pushing
Replace the current tuck action with a convincing pole-pushing animation that helps the skier get moving.
- Pushing works while stationary or moving slowly.
- Each push has anticipation, pole contact, propulsion, and recovery.
- Apply the forward impulse during the actual propulsion phase.
- Fade assistance out smoothly as speed increases.
- Above a configurable speed threshold, pushing provides no acceleration and does not trigger the animation.
- Require appropriate ground contact. Prevent pushing in midair or gaining unlimited speed by spamming the input.
- Uphill pushing should provide limited help rather than overpowering gravity.
At high speed, the skier can naturally adopt an athletic stance, but this input must not become a speed boost.
3. Build an actual skier with style
Replace the placeholder appearance with a properly proportioned, articulated skier wearing:
- A detailed black ski jacket.
- Baggy black snow pants.
- Quality black ski boots attached correctly to bindings.
- Black gloves, goggles, and a coordinated helmet or headwear.
- Proper skis, bindings, and poles.
Give the clothing believable volume, folds, seams, and material variation. The jacket, pants, and boots should have different roughness and surface qualities so the outfit remains readable in shadow. Keep the silhouette stylish and relaxed.

Use a real skeleton and coherent joint movement. Add foot placement, hand alignment, and restrained secondary motion for clothing where practical. Prioritize a strong model and convincing movement over expensive cloth simulation.
4. Give tricks life and style
Rework the stiff flips and spins.

Layout backflips:
- Start with a believable takeoff and body extension.
- Use an elongated layout pose with a slight natural arch.
- Let the hips, legs, torso, and arms contribute to the motion.
- Transition smoothly into spotting the landing and bringing the skis toward the slope.
Spins:
- Add shoulder and hip windup, counterrotation, relaxed arms, and subtle asymmetry.
- Let the skis follow the body naturally.
- Blend between takeoff, rotation, optional grabs, and landing preparation.
- Make combined flips and spins feel connected.
Use physics to govern trajectory and angular motion, with bounded player control and procedural posing for expression. Avoid rotating the entire character as one rigid object or snapping instantly into a landing pose.

Landings should include knee compression, body follow-through, ski movement, and a brief recovery. Match the impact response to the actual landing force. Tricks should have “steeze” while remaining readable and responsive.
5. Redesign the bland mountain
Give the mountain a strong silhouette, distinct areas, and deliberate routes.

Add:
- Narrow chutes between rock formations.
- Actual cliff edges with clear takeoffs, open air below, and usable landing slopes.
- Small, medium, and advanced drops.
- Wind lips, cornices, natural kickers, bowls, ridgelines, and flowing gullies.
- Tree lines, exposed rock, and recognizable landmarks.
- Routes that connect naturally, with opportunities to choose different lines.
Remove or reshape the repetitive high-speed moguls causing constant bouncing. Use larger, smoother terrain features on fast routes. Keep technical bumps in suitable areas where the movement system can handle them.

Design terrain around skiing speed and landing geometry. Avoid random noise that creates unpleasant chatter. Make dangerous features readable from the approach, and provide recovery routes when possible.
6. A major graphics and snow upgrade
Aim for a polished contemporary sports-game appearance. Improve the underlying art, materials, lighting, and composition together.
- Create snow materials with convincing fine detail, distance blending, roughness variation, and subtle sparkle.
- Differentiate fresh powder, packed snow, wind-scoured surfaces, and exposed rock.
- Improve mountain shapes, rock formations, vegetation placement, and environmental detail.
- Add strong directional lighting, readable terrain shadows, restrained atmospheric haze, and consistent color grading.
- Preserve detail in bright snow and the black outfit.
- Use restrained bloom and camera effects. Keep the image sharp and readable during fast movement.
Make snow effects respond to skiing:
- Edge spray follows the engaged ski edges.
- Spray direction and intensity reflect speed, turn force, slipping, and snow type.
- Hard braking produces a stronger plume.
- Landings produce impact bursts proportional to the impact.
- Skis leave tracks with sensible persistence and performance limits.
- Airborne snow particles catch light without covering the player or obscuring terrain.
Avoid constant identical particle clouds. Effects should communicate what the skis are doing.
7. Keep it optimized
Establish a performance baseline before making major changes. Target stable 60 FPS on the project’s intended hardware, with scalable settings.

Use appropriate mesh LODs, vegetation instancing, culling, pooled particles, capped effects, efficient materials, and controlled shadow distances. Keep expensive simulation close to the player.

Run physics at a stable fixed timestep and interpolate visuals appropriately. Make movement frame-rate independent. Ensure high-speed collision remains reliable.

Profile representative gameplay before and after the upgrade. Report the tested hardware or environment, resolution, graphics settings, and measured results. If you cannot measure performance, say so clearly.
8. Implement and validate
Start with ski contact, suspension, and pushing. Then improve character posing and tricks, build one polished mountain section, and apply the visual overhaul. Expand proven improvements across the map.

Test:
- Starting from rest and pushing.
- Pushing becoming unavailable at speed.
- Slow turns, fast carving, braking, and traversing.
- Smooth travel across uneven terrain.
- Cliff takeoffs and slope landings.
- Layout backflips, spins, and combined tricks.
- Crashes, recovery, and respawning.
- Performance during dense snow effects and detailed scenery.
Expose useful tuning values for grip, suspension, damping, pushing, air control, and effects. Finish with a concise explanation of what changed, what was tested, and any remaining limitations.

Make the actual improvements. Prioritize satisfying skiing, expressive character movement, strong terrain design, and a cohesive visual result.