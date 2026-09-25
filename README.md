# Goliath Explorer

Space simulator with a realistic black hole you can fly into, asteroid fields, hostile interceptor ships, an alien dreadnought mothership, a planetary nebula around a white dwarf, and a pulsar.

Vibecoded with Opus 5, built with **Godot 4.7** (Forward+ / Vulkan), with every mesh and texture generated in code at load time instead of external art files.



https://github.com/user-attachments/assets/e3d3c3e6-e678-446b-aff0-e867ed5c10b6





# 🕹️ Game & Graphics

No quests, the black hole is the content. Find out how close you can hold an orbit before your engines can't keep up, and see what happens when you fall in from the inside.

- **Orbit the disk.** Outside a certain line gravity is zero and you're free flying. Cross it and gravity pulls you straight in.
- **Cross the horizon.** You can actually do it. Controls are gone the moment you cross, but the fall plays out for a few seconds with ship tumbling and camera shaking harder the deeper you go.
- **Fight.** Interceptors spawn near you and despawn once you lose them. Asteroids break apart under fire. An alien dreadnought sits behind your starting position (near the green nebula) with five tracking turrets and a patrol screen.
- **Visit the landmarks.** A nebula and a pulsar are both visible from start and deadly up close.

### Flight model

Semi-Newtonian and hand-tuned, so thrust, drag and gravity are just numbers you can tweak. The flight assist has limits that Goliath overpowers when you're close enough. Mouse movement controls turn rate instead of instant push, so aiming stays consistent regardless of frame rate, and the ship keeps tumbling for a moment after you flick before drag catches up.

### Three hulls (ships)

Pick in the Hangar, which shows the exact generated model you'll fly. Top speed is thrust * brake time:

| Hull | Top speed | HP | Guns | Charged beam |
|---|---|---|---|---|
| MK-I Skiff | 1213 u/s | 100 | 84 dps | 9.0 s |
| Wasp Interceptor | 2015 u/s | 60 | 90 dps | 14.5 s |
| Anvil Mining Rig | 771 u/s | 210 | 75 dps | 5.5 s |

The charged beam breaks the pattern on purpose: weakest guns and worst handling means it recharges fastest, so the Anvil has one clear strength and the Wasp pays for its speed elsewhere.

### Weapons

- Lasers fire as a single hit-scan ray down the center, so whatever your crosshair covers gets hit. Two tracer beams from the wing roots are just for looks.

- The charged beam (Q) charges a plasma sphere at your nose while you hold it, then fires on release and travels across space instead of hitting instantly. Lasers land wherever your crosshair is right now; this weapon is about picking a heading and watching it close the distance. Damages everything in the blast radius on impact.

- Aim assist keeps a light lock on whatever's nearest your crosshair and holds it briefly after you look away. Targets cross the aiming cone in a couple frames at these speeds.

### Interface

- Bearing tape at the top shows Goliath, both landmarks, the dreadnought and nearby hostiles by direction, so you know which way to turn without reading coordinates.
- Vessel panel (top left): hull HP, speed, thruster heat and charged beam as plain numbers ("84 / 100") instead of percentages.
- Goliath telemetry (top right): distance in Schwarzschild radii, altitude, current pull, and how much open sky is left.
- Radar and fullscreen map (`M`), both matching whatever range you set in settings.
- Escape compass, kill banner, temporary scoreboard, and the boss health bar.
- Coordinates bottom left, plus Info & Briefing panel on the menu pulling numbers from live settings.

### Customization and settings

Everything lives in one autoload, `core/Globals.gd`, set up as a scene so every setting shows up as a slider in the editor. Open `core/Globals.tscn` to tune anything.

The in-game Options panel is built from a table, so adding a setting takes one line:

- **Graphics quality** (1-10): one slider driving resolution scale, raymarch steps, background detail and glow together. The Goliath raymarch takes most frame time on integrated graphics so they're linked.
- **Simulation**: lensing strength, disk size and thickness, gravity range and strength, nebula brightness, asteroid density and spawn rate.
- **Landmarks**: gravity and size for the nebula and pulsar. Size scales the body and its danger zone together.
- **Camera & input**: FOV, distortion, shake, mouse sensitivity (increase this), invert pitch.
- **Weapons**: aim-assist cone, target-assist hold time, beam length, blast radius.
- **Controls**: rebind every action to any key or mouse button.



# 🧬 Code & Science

### How to run

Open the project in Godot 4.7+ and press play, or run `godot --path .`.
Prebuilt builds are in `build/`: `GoliathExplorer.exe` for Windows (keep the `.pck` next to it) and `GoliathExplorer.AppImage` for Linux (make it executable and run it).
`environment/TestFlight.tscn` is a bare scene for testing just the black hole shader.

### Structure

8 folders, each with one job. `environment/` doesn't talk directly to `ship/`, they only meet through `GravityWell`'s public methods. `ui/` reads from the ship, but the ship doesn't know the UI exists.

| Folder | Owns |
|---|---|
| `core/` | Global tuning, gravity, debug camera |
| `ship/` | Player ship, flight model, chase camera, weapons |
| `enemy/` | Interceptors and their spawner |
| `environment/` | Goliath, shaders, asteroids, scenes |
| `hazards/` | White dwarf, pulsar, and their shaders |
| `boss/` | The dreadnought and turrets |
| `ui/` | HUD, options, hangar, briefing |
| `menu/` | Title screen and navigation |

Geometry is generated, not modeled, so ships, asteroids, the alien hull and magnetosphere are all built with `SurfaceTool` at load time. Every dimension is just a number you can tweak and re-run. See `docs/core_architecture.md` for the longer version with benchmarks.

## The science

The project is really about the black hole, so that part gets the full writeup. The nebula and pulsar are simpler and rougher, made fast and not meant for close inspection, so their sections are short (btw there's no sound in the game).

Units are Schwarzschild radii throughout: the shader works in natural units where `rs = 1`, and one number in `Globals` maps that to world units. One world unit is about ten metres; `rs` is 575 of them.

### The black hole

For a non-rotating mass, the event horizon sits at the Schwarzschild radius:

```
r_s = 2GM / c²
```

Light rays bend step by step using the standard approximation for how light curves near a black hole. Treating `h² = |r × v|²` as constant along the path, each step bends the ray by:

```
d²r/dt² = −(3/2) · h² · r / |r|⁵
```

This is the same effect that bends starlight at the sun's edge, just far stronger. It runs until a ray escapes, falls in, or gets absorbed by the disk.

Three radii come out of that integration, all visible in the game:

- **The photon sphere** at `r = 1.5 r_s`, where light can orbit. Rays that graze it wrap around before escaping, forming the bright photon ring.
- **The shadow**, with critical impact parameter `b_c = 3√3/2 · r_s ≈ 2.598 r_s`. Anything aimed inside never comes back, which is why the shadow looks bigger than the horizon itself.
- **The ISCO** at `r = 3 r_s`, the innermost stable circular orbit. The disk starts here, leaving a dark gap between the gas and the horizon.

The HUD's "sky open" readout shows how much sky is visible from radius `r`:

```
sin θ_shadow = (b_c / r) · √(1 − 1/r)
```

The visible sky shrinks to a point as you approach the horizon.

**The disk** is a puffed-up slab, not flat, and light builds up along each ray instead of being sampled once. That's why flying through looks like fog instead of passing through a sheet. Gas closer in orbits faster (`v ∝ r^(−1/2)`), and that speed difference twists it into streaks. Color comes from Doppler shift: the side spinning toward you looks brighter and bluer, the side spinning away looks dimmer, the same lopsided look seen in real black hole images.

One fix worth keeping: without correcting for viewing angle, rays that skim the disk edge-on pick up too much brightness and wash to white. Weighting by that angle fixes it, with a small floor left in so grazing views still glow a bit.

### The pulsar

The magnetic axis is tilted away from the spin axis, so beams sweep around like a lighthouse as the star turns. That's why real pulsars appear to blink.

Field lines (`r(θ) = L · sin²θ`) are drawn as actual line geometry instead of raymarched, because they're too thin for a volume march to catch. The beams themselves are raymarched, and the same angle both draws the visible cone and decides what damages the player, so what you see matches what hurts you.

### The supernova remnant

Loosely modeled on the Helix Nebula: shells, a ring around the middle, and streaks of denser gas pointing at the star. Color follows temperature: blue-white near the center, fading to rust red at the edge.

Streaks stay pointed at the star because their noise pattern is based on direction only, then twisted with distance so they curve instead of forming straight spokes.

### The white dwarf and neutron star

Both are drawn as simple analytic discs from the ray's closest approach instead of raymarched, because they're too small for a march to reliably hit. That means they never flicker and get a soft glow for free.
