# GoliathExplorer: core architecture

A Godot 4.7 (Forward+) space sim built around one thing: a Schwarzschild black
hole you can actually fly into, raymarched per-pixel rather than faked with a
sprite.

## Modules

Each folder has one job and a narrow interface to the others.

| Folder | Owns | Depends on |
|---|---|---|
| `core/` | Global tuning, gravity, the debug camera | nothing |
| `enemy/` | Hostile interceptors and their spawner | `core/`, `ship/` (mesh) |
| `ui/` | Draw vocabulary, HUD, options, hangar | `core/`, reads `ship/` |
| `menu/` | Title screen and navigation | `core/`, `ui/` |
| `environment/` | Goliath, its shaders, asteroids, the scenes | `core/` |
| `hazards/` | The white dwarf, the pulsar, procedural gas | `core/` |
| `boss/` | The dreadnought and its turrets | `core/`, `hazards/`, `ship/` |
| `ship/` | Player vessel, flight model, chase camera | `core/` |
| `docs/` | This file | nothing |

Nothing reaches sideways. `environment/` never touches `ship/`; they meet
through `GravityWell`'s public methods and nothing else. `ui/` reads the ship
but the ship knows nothing about the interface, so the HUD can be replaced
without touching flight code.

### Two scenes, on purpose

- **`environment/Expedition.tscn`** is the game: Goliath, the asteroid field, the
  ship, the HUD. This is what "Start Expedition" loads.
- **`environment/TestFlight.tscn`** is the shader bench: Goliath, a free-fly
  camera, and three fixed rocks used as depth probes. No ship, no field, no
  HUD, so a rendering change can be judged without gameplay in the way.

### `core/Globals.gd` + `core/Globals.tscn`: the tuning hub

Autoloaded as `Globals`. Every number worth playing with lives here: lensing
strength and disk tint, gravity and its deadzone, spawn rates, FOV distortion,
world scale.

The autoload points at **`Globals.tscn`, not at `Globals.gd`**, because Godot
only surfaces `@export` variables for nodes you can select in the inspector,
and an autoload registered as a bare script is not selectable: its exports
would be invisible and the "customization hub" would be a file you edit by
hand. Wrapping the script in a one-node scene makes every knob a live
inspector slider. Open `core/Globals.tscn` to tune.

Every setter emits `settings_changed`. `Goliath.gd` is a `@tool` script
listening to it, so dragging a slider re-tunes the hole in the editor viewport
immediately, with no play-test cycle.

### `core/GravityWell.gd`: the pull, with a deadzone

Not an `Area3D`. Ships, asteroids and debris all need the
acceleration at a point, and several of them will not be physics bodies at all,
so this is a plain query: `get_acceleration(world_pos) -> Vector3`. Consumers
find it through the `gravity_wells` group rather than a hardcoded path.

The deadzone is the design:

- **Outside `bh_capture_radius`** (default 8 rs, inside the visible disk and well
  outside the ISCO): returns exactly `Vector3.ZERO`. No drift, no nagging tug.
  The whole outer disk is free flight.
- **Inside it**: inward pull and a tangential frame-dragging term ramp in
  together, shaped by `bh_falloff_exponent`. Crossing the line puts you into a
  decaying spiral, not a straight plunge.

Two separate progress curves, because they answer different questions:

- `capture_progress()`: 0 at the deadzone edge, 1 at the horizon. Drives gravity.
- `proximity()`: 0 at the disk's outer edge, 1 at the horizon. Drives FOV
  distortion, so the view starts stretching while you are still coasting freely
  instead of snapping the instant gravity engages.

### `ship/`: the flight model

`Ship.gd` is a `CharacterBody3D`, not a `RigidBody3D`, so thrust, drag and
gravity are all authored here, and the braking assist
has an authority ceiling that **loses** to Goliath close in. A rigid
body would bury all three in the solver. `move_and_collide` still gives real
collisions, which is all the asteroids need.

**Linear feel: the "in-between".** Braking thrusters run continuously, pulling
velocity toward zero with a time constant of `ship_brake_time / 3`, so releasing
the throttle sheds ~95% of your speed in that many seconds. Two things fall out
for free:

- a natural terminal velocity of `thrust x tau` (~1200 u/s at defaults), and
- because assist authority is capped at `ship_assist_authority x thrust`, a
  radius inside which gravity simply out-pulls your engines.

That radius is the game. `GravityWell.point_of_no_return_rs()` solves for it by
bisection and the HUD prints it. At defaults it sits near 2 rs, comfortably
inside the 8 rs deadzone edge, so there is a band where you are being pulled but
can still climb out, which is where the interesting flying is.

**Angular feel.** Mouse motion is read as a rate *command* (pixels per second →
rad/s), not as an impulse, so handling does not change with frame rate. Angular
velocity chases that command through its own drag constant, which is what lets
the ship keep tumbling for a moment after a flick. Roll is on Q/E. Nothing is
axis-locked, so the ship can tumble through any orientation.

`ChaseCamera.gd` runs `top_level`, parented to the ship but inheriting nothing
from it.

**Position tracking is exact.** The obvious implementation (exponentially
interpolate the camera toward the ship each frame) is wrong for a
craft that accelerates this hard. An interpolation with time constant `tau`
settles at a steady-state error of `speed * tau`; at 1200 u/s and `tau = 0.09`
that is over a hundred units, so the ship tears away from the camera under
thrust and snaps back when you release. The only displacement allowed now is a
lean driven by acceleration and hard-limited to `max_lean` (0.32 units), which
keeps the physical cue (the ship presses back into frame when you burn)
without the rubber band. Orientation still lags, because that reads as mass
rather than as a bug.

The camera also owns mouse-wheel zoom: `distance` runs from `max_distance` down
to zero, and below `cockpit_threshold` the hull is hidden and the eye blends
into the canopy, giving a first-person view out of the same control. Trauma
shake and FOV distortion live here too.

`ShipMesh.gd` generates the hull as an `ArrayMesh` at load: tapered hexagonal
spine, faceted canopy, swept delta wings with winglets, twin nacelles. Generated
rather than authored because there is no asset pipeline yet and a checked-in
`.glb` would be an opaque blob nobody can tune. Every face is oriented against a
point known to be inside its own solid, so winding cannot come out inverted.

### `ui/`: the interface

`SciFi.gd` holds the entire visual vocabulary: palette, chamfered-rectangle
geometry, multi-pass glow strokes, segmented meters. Everything in `ui/` draws
through it rather than through StyleBoxes, because cut corners are not a
`StyleBoxFlat` shape and the glow is a stroke pass a StyleBox cannot express.
Retheming the ship is one file.

- `HudPanel.gd` / `StatBar.gd` / `SkinSlot.gd`: the reusable pieces.
- `HUD.tscn`: top left is the ship (hull, velocity, thruster heat), top right is
  Goliath (radius, altitude, pull, sky aperture, capture status).
- `EscapeCompass.gd`: see *Navigating the dark* below.
- `OptionsPanel.gd`: generated from a table; each row names a property on
  `Globals` and reads its current value straight off it, so there is no second
  copy of the settings to keep in sync. Adding a knob is one line. Row kind is
  the first field: `#` heading, `@` checkbox, `$` the key-binding block,
  anything else a slider. Rebinding listens on `_input` so the key being bound
  cannot also fire what it is currently bound to, takes the key away from any
  other action that held it, and strips the event down to the physical keycode
  so a stray modifier state at press time cannot make the binding unmatchable.
- `HangarPanel.gd`: renders the same `ShipMesh.build()` geometry the expedition
  uses, in its own `SubViewport` world, so the locker can never drift out of
  sync with the real ship the way a screenshot would.

### `enemy/`: hostiles

`Enemy.gd` is a `CharacterBody3D` on collision layer 3, flying the same
flight-assist shape as the player so the two handle alike. The AI is
thin: close on the player, wander when nobody is in range, with
one rule that matters more than it sounds: every goal is pushed back out to
`keep_out_rs`, outside the gravity deadzone. Without it a spawner quietly feeds
its whole population into the hole within a minute and the map empties.

Both the AI's keep-out and the spawner's floor are **derived from**
`Globals.bh_capture_radius` plus a margin rather than written down. That radius
is a setting now, and a fixed number would quietly start spawning hostiles
inside the deadzone the moment anyone raised it. Verified at the current 13 rs:
nothing spawns inside it.

Two rules keep them out of Goliath rather than one. The goal rule above covers
where they *want* to be; an overshoot at speed still lands inside the deadzone,
and an interceptor's engines are about a twelfth of the pull at the horizon, so
from there it is going in whatever its flight plan says. So a captured hostile
also burns straight outward (enough to save a shallow overshoot, nowhere near
enough to climb out from deep in), and anything that crosses the horizon anyway
is destroyed on the spot. Without that last part they pile up in the shadow
where they cannot be shot, cannot leave, and keep showing on the map as contacts
that never resolve. No score for it: Goliath killed it, not the player.

**Spawn placement.** `EnemySpawner.gd` spawns around the player, not around the
map. The first version seeded a fixed ring around Goliath and left everything
in it awake forever, which was wrong twice over. Interceptors thirty
kilometres away were still running flight assist and a `move_and_collide`
every physics tick for nobody's benefit: that is the frame time this cost. And
because they were placed by *radius*, flying out to the pulsar meant flying
away from the entire population: the map had hostiles on it and the game did
not.

Now they appear in a shell 4.2–9 km around the player, out of immediate view and
clear of the deadzone, and are freed once they fall 17 km behind. The gap
between those two numbers is hysteresis: a hostile that spawns at
the rim and turns away must not be deleted on the next tick. Freed rather than
pooled, because a pool would keep the physics bodies in the world and the body
is the cost. The cap came down from 7 to 4 to match: four nearby is a busier
fight than seven scattered across the system ever was, and it is a frame-time
budget as much as a difficulty knob.

### `ship/`: hull classes

`ShipClasses.gd` holds three playable hulls and is the single place their stats
live. Selecting one writes the whole entry into the corresponding `Globals`
properties rather than being read through an indirection at every call site,
so the flight model, the HUD gauges, the chase camera's speed kick and the
hangar's own bars all keep reading exactly the fields they already read, and the
inspector sliders stay usable for fine-tuning on top of a chosen hull.

| | Top speed | Hull | DPS | Feel |
|---|---:|---:|---:|---|
| MK-I Skiff | 1213 u/s | 100 | 84 | balanced |
| Wasp Interceptor | 2015 u/s | 60 | 90 | fast, fragile, snappy |
| Anvil Mining Rig | 771 u/s | 210 | 75 | slow, tough, heavy punch |

**Top speed is a trap.** Under flight assist, top speed is `thrust × brake_time / 3`,
engine power *and* how long the brakes take. The first version of this table
gave the fast hull punchier brakes to make it feel agile, which cancelled its
extra thrust exactly and put all three classes within 90 u/s of each other.
Agility now lives in the turn and angular-brake rates, where it belongs; brake
time is left to set top speed.

### `ship/`: weapons

`LaserCannon.gd` resolves each shot as **one ray down the ship's centre line**
and spawns two `LaserBolt` tracers from the wing roots purely for the look.

That split was forced by a measurement. The first version gave each bolt its own
swept raycast, fired parallel from the muzzles, and it missed everything. The
muzzles sit 0.52 units either side of the centre line while an interceptor's
hull is about 0.57 units of half-width, so at four kilometres the two beams
sailed past on either side of a target the crosshair was centred on. Converging
the guns would fix that at exactly one range. Resolving the shot where the
player is actually aiming fixes it at every range, and costs one raycast per
volley instead of two per physics tick.

**Tracers.** `LaserBolt` widens with range, but only *partially*. Fired from a
chase camera a bolt recedes almost exactly along the view axis, so it is seen
end-on: however long the beam, what reaches the eye is its cross-section, and
that shrinks until the shot simply vanishes. Lengthening it does nothing: a
380-unit beam pointed away from the camera still projects to about 13 pixels.
Muzzle spacing cannot rescue it either: half a unit of separation at two
kilometres is 0.014 degrees.

The first fix over-corrected: holding a genuinely *constant* apparent width
means nothing about the bolt changes frame to frame, and it reads as parked in
mid-air rather than as travelling away. The exponent is now 0.7 rather than 1,
so it still shrinks, just far more slowly than perspective alone would shrink
it. Measured over one flight: 0.0183 rad of apparent width at 700 units falling
to 0.0113 at 3500, visibly receding, still legible at the far end. The last
third of the flight fades the alpha out, because a tracer that winks out at full
brightness on reaching its limit looks like a shot being deleted rather than one
running out of range. Length is left unscaled and exposed as
`Globals.laser_beam_length`, so seen from the side it is still a beam rather
than a wall.

**Aim assist** keeps a magnetic lock on whatever sits nearest the crosshair
inside `aim_assist_cone`, and holds it for
`aim_assist_grace` after the crosshair leaves. At these closing speeds a target
crosses a 3-degree cone in a couple of frames; without the grace period the
assist would only ever help players who were already on target. Only the ray
bends: the tracers still leave the muzzles pointing where the ship points, so
the help is felt rather than seen. `ui/TargetMarkers.gd` draws a bracket on the
locked target, because an invisible assist reads as the game randomly deciding
whether shots count.

Anything the assist pulls onto **must be inside the aim cone**. The soft target
(`E`) gets priority among candidates, but only while it is actually ahead of the
nose: an earlier version gave it priority unconditionally, and since a soft lock
lasts seconds, firing at an asteroid quietly sent every round at a hostile off
screen. Aim assist may nudge a shot; it may not choose the target for you.

**Soft lock (`E`)** is a "help me come about" button rather than an auto-aim. It
searches a wide cone, then feeds a steering rate proportional to the angular
error into the same command the mouse drives, capped well under
`ship_turn_rate` and faded out over the last second so it releases rather than
snaps off. Measured: 24 degrees of error closed to 3.9 over two seconds, and the
pilot can out-turn it at any point.

Asteroids take damage too: hit points scale with radius, so size on screen is
the cue for how long something takes to break. `ImpactFlash` pops at every hit
point, small for a hit and large for a kill; without it, shooting a rock that
takes six shots looks exactly like missing it six times.

### `ship/`: the charged beam (`Q`)

Hold `Q` to spin a plasma sphere up at the nose; release to launch it. Three
states, and one gauge shows all three, because they are never both interesting
at once: while recharging the bar is the recharge, and once ready the bar is the
charge you are holding.

`ChargeShot` is **not** hitscan, unlike the lasers.
A duelling weapon has to land where the crosshair is at the instant you pull; a
siege weapon's whole identity is that you commit to a heading, watch it cross
the gap, and see what it takes with it. Travel time is the weapon. On contact it
runs a sphere query and damages everything inside `charge_blast_radius` with
linear falloff from the centre: nothing at the rim takes full damage, which is
what stops the blast radius being a hard line the player has to guess at.

Releasing below 18% of a full charge cancels and costs nothing. A weapon with a
fifteen-second cooldown must not be spendable by brushing a key.

The recharge is the one stat that runs *against* the rest of `ShipClasses`:

| Hull | Recharge |
|---|---|
| Anvil Mining Rig (heavy) | 5.5 s |
| MK-I Skiff (balanced) | 9.0 s |
| Wasp Interceptor (scout) | 14.5 s |

The hull with the worst guns and the worst handling gets the fastest recharge,
so the Anvil has one thing it is unambiguously best at and the Wasp pays for its
agility somewhere.

The charging VFX is `ship/charge_orb.gdshader`: unshaded, additive, two bands
of detail turning against each other, driven entirely by `TIME` and a single
`charge` uniform. Blue while it spins up, green as it fills, white-hot at full,
so the state can be read off the colour without the gauge.

### `hazards/`: the deep-space landmarks

`Hazard` is modelled on `GravityWell` rather than on `Area3D`, and for the same
reason: everything that wants to be pulled asks for an acceleration at a point
once per physics tick, so nothing has to overlap anything. What it adds is that
there can be *several*, found through the `hazards` group, which is why `Ship`
sums the group rather than consulting one node. Summing means two overlapping
hazards behave like two overlapping hazards instead of like whichever the sort
order happened to pick.

Every hazard's pull is weaker than every hull's braking authority,
so it is a current you fly against rather than a capture. Goliath stays the only
thing in the game that wins outright. And each is exactly zero outside its own
radius (the same deadzone idea), so drifting through the system is never a slow
accumulation of nudges from objects you cannot see.

#### Both landmarks are raymarched, for the same reason Goliath is

They started as geometry: braided tori for the remnant's rings, an instanced
MultiMesh of darts for its cometary knots, nested additive spheres for its gas,
and cone meshes for the pulsar's beams. All of it shared one failure. **A mesh
has a silhouette and gas does not.** A torus seen edge-on is a hard-edged
ribbon; a cone at any opacity is a wedge of coloured plastic; a sphere at
uniform alpha is a ball with a rim. Each could be tuned to read correctly from
one distance and one angle at a time, and never from all of them.

Both now use the skeleton `Goliath.gdshader` established: an inverted bounding
sphere in the transparent pass, the ray rebuilt from `INV_PROJECTION_MATRIX`
rather than from mesh geometry so it survives the near plane slicing the
volume, clamped against the depth buffer so ships occlude it, linear HDR out for
the scene's ACES pass, premultiplied alpha. The shared parts live in
`hazards/volume.gdshaderinc`.

Two things in that skeleton stand out on their own.

**Neither volume writes depth, and neither does Goliath.** Two transparent
volumes therefore cannot sort against each other, and whichever draws second
wins regardless of what the geometry says. Since Goliath's march returns opaque
for every pixel where it does not find scene geometry, everything else that
skips the depth buffer has to yield to it (`behind_occluder`).

What counts as "Goliath" for that test is **everything it draws opaquely**, and
arriving at that took two wrong answers first.

Testing against the *influence sphere* looks right and is wrong twice over. The
sphere is 17.6 km across and the player spawns 10.8 km from the centre, so the
camera is inside it throughout the inner system, and a ray starting inside a
sphere enters it at t = 0, which is in front of everything. Every landmark was
discarded from every vantage point that mattered, which the screenshots missed
because each of them had the camera parked out beside the landmark it was
checking.

Testing against the *shadow alone* fixed that and was still wrong, on the
reasoning that the disk is translucent and a landmark showing faintly through
its outer edge was a minor error. It is not minor: the disk is the brightest
object in the scene and covers far more sky than the shadow does, so a nebula
painted across it reads as a bug on sight.

`goliath_cover()` now handles both, and returns a fraction rather than a
yes/no so the disk's rim is a fade and not a cut-out:

- **Shadow**: a straight-line impact parameter under the critical
  3√3/2 rs is captured and never comes back out. Feathered over the last tenth
  of a radius so the edge is not a stair.
- **Disk**: solved as a ray/plane crossing in the hole's own frame rather than
  marched. One divide and a length: where the ray crosses y = 0, and whether
  that lands between the disk's inner and outer radii. Grazing crossings pass
  through more gas, so the coverage is weighted by the inverse of the ray's
  inclination, exactly how the disk's own integration weights its emission.

#### Tuning the remnant by measurement, not by eye

The first render was a full-screen white-out. Rather than iterate against a
four-minute render each time, the density function was reimplemented in Python
(same hash, same value noise, same fBm), and rays were integrated across the
image at three camera distances.

That exposed the metric the eye actually uses. The filament term is sampled on
**direction only**, so a feature stays constant all the way along a radius: that
is what makes it read as a finger of gas pointing at the star rather than a blob
floating in it, and it means the density barely varies along any one ray. The
contrast the eye reads as structure is *between neighbouring pixels*, so the
thing to measure is the spread of brightness across rays, not along one.

Solved profile at 4.3 km out: brightness at the 10th/50th/90th percentile of
0.33 / 0.81 / 1.35 and opacity 0.14 / 0.34 / 0.56. About four times the contrast
of the first attempt at a third of its brightness, and translucent enough that
stars read through most of it. The parameter that decided it was the filament
threshold: fBm has a mean near 0.47 and a deviation near 0.12, so subtracting
0.95 from 2.2× it leaves most directions empty and lets a minority through. That
is the difference between filaments and fog.

**Placement.** Both sit far outside the Goliath system: the remnant at 163 rs
(923 km) and the pulsar at 187 rs (1104 km). At that range they are landmarks
you navigate *to* rather than scenery you pass, which is why they are also sized
to stay legible from the spawn point: the remnant's gas is 9 km across and the
pulsar's beams reach 26 km, so they subtend 13° and 27° from the start position.

**Sizing is one number each.** `Globals.remnant_scale` and `pulsar_scale`
multiply the gas or beam reach, the star, the danger radius and the lethal
radius together, so a landmark stays in proportion with itself, and more
importantly, its hazard cannot be left behind by its appearance. Verified: at
2× the remnant's gas, danger and kill radii all double; at 0.5× the pulsar's
beams halve and its damaging cone halves with them, still biting at 0.4 of the
new reach and not at all past it. Gravity is a second slider each.

**`SupernovaRemnant`** is a Helix-style planetary nebula: two radial shells, a
flattened equatorial annulus, radial cometary knots, and a white dwarf at the
middle. Pull 2900 u/s², danger radius 19000, kill radius 690, generously larger
than the star itself, because at 1200 u/s the ship crosses 20 units a physics
tick and a kill radius tight to the surface would be a coin flip. Contact is
fatal; measured, the pull draws a coasting ship 309 units inward in 1.5 seconds
from halfway out.

**`Pulsar`** is an oblique rotator. The magnetic axis is tilted 32° from the spin
axis, so as the star turns the beams sweep out two cones; this is why real
pulsars pulse, and it is the whole mechanic. The march runs in the *magnetic*
frame, where the axis is +Y, so sweeping the beams costs one `mat4` upload a
frame and no per-fragment work at all.

`beam_half_angle` is handed to the shader and used by `beam_exposure` unchanged:
what you can see and what burns you cannot drift apart. At exactly that angle
the drawn beam is at 1/e of its axial brightness, so the damaging cone is the
bright core of what is drawn rather than its full visible extent. Measured:
7.83° half-angle, a fixed point on the cone lit for 43 of 480 ticks over two
rotations (8.9%, which is 2 × 15.7°/360°), 38 hull points per second on the
axis. That kills a standard hull in about two and a half seconds: long enough
to notice the alarm and turn out, short enough that parking in it is never an
option. It started at 62/s, which killed before the camera had finished shaking.

**What is still geometry: the magnetosphere.** A field line is a
line; a line mesh draws lines exactly. Marching a volume to recover a curve
would be slower and worse, and here it would not work at all: a field line a
few hundred units thick inside an eleven-kilometre volume is finer than any step
size that volume can afford, so the march would step straight over it. The lines
follow r = L sin²θ and carry a per-vertex fade with distance so the outer shells
thin out instead of stopping at their last vertex.

One non-obvious artefact: the per-pixel entry
dither that hides step banding becomes *visible stippling* along a beam as soon
as one step carries enough opacity to matter on its own. The fix was lower
extinction and more steps, not a different dither.

Both are drawn on the plan view with a **dashed** danger ring, so they never
read as one of Goliath's rings: those are concentric on the map's centre and
these are not, and the eye should not have to work that out. On the minimap they
pin to the rim with a chevron when out of range, the way Goliath does: knowing
the pulsar is off to port is useful at four times radar range.

### `boss/`: the dreadnought

An `'Oumuamua`-class shard 1750 units long: a little over seventeen kilometres
at this project's scale, and around a thousand times the length of the ship
flying at it. It is meant to be the largest thing in the game that is not a
star, and at the 640 it started at it read as a big asteroid rather than as a
vessel. The aspect ratio works out near 5.4:1, close to the 6:1 the real
object's light curve implied; anything stubbier reads as another asteroid at
the range it is first spotted from. Dark rock lit by 40 bioluminescent veins
that breathe on two beats at slightly different rates, so no two are ever quite
in phase.

It sits about 28 km **behind** the player's starting heading, so the opening
view is Goliath and the first thing you find by turning round is this. Its
direction from the spawn point carries a green nebula in
`starfield.gdshaderinc`, so it is first seen against a wall of its own colour
rather than against empty sky.

It is a `StaticBody3D` moved by hand rather than a `CharacterBody3D`: it drifts
at walking pace and never resolves a collision against anything (the player
bounces off it, not the other way round), and a static body is what the player's
hitscan rounds want on the far end of a raycast. It sits on layer 3 with the
interceptors, so `LaserCannon`'s existing `1|4` query finds it with no special
case.

**Turrets** own their aiming and cadence but not their ammunition: five turrets
with a bolt pool each would be five times the nodes for a rate of fire one pool
serves comfortably. A turret engages only when the player is on its own side of
the hull, tested against the mount normal, cheaper than a line-of-sight
raycast and the same question at this geometry, since the hull is convex.

Return fire is **not** hitscan. A hitscan turret either always
hits or randomly does not, and neither is something a pilot can answer; a bolt
with travel time can be seen coming and flown out of, and it means the turret
has to lead its shot, so jinking works for exactly the reason it looks like it
should.

A bolt does 7 damage into a 14-unit hit radius, both down about 20% from where
they started. At the old numbers a standing engagement at three kilometres ran
3–10 hull points a second depending on how the spread fell, and the top of that
range killed a Wasp in six seconds: pressure is the intent, a countdown is not.

That hit test has to be **swept**. Comparing the bolt's position each tick
against a hit radius silently never fires: at 5200 u/s a bolt covers 87 units
per physics step, so it steps clean over an 18-unit sphere. Measured, that cost
the turrets every shot they took past about a kilometre. It is now the closest
approach of the tick's segment to the player.

**Death** goes in stages. Something 640 units long detonating as a single sphere
looks like a bug (the eye has the hull's length for scale and a point explosion
contradicts it), so secondaries walk down the spine for 2.6 seconds, each at a
real point on the hull, and only then does the whole thing go. Worth 2500
points.

`ui/BossBar.gd` appears only inside the engagement range and fades out again,
for the same reason the scoreboard does.

### `environment/`: asteroids

`Asteroid.gd` builds rocks from a twice-subdivided icosphere (320 faces) pushed
around by layered value noise: low-frequency lobes for silhouette, a mid band
for facet relief, plus a per-axis squash so they are not potatoes of revolution.
Vertices are never shared between faces, so normals come out per-face and the
result is faceted rather than smooth. Four variants are built once and cached;
instances differ by variant, scale and orientation, which is enough variety for
hundreds of rocks at a fraction of a mesh each. The material is triplanar:
the icosphere's spherical UVs pinch at the poles and no seam fixing hides that
on a heavily deformed sphere.

`AsteroidField.gd` places them in an annulus whose inner edge sits *outside* the
gravity deadzone, with density peaking near the disk midplane. Count scales with
`Globals.asteroid_density`, and the field rebuilds only when that value actually
changes, so dragging any other slider costs nothing.

`DiskDebris.gd` fills the accretion disk with rocks on fixed circular tracks,
drawn through three `MultiMeshInstance3D` batches. Orbital radius is a constant
of each instance rather than the result of integrating gravity, so no amount of
drift or numerical error can walk one across the horizon: the disk stays
populated forever. They carry no collision: the disk is a hazard you fly
through, not a field you thread, and hundreds of moving colliders in the one
region the player is most likely to be would be both expensive and infuriating.

Collisions are handled in `Ship._move`: impact speed drives hull damage, a HUD
flash, and camera trauma; the ship slides off rather than stopping dead.

### `environment/`: Goliath

`Goliath.tscn` is three nodes:

- **Volume**: a `MeshInstance3D` carrying `Goliath.gdshader`. Everything you
  see comes out of that one fragment shader.
- **GravityWell**: the force source above. No visuals.
- **Goliath.gd**: the only script that knows about both. Its entire job is
  pushing `Globals` into the shader and keeping the gravity well's spin axis
  matched to the shader's `axis_tilt`.

`TestFlight.tscn` wires Goliath to the debug camera, a sky, and three reference
solids (see *Verifying the depth compositing* below).

## The shader

Ported from `../ga2/index2.html`: a Three.js + single-GLSL-fragment-shader
Gargantua renderer. The physics is unchanged: force-approximation geodesic
raymarch, ISCO disk with Keplerian-sheared fBm filaments, relativistic Doppler
beaming, photon ring by closest approach. See that project's `README.md` for
the derivations.

Three things differ, all forced by moving from a fullscreen quad into a 3D scene.

### 1. World-space volume instead of a fullscreen pass

The shader lives on an inverted bounding sphere centred on the hole
(`render_mode cull_front, depth_test_disabled, depth_draw_never,
blend_premul_alpha`), drawn in the transparent pass.

Rays are rebuilt from `INV_PROJECTION_MATRIX` / `INV_VIEW_MATRIX` rather than
from the mesh's own vertices, so they stay correct when the camera is *inside*
the volume and the near plane is slicing through it, which is why a volume was
chosen over a backdrop. Before marching, the ray is advanced
analytically to the sphere's entry point; outside it the path is a straight
line, and `cross(pos, dir)` is invariant along a line, so skipping ahead costs
the photon nothing.

### 2. Depth compositing

The shader samples `hint_depth_texture` and clamps the march to the nearest
already-drawn geometry. Three outcomes per pixel:

| Ray ends | Output colour | Alpha |
|---|---|---|
| Crosses the horizon | accumulated disk only | `1.0` (opaque black shadow) |
| Hits scene geometry | disk in front of it | accumulated (geometry shows through) |
| Escapes to the sky | disk + lensed backdrop | `1.0` |

Premultiplied-alpha blending makes all three fall out of one `vec4`.

**Known limitation:** only the procedural backdrop is lensed. Scene geometry
composites correctly by depth but is not bent: an asteroid passing behind the
hole is occluded by the shadow, but you will not see a warped image of it in the
Einstein ring. Doing that needs a screen-space fallback that breaks down at
large deflection angles. This is the standard tradeoff.

### 3. No tonemapping in the shader

The WebGL original ended with `acesFilm()` and a 1/2.2 gamma because it owned
the whole framebuffer. Here the shader emits **linear HDR** and
`WorldEnvironment` applies ACES globally, so the hole is graded like every other
object in the scene instead of being tonemapped twice.

### 4. A disk with thickness, and landing on it

The disk is a slab, not a plane. Two consequences:

- **Step limiting.** Inside the disk's radial band the march step is clamped by
  distance to the midplane, or a coarse step jumps through the slab and the disk
  vanishes at grazing angles.
- **Integrated emission.** Emission accumulates along the segment instead of
  being sampled once at a plane crossing: this is what makes flying *through*
  the disk fog the view rather than flick past a sheet of paper.

**The polar artefact.** The first version of the limiter engaged only once a
sample was already inside the slab. A ray sitting just outside it took a full
coarse step and could cross the whole disk in one go, contributing nothing.
Whether that happened depended on where the sampling lattice fell relative to
y = 0, and the lattice spacing is `dt = r * 0.12`, which, viewed down the spin
axis, is very nearly constant along each ray and varies with image radius. The
result was concentric rings of missing disk, with matching rings in the
background behind them, since the background is attenuated by whatever alpha the
disk accumulated. It only showed from steep angles because edge-on views cross
the slab at a shallow enough angle that the coarse step could not clear it.

The fix is to clamp the step so a ray outside the slab and closing on it lands
exactly on its surface, then sample finely from there. No ray can skip the disk
at any camera angle, and emission is continuous because sampling always begins
from the same surface. It is also **2.4x faster** from directly overhead
(55.9 → 23.7 ms), since rays no longer thrash at fine step sizes after entering
the slab at an arbitrary depth.

### 4b. The original thickness problem

The disk is a slab, not a plane. Two consequences:

- **Step limiting.** Inside the disk's radial band the march step is clamped by
  distance to the midplane, or a coarse step jumps clean through the slab and the
  disk vanishes at grazing angles. It keys off `abs(pos.y)`, so it costs nothing
  out in open space.
- **Integrated emission.** Emission accumulates along the segment instead of
  being sampled once at a plane crossing. This is what makes flying *through*
  the disk fog the view rather than flick past a sheet of paper.

Path length through a slab goes as `1 / sin(inclination)`,
so an unweighted integral makes grazing rays accumulate without bound and washes
the whole disk to flat white, which is exactly what the first attempt did.
Weighting each segment by the ray's inclination cancels that completely; a floor
of 0.6 on the weight lets grazing views keep up to ~1.7x extra glow, which is the
volumetric depth cue worth keeping. Brightness is normalised by the Gaussian's
vertical integral, so `disk_thickness_rs` changes the *shape* of the disk without
changing its face-on brightness.

### Shared backdrop, no seam

`starfield.gdshaderinc` holds the stars, nebulae, marker stars and comets. It is
`#include`d by **both** `Goliath.gdshader` (sampled along each photon's *lensed*
exit direction) and `GoliathSky.gdshader` (sampled along the plain view
direction, outside the volume).

They have to be the same code. Deflection is windowed to ~1e-5 by the volume's
boundary, so with a shared backdrop the transition is invisible; with two
different skies it would be a visible sphere edge.

## World scale

The shader works in natural units (rs = 1) internally, exactly like the original.
`Globals.bh_rs_world` is the only place the two scales meet.

| Quantity | Natural | World (default) |
|---|---|---|
| Event horizon | 1 rs | 500 u |
| ISCO / disk inner | 3 rs | 1 500 u |
| Disk outer edge | 17 rs | 8 500 u |
| Gravity deadzone edge | 8 rs | 4 000 u |
| Influence volume | 30.6 rs | 15 300 u |
| Ship | n/a | ~1 u |

1 unit ≈ 10 m. Camera `far` is 60 000; Forward+ reverse-Z depth handles that
range without precision trouble.

## The title backdrop

The menu shows the real Goliath scene rather than a still or a faked 2D hole, so
retuning the shader retunes the title screen. It was, however, paying the full
49 ms raymarch plus the 11 ms sky to sit behind a scrim and a column of buttons.

It now renders into a `SubViewport` inside a `SubViewportContainer` with
`stretch_shrink` between 6 and 2 depending on the quality level. Cost falls with
the square of the shrink factor (a shrink of 4 is 1/16 the pixels), and the
softness that buys is, behind a menu, atmosphere rather than a defect. Even at
quality 10 the backdrop renders at half resolution, because nothing on that
screen is worth a full-resolution raymarch.

## Settings persistence

`Globals.save_settings()` writes to `user://settings.cfg`: the tuning
properties listed in `_saved_properties()`, plus every binding in `BINDABLE` as
a physical keycode or mouse button index. `load_settings()` runs from
`Globals._ready()`, after the shipped defaults have been captured so
`reset_bindings()` has something to restore. Saving happens when the options
panel closes and when leaving a scene, not on every slider tick.

## Orbiting rather than falling

Two pieces make Goliath something you circle rather than something you drop into.

**Gravity has a tangential term.** `GravityWell` returns inward pull *and* a
frame-dragging component (`bh_spin_strength`), both ramping in past the deadzone.
Measured from rest at 5 rs, the ship reaches 1222 u/s tangential against 387 u/s
radial: it spirals.

**The disk drags you along with it.** `Ship`'s braking thrusters brake toward the
*local rest frame*, not toward zero. Out in open space that frame is stationary
and the assist behaves as it always did. Inside the accretion disk it is the
orbiting gas: `GravityWell.disk_flow_velocity()`, a Keplerian `v ∝ r^-1/2`
profile anchored at the ISCO and faded in by `disk_containment()` across both the
radial edges and the slab's vertical falloff. So turning into the flow and
releasing the throttle leaves you co-moving with the disk instead of stopping
dead in a torrent of infalling plasma. Measured: released at 10 rs, the ship held
520 → 516 u/s and swept 26 degrees of arc in five seconds with the radius stable
to 0.17 rs.

## The map and the minimap

`ui/MapScreen.gd` (toggled with `M`) is a plan view projected onto the disk
plane, because that is the plane the interesting radii live in and a perspective
view of a black hole tells you nothing about how close you are to dying in it.
Altitude is reported as a number rather than drawn, which is the honest way to
show it on a 2D plan. Every ring (horizon, point of no return, ISCO, gravity
deadzone, disk outer) is read live from `Globals` and `GravityWell`, so moving a
slider moves the map.

`ui/Minimap.gd` is a heading-up radar under the telemetry panel. Heading-up
rather than north-up because there is no north in a space sim: the only frame a
pilot can act on immediately is their own. Goliath is drawn to true scale within
the sweep and pinned to the rim with an arrow once it falls outside range.

Its rings (horizon, disk, deadzone) are **clipped to the bezel**. They are
drawn at true scale, and with the deadzone now at 13 rs at least one of them is
wider than the instrument at any useful radar range; as plain `draw_arc` calls
they simply ran off it and painted rings across the panel behind. Canvas drawing
has no circular clip, so the circle is walked as points and emitted as runs of
polyline that stay inside. Splitting into runs rather than clamping matters:
clamping an outside point to the rim would draw a false arc along the bezel,
which reads as another ring rather than as the absence of one.

`ui/ContactBar.gd` is a **bearing tape** across the top. A tape rather than a
list, because the question a pilot has is "which way do I turn", and a column of
coordinates does not answer it: each contact is placed by its bearing in the
ship's own frame, so a mark left of centre means turn left and how far left says
how much. Elevation is dropped rather than squeezed in: a two-axis reticle at
this size is unreadable, and the range under each mark carries the part that
matters. Contacts behind the ship pin to whichever end is the shorter way round,
with a chevron, because an off-scale mark that does not say which way to turn is
worse than no mark.

Two things about it were found by looking at it rather than by reasoning. The
first version used ◉ ✶ ◆ ▲ as icons; half of them do not exist in the fallback
font and came out as blanks, and the half that did were indistinguishable at
14px, so it uses words. And marks that share a bearing overlapped into
illegible mush, which out here happens constantly since the landmarks are fixed
and the player turns past them, so the layout sorts by position and pushes each
colliding mark to a second row.

`ui/CoordReadout.gd` puts the ship's world position bottom-left, small and
static. It answers a different question from the tape: the tape says which way
to turn, this says where you are, which is what you need to read back or check a
map against.

`ui/TargetMarkers.gd` hangs a downward chevron over every hostile. Screen space
rather than 3D sprites: a world-space marker either shrinks to nothing at these
distances or needs billboarding plus distance-compensating scale, and still ends
up occluded by the ship it is pointing at.

All three read hostiles straight off the `enemies` group rather than from
`EnemySpawner`. The spawner only knows about the hostiles it made; the
dreadnought's escorts are not among them, and a marker that skipped half the
hostiles on screen would be worse than no markers.

The plan view now fits the hazards and the dreadnought into its frame as well as
the disk and the player. It is a system map rather than a map of the hole: the
hazards are the reason to open it, so they have to be on it.

## Scoring

`Globals` carries `score` and `kills` for the session and emits `scored` on
every event; `ui/KillFeed.gd` turns that into a banner, a short list of recent
events, and a scoreboard that fades in on the first kill and back out a few
seconds after the last. The scoreboard is temporary: a permanently pinned score
panel is one more thing occupying the screen during the 95% of a flight where
nothing is being shot.

Score is **not** in `_saved_properties()`. A score belongs to a run, and a total
that silently resumes at whatever you had last time is worse than no score.

`environment/Effects.gd` pools `Explosion` instances and is found by group, so
anything that dies can detonate without the debug scenes needing to carry a
particle pool. Explosions are four layers (fireball, shockwave, sparks and a
light flash) because a single expanding sphere reads as a bubble, not a kill.

## Dying at the horizon

Crossing the horizon does not end the run immediately. `Ship._begin_terminal()`
hands the wreck to gravity for `Globals.horizon_death_delay` seconds: control is
gone at once (nothing you press matters past the horizon and pretending
otherwise would be a lie), but the fall is played out, with the tumble and the
camera shake building as the clock runs down. Only then does `destroyed` fire
and the panel appear.

One guard is needed: the tangential term in the well is strong enough down there
to sling the wreck back out past the horizon, which looks like the ship escaping
something nothing escapes. The terminal fall therefore holds its radius
monotonically decreasing.

## Navigating the dark

Inside the shadow there are no stars, no disk and no parallax, so "which way is
out" stops being answerable by looking: a real gameplay problem, not a polish
item. `EscapeCompass.gd` answers it directly:

- **Escape vector.** Radially outward is the only direction that increases your
  radius. Drawn as a chevron on the target when it is on screen, pinned to the
  screen rim pointing the way to turn when it is not.
- **Aperture ring.** The patch of sky you can still fly out through, drawn at its
  true angular size. A Schwarzschild shadow subtends
  `sin(theta) = b_c/r * sqrt(1-1/r)` with `b_c = 3*sqrt(3)/2 rs`, taking the
  obtuse branch inside the photon sphere; the sky is what is left, so it closes
  to a point at the horizon. The angle is printed on the escape arrow too,
  because when the way out is behind you the ring cannot be drawn at all, and
  that is precisely when the number matters most.
- **Horizon ring.** A dashed outline of the shadow, which is otherwise pure black
  against pure black. Useful at a distance as a target; skipped past ~70 degrees
  where the tangent projection stops being meaningful.
- **Prograde marker.** Where the ship is actually going, which under a
  semi-Newtonian model is regularly not where it is pointing.

Crossing the horizon is lethal rather than a hazard to fly out of: `Ship` checks
`GravityWell.inside_horizon()` each tick and destroys itself. Without that the
ship coasts around inside a black screen forever.

## Verifying the depth compositing

`TestFlight.tscn` parks three grey boxes: one between the camera and the hole,
one directly behind it, one inside the disk. If the depth clamp is working, the
near box occludes the disk, the far box is swallowed by the shadow, and the disk
cuts across the third. A plain fullscreen pass would hide all three.

Run it: `godot --path . res://environment/TestFlight.tscn`

`WASD` move · `SPACE`/`CTRL` up-down · `SHIFT` boost · `G` toggle gravity
(arcade ↔ Newtonian) · `ESC` release mouse.

## Controls (Expedition)

All of these are rebindable in Options → Controls.

| | |
|---|---|
| `W` `S` | main engine / reverse |
| `A` `D` | lateral thrust |
| `SPACE` `CTRL` | up / down thrust |
| `SHIFT` | afterburner |
| mouse | pitch / yaw |
| `X` `V` | roll left / right |
| LMB | fire lasers |
| `E` | target assist, steers the nose onto a hostile for a few seconds |
| `Q` | hold to charge the heavy beam, release to fire |
| `M` | plan view |
| wheel | zoom the chase camera; all the way in is a cockpit view |
| `R` | restart after a hull breach |
| `ESC` | back to the main menu (and from the menu, quit) |
| `TAB` | release the cursor without leaving |

## Performance

Measured with `RenderingServer.viewport_get_measured_render_time_gpu()` at
1920x1008 on Intel RPL-P integrated graphics, ship parked at 21.6 rs. Each row
below is the frame time with that one item *disabled*, so the difference from
the baseline is what it costs:

| Disabled | Frame | Its cost |
|---|---:|---:|
| none (baseline) | 64.9 ms | |
| Goliath raymarch volume | 15.6 ms | **49.4 ms (76%)** |
| Procedural sky shader | 54.2 ms | **10.7 ms (16%)** |
| Glow post-process | 63.2 ms | 1.8 ms |
| 160 asteroids | 64.8 ms | 0.2 ms |
| Ship mesh + materials | 65.1 ms | ~0 |
| HUD canvas | 64.9 ms | ~0 |
| Both raymarch and sky | 3.7 ms | |

Two shaders are 93% of the frame and everything else together is under 4 ms.
The ship's mesh, its metallic/rim material, the thruster light and all 160
asteroid meshes are, between them, below the noise floor, so there is nothing
to win by simplifying them, and they were left alone.

### What the landmarks cost

Measured the same way: interleaved A/B, minima taken, with the three landmark
nodes toggled `visible` between samples at 1280x720. Both columns are after the
rework to raymarched volumes:

| Camera | landmarks on | off | cost |
|---|---|---|---|
| spawn view, Goliath filling the frame | 21.45 ms | 21.32 ms | +0.13 ms |
| remnant at 9.6 km | 9.31 ms | 7.16 ms | +2.15 ms |
| inside the remnant | 18.34 ms | 5.59 ms | +12.75 ms |
| pulsar at 3.5 km | 4.98 ms | 4.13 ms | +0.85 ms |

Three things stand out from that table.

Anywhere near Goliath the landmarks are free: the frame is the hole's raymarch
and nothing else was ever going to matter.

The pulsar is nearly free everywhere, because there is no noise lookup anywhere
in its march: a beam is an angular falloff and a field line is a closed form.
That is why its volume can be three times the remnant's radius and cost a
sixth as much.

**Sitting inside the remnant is the expensive case.** It
first measured +25.7 ms of a 31.3 ms frame, essentially all of it two fBm
evaluations per step across a volume filling the screen. Three changes halved
it to +12.8 ms: an early-out that returns before sampling any noise when the
radial envelope is empty, one octave fewer on the filaments and two fewer on
the gate, and a step budget cut from a fifth of the hole's to a seventh. The
result is visually indistinguishable: dropping octaves does not change the
look because `fbm_gas()` normalises by its own amplitude sum, so the mean and
variance the filament threshold was solved against hold at any octave count.
Without that normalisation, turning the graphics slider down would not make the
nebula coarser, it would make it disappear.

### The quality slider

Because there are only two things worth tuning, there is only one slider:
`Globals.quality_level`, 1–10, which drives all of them together.

| Level | Render scale | Steps | Sky detail | Glow | Frame |
|---|---|---|---|---|---:|
| 1 | 0.40 | 60 | stars only | off | 6.4 ms (156 fps) |
| 3 | 0.53 | 93 | + nebula | off | 11.6 ms (86 fps) |
| 5 | 0.67 | 127 | + clouds | on | 27.1 ms (37 fps) |
| 6 (default) | 0.73 | 143 | + clouds | on | 31.4 ms (32 fps) |
| 8 | 0.87 | 177 | full | on | 48.4 ms (21 fps) |
| 10 | 1.00 | 210 | full | on | 75.3 ms (13 fps) |

Resolution is the dominant term: the raymarch is very nearly linear in pixel
count. Step budget is a weak lever on its own, because the loop is not
step-bound: most rays break early on escape, saturation or occlusion. Sky detail
drops fBm octaves and then whole features (comets, then nebula clouds), and is
felt twice, since the backdrop is evaluated both on background pixels and again
for every photon that escapes the raymarch.

### A measurement that did not work out

`disk_color()` is the expensive call inside the march (five octaves of
anisotropic fBm plus a dust-lane sample, well over a hundred hashes), and the
volumetric disk calls it several times per slab crossing. Since it depends on
radius and angle but not height, caching it across a crossing looks like free
money.

Measured interleaved, taking minima over four rounds to defeat thermal drift:
**cache on 76.6 ms, cache off 68.1 ms**. It is 12% *slower*. A branch does not
skip work for a GPU warp in which any lane still needs the recompute, so the
cost is paid anyway and you add divergence and live registers on top. The cache
was reverted and the finding left as a comment in the shader so nobody
re-derives it.

### Measuring this yourself

Do **not** use `--write-movie` for timing. Its reported "GPU render time" is
dominated by frame readback and encoding: it reports a *simpler* scene as
slower and shows quality settings having no effect at all. Use the
RenderingServer timer, and interleave A/B configurations within a single
process: this machine's frame times drift upward by 40% or more across a long
run as the GPU throttles, which is larger than most effects worth measuring.

This is integrated graphics with no discrete GPU in the machine; a dedicated
card should be several times faster.

## Where this goes next

Weapons and enemies are the next module. The hooks are already in place:
`Globals.enemy_spawn_rate` / `max_enemies` are wired to the options panel but
nothing consumes them, and the hangar's LASER POWER bar reads NOT FITTED rather
than inventing a number.
