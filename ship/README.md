# `ship/`

The player vessel.

- `Ship.tscn` / `Ship.gd` — `CharacterBody3D` with the semi-Newtonian flight
  assist: continuous braking thrusters with a capped authority that loses to
  Goliath close in. Full pitch/yaw/roll, hull integrity, thruster heat, and
  collision damage.
- `ChaseCamera.gd` — `top_level` smoothed chase camera, trauma shake, FOV
  distortion on approach.
- `ShipMesh.gd` — generates the hull geometry and its collision hull.

Design notes, including why this is not a `RigidBody3D` and how the brake time
constant produces the point of no return, are in
`docs/core_architecture.md` under *`ship/` — the flight model*.
