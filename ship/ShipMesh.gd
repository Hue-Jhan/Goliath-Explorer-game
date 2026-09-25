class_name ShipMesh
extends RefCounted
## Builds the player hull as an [ArrayMesh] at load time.
##
## Generated rather than authored because the project has no asset pipeline yet
## and a checked-in .glb would be an opaque blob nobody can tune. Every
## dimension below is a number you can edit and re-run.
##
## Faceted on purpose: vertices are never shared between triangles, so
## [method SurfaceTool.generate_normals] produces one normal per face and the
## hull reads low-poly without any smoothing groups.
##
## The ship points down local -Z, matching Godot's camera convention, so
## [code]-basis.z[/code] is "forward" everywhere in the flight code.

const HEX := 6


## Full hull: fuselage, canopy, clean swept wings, twin nacelles.
static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- fuselage: a tapered hexagonal spine from nose to tail ---------------
	var nose := Vector3(0.0, 0.0, -1.42)
	var ring_a := _ring(0.15, 0.11, -0.74)
	var ring_b := _ring(0.36, 0.23, 0.10)
	var ring_c := _ring(0.29, 0.18, 0.84)
	_fan(st, nose, ring_a)
	_loft(st, ring_a, ring_b)
	_loft(st, ring_b, ring_c)
	_cap(st, ring_c)

	# --- canopy: a faceted wedge sitting on the spine ------------------------
	_canopy(st)

	# --- wings: clean swept delta plates, mirrored ---------------------------
	_wing(st, 1.0)
	_wing(st, -1.0)

	# --- nacelles: octagonal tubes flanking the tail -------------------------
	_nacelle(st, Vector3(0.44, -0.02, 0.62))
	_nacelle(st, Vector3(-0.44, -0.02, 0.62))

	st.generate_normals()
	return st.commit()


## Scout hull: a needle. Long fine nose, narrow spine, a single big engine and
## thin wings raked hard back — it should read as "fast and fragile" before the
## player has seen a single stat.
static func build_scout() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var nose := Vector3(0.0, 0.0, -1.85)
	var fore := _ring(0.10, 0.08, -0.95)
	var waist := _ring(0.23, 0.18, -0.02)
	var tail := _ring(0.19, 0.15, 0.88)
	_fan(st, nose, fore)
	_loft(st, fore, waist)
	_loft(st, waist, tail)
	_cap(st, tail)

	# One central engine instead of a pair.
	_nacelle(st, Vector3(0.0, -0.04, 0.60))

	# Thin wings, low on the hull and swept almost to the tail.
	for side: float in [1.0, -1.0]:
		var th := 0.028
		var tip := 1.22 * side
		_hexa(st, [
			Vector3(0.18 * side, th, 0.02), Vector3(tip, th * 0.5, 0.62),
			Vector3(tip, th * 0.5, 0.86), Vector3(0.18 * side, th, 0.94),
			Vector3(0.18 * side, -th, 0.02), Vector3(tip, -th * 0.5, 0.62),
			Vector3(tip, -th * 0.5, 0.86), Vector3(0.18 * side, -th, 0.94),
		])
		# Forward canards, small, for the interceptor silhouette.
		_hexa(st, [
			Vector3(0.12 * side, 0.02, -1.02), Vector3(0.48 * side, 0.02, -0.74),
			Vector3(0.48 * side, 0.02, -0.58), Vector3(0.12 * side, 0.02, -0.66),
			Vector3(0.12 * side, -0.02, -1.02), Vector3(0.48 * side, -0.02, -0.74),
			Vector3(0.48 * side, -0.02, -0.58), Vector3(0.12 * side, -0.02, -0.66),
		])

	_canopy_at(st, -0.30, 0.9)
	st.generate_normals()
	return st.commit()


static func build_scout_shape() -> Shape3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(0.0, 0.0, -1.85),
		Vector3(0.23, 0.20, -0.02), Vector3(-0.23, 0.20, -0.02),
		Vector3(0.23, -0.20, -0.02), Vector3(-0.23, -0.20, -0.02),
		Vector3(0.19, 0.16, 0.95), Vector3(-0.19, 0.16, 0.95),
		Vector3(0.19, -0.16, 0.95), Vector3(-0.19, -0.16, 0.95),
		Vector3(1.22, 0.03, 0.74), Vector3(-1.22, 0.03, 0.74),
		Vector3(0.48, 0.03, -0.66), Vector3(-0.48, 0.03, -0.66),
	])
	return shape


## Heavy hull: a brick. Wide blunt prow, deep body, four stubby nacelles and
## clipped wings. Slow, and it looks it.
static func build_heavy() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var prow := _ring(0.30, 0.24, -1.15)
	var fore := _ring(0.46, 0.34, -0.70)
	var waist := _ring(0.58, 0.42, 0.10)
	var tail := _ring(0.50, 0.36, 0.92)
	_fan(st, Vector3(0.0, 0.0, -1.48), prow)
	_loft(st, prow, fore)
	_loft(st, fore, waist)
	_loft(st, waist, tail)
	_cap(st, tail)

	# Armoured prow plate, squared off against the round spine.
	_hexa(st, [
		Vector3(0.34, 0.20, -1.30), Vector3(0.34, 0.20, -0.62),
		Vector3(-0.34, 0.20, -0.62), Vector3(-0.34, 0.20, -1.30),
		Vector3(0.34, -0.20, -1.30), Vector3(0.34, -0.20, -0.62),
		Vector3(-0.34, -0.20, -0.62), Vector3(-0.34, -0.20, -1.30),
	])

	# Four stubby engines rather than two.
	for sx: float in [0.66, -0.66]:
		for sy: float in [0.24, -0.24]:
			_nacelle(st, Vector3(sx, sy, 0.66))

	# Clipped wings: short, deep, no rake.
	for side: float in [1.0, -1.0]:
		var th := 0.085
		_hexa(st, [
			Vector3(0.50 * side, th, -0.20), Vector3(1.12 * side, th * 0.7, 0.04),
			Vector3(1.12 * side, th * 0.7, 0.72), Vector3(0.50 * side, th, 0.88),
			Vector3(0.50 * side, -th, -0.20), Vector3(1.12 * side, -th * 0.7, 0.04),
			Vector3(1.12 * side, -th * 0.7, 0.72), Vector3(0.50 * side, -th, 0.88),
		])

	_canopy_at(st, -0.55, 1.25)
	st.generate_normals()
	return st.commit()


static func build_heavy_shape() -> Shape3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(0.0, 0.0, -1.48),
		Vector3(0.58, 0.44, 0.10), Vector3(-0.58, 0.44, 0.10),
		Vector3(0.58, -0.44, 0.10), Vector3(-0.58, -0.44, 0.10),
		Vector3(0.50, 0.38, 1.10), Vector3(-0.50, 0.38, 1.10),
		Vector3(0.50, -0.38, 1.10), Vector3(-0.50, -0.38, 1.10),
		Vector3(1.12, 0.09, 0.40), Vector3(-1.12, 0.09, 0.40),
		Vector3(0.34, 0.22, -1.30), Vector3(-0.34, 0.22, -1.30),
	])
	return shape


## Canopy wedge, parameterised so every hull can carry one at its own station.
static func _canopy_at(st: SurfaceTool, z: float, width: float) -> void:
	var w := 0.15 * width
	var fw := 0.08 * width
	var bl := Vector3(-w, 0.09 * width, z + 0.14)
	var br := Vector3(w, 0.09 * width, z + 0.14)
	var fl := Vector3(-fw, 0.06 * width, z - 0.48)
	var fr := Vector3(fw, 0.06 * width, z - 0.48)
	var tl := Vector3(-0.10 * width, 0.26 * width, z + 0.08)
	var tr := Vector3(0.10 * width, 0.26 * width, z + 0.08)
	var tip := Vector3(0.0, 0.14 * width, z - 0.50)
	var interior := Vector3(0.0, 0.14 * width, z - 0.10)
	_tri_out(st, tl, tr, tip, interior)
	_tri_out(st, bl, tl, tip, interior)
	_tri_out(st, bl, tip, fl, interior)
	_tri_out(st, br, tip, tr, interior)
	_tri_out(st, br, fr, tip, interior)
	_tri_out(st, bl, br, tr, interior)
	_tri_out(st, bl, tr, tl, interior)


## A hostile interceptor: smaller, sharper, and deliberately unlike the player
## hull so the two read apart instantly at distance and on the map.
## [param size] is baked into the vertices rather than applied as node scale.
## Scaling a CharacterBody3D scales its basis vectors too, and anything that
## then uses -basis.z as a thrust direction silently multiplies its engines by
## the scale factor -- which is exactly what happened here, and made hostiles
## 4.5x faster than intended.
static func build_interceptor(size: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var nose := Vector3(0.0, 0.0, -1.15) * size
	var fore := _ring(0.16 * size, 0.13 * size, -0.42 * size)
	var waist := _ring(0.26 * size, 0.20 * size, 0.18 * size)
	var tail := _ring(0.17 * size, 0.14 * size, 0.72 * size)
	_fan(st, nose, fore)
	_loft(st, fore, waist)
	_loft(st, waist, tail)
	_cap(st, tail)

	# Two dorsal-canted fins rather than wings, so the silhouette is a dart.
	for side: float in [1.0, -1.0]:
		var th := 0.035 * size
		var lift := 0.34 * size
		_hexa(st, [
			Vector3(0.14 * side, th, -0.10) * size, Vector3(0.78 * side * size, th + lift, 0.46 * size),
			Vector3(0.78 * side * size, th + lift, 0.70 * size), Vector3(0.14 * side * size, th, 0.76 * size),
			Vector3(0.14 * side * size, -th, -0.10 * size), Vector3(0.78 * side * size, -th + lift, 0.46 * size),
			Vector3(0.78 * side * size, -th + lift, 0.70 * size), Vector3(0.14 * side * size, -th, 0.76 * size),
		])

	st.generate_normals()
	return st.commit()


## Convex collision proxy for the interceptor.
##
## Deliberately 20% tighter than the hull it stands in for. A proxy that
## enclosed the mesh made a hostile easier to hit than it looked -- the fins
## alone are 1.6 units across at the standard size, and a raycast clipping the
## empty air between them still counted. Shrinking it means the crosshair has to
## be on the body, which is the only part a pilot is actually aiming at.
const HITBOX_SCALE := 0.80

static func build_interceptor_shape(size: float = 1.0) -> Shape3D:
	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array([
		Vector3(0.0, 0.0, -1.15),
		Vector3(0.26, 0.22, 0.18), Vector3(-0.26, 0.22, 0.18),
		Vector3(0.26, -0.22, 0.18), Vector3(-0.26, -0.22, 0.18),
		Vector3(0.17, 0.14, 0.76), Vector3(-0.17, 0.14, 0.76),
		Vector3(0.17, -0.14, 0.76), Vector3(-0.17, -0.14, 0.76),
		Vector3(0.78, 0.40, 0.58), Vector3(-0.78, 0.40, 0.58),
	])
	for i in pts.size():
		pts[i] = pts[i] * size * HITBOX_SCALE
	shape.points = pts
	return shape


## The glowing disc at the back of one engine bell. Separate mesh so it can
## carry an unshaded emissive material without a second hull surface.
static func build_engine_glow(radius: float = 0.155) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3.ZERO
	var rim := PackedVector3Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		rim.append(Vector3(cos(a) * radius, sin(a) * radius, 0.0))
	for i in 8:
		var b := rim[i]
		var c := rim[(i + 1) % 8]
		# Faces the +Z side (astern); the interior reference sits in front of it.
		_tri_out(st, centre, b, c, Vector3(0.0, 0.0, -1.0))
	st.generate_normals()
	return st.commit()


## Convex collision proxy for the whole ship.
static func build_collision_shape() -> Shape3D:
	var pts := PackedVector3Array([
		Vector3(0.0, 0.0, -1.42),
		Vector3(0.36, 0.26, 0.10), Vector3(-0.36, 0.26, 0.10),
		Vector3(0.36, -0.24, 0.10), Vector3(-0.36, -0.24, 0.10),
		Vector3(0.30, 0.19, 0.95), Vector3(-0.30, 0.19, 0.95),
		Vector3(0.30, -0.19, 0.95), Vector3(-0.30, -0.19, 0.95),
		Vector3(1.18, 0.02, 0.62), Vector3(-1.18, 0.02, 0.62),
		Vector3(1.18, 0.02, 0.80), Vector3(-1.18, 0.02, 0.80),
		Vector3(0.0, 0.30, -0.30),
	])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


# --- primitives ---------------------------------------------------------------

static func _ring(half_width: float, half_height: float, z: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in HEX:
		var a := TAU * float(i) / float(HEX)
		pts.append(Vector3(cos(a) * half_width, sin(a) * half_height, z))
	return pts


## Adds a triangle, choosing the winding that makes its normal point away from
## [param interior]. Godot front-faces are clockwise; rather than reason about
## that per part, every face is oriented against a point known to be inside the
## solid, which cannot come out inverted.
static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, interior: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var centroid := (a + b + c) / 3.0
	if n.dot(centroid - interior) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_uv(Vector2(v.x + v.z, v.y + v.z) * 0.5)
		st.add_vertex(v)


static func _fan(st: SurfaceTool, tip: Vector3, ring: PackedVector3Array) -> void:
	var interior := Vector3(0.0, 0.0, (tip.z + ring[0].z) * 0.5)
	for i in ring.size():
		_tri_out(st, tip, ring[i], ring[(i + 1) % ring.size()], interior)


static func _loft(st: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array) -> void:
	var interior := Vector3(0.0, 0.0, (a[0].z + b[0].z) * 0.5)
	for i in a.size():
		var j := (i + 1) % a.size()
		_tri_out(st, a[i], a[j], b[j], interior)
		_tri_out(st, a[i], b[j], b[i], interior)


static func _cap(st: SurfaceTool, ring: PackedVector3Array) -> void:
	var centre := Vector3(0.0, 0.0, ring[0].z)
	var interior := centre - Vector3(0.0, 0.0, 0.4)
	for i in ring.size():
		_tri_out(st, centre, ring[i], ring[(i + 1) % ring.size()], interior)


## A convex box-ish solid from 8 corners, oriented outward from its own centre.
static func _hexa(st: SurfaceTool, c: Array) -> void:
	var interior := Vector3.ZERO
	for v in c:
		interior += v
	interior /= float(c.size())
	var faces := [
		[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1],
		[1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0],
	]
	for f in faces:
		_tri_out(st, c[f[0]], c[f[1]], c[f[2]], interior)
		_tri_out(st, c[f[0]], c[f[2]], c[f[3]], interior)


static func _canopy(st: SurfaceTool) -> void:
	# Base sits slightly inside the spine so there is no z-fighting seam.
	var bl := Vector3(-0.15, 0.09, -0.16)
	var br := Vector3(0.15, 0.09, -0.16)
	var fl := Vector3(-0.08, 0.06, -0.78)
	var fr := Vector3(0.08, 0.06, -0.78)
	var tl := Vector3(-0.10, 0.26, -0.22)
	var tr := Vector3(0.10, 0.26, -0.22)
	var tip := Vector3(0.0, 0.14, -0.80)
	var interior := Vector3(0.0, 0.14, -0.40)
	_tri_out(st, tl, tr, tip, interior)          # canopy glass, front slope
	_tri_out(st, bl, tl, tip, interior)
	_tri_out(st, bl, tip, fl, interior)
	_tri_out(st, br, tip, tr, interior)
	_tri_out(st, br, fr, tip, interior)
	_tri_out(st, bl, br, tr, interior)           # rear face
	_tri_out(st, bl, tr, tl, interior)


static func _wing(st: SurfaceTool, side: float) -> void:
	var th := 0.045
	var root_f := 0.32 * side
	var tip_x := 1.18 * side
	# Swept delta: leading edge rakes back as it goes outboard.
	var c := [
		Vector3(root_f, th, -0.28), Vector3(tip_x, th * 0.4, 0.44),
		Vector3(tip_x, th * 0.4, 0.80), Vector3(root_f, th, 0.86),
		Vector3(root_f, -th, -0.28), Vector3(tip_x, -th * 0.4, 0.44),
		Vector3(tip_x, -th * 0.4, 0.80), Vector3(root_f, -th, 0.86),
	]
	_hexa(st, c)


static func _nacelle(st: SurfaceTool, centre: Vector3) -> void:
	var front := PackedVector3Array()
	var waist := PackedVector3Array()
	var back := PackedVector3Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector3(cos(a), sin(a), 0.0)
		front.append(centre + d * 0.10 + Vector3(0, 0, -0.52))
		waist.append(centre + d * 0.19 + Vector3(0, 0, -0.10))
		back.append(centre + d * 0.17 + Vector3(0, 0, 0.42))
	_loft(st, front, waist)
	_loft(st, waist, back)
	# Nose cone of the nacelle.
	var tip := centre + Vector3(0, 0, -0.66)
	_fan(st, tip, front)
	# Engine bell rim: capped, the glow quad is parented separately.
	_cap(st, back)
	# Pylon joining it to the spine.
	var inboard := signf(centre.x) * -0.09
	var c := [
		centre + Vector3(inboard, 0.05, -0.20), centre + Vector3(-centre.x * 0.62, 0.07, -0.16),
		centre + Vector3(-centre.x * 0.62, 0.07, 0.20), centre + Vector3(inboard, 0.05, 0.24),
		centre + Vector3(inboard, -0.05, -0.20), centre + Vector3(-centre.x * 0.62, -0.07, -0.16),
		centre + Vector3(-centre.x * 0.62, -0.07, 0.20), centre + Vector3(inboard, -0.05, 0.24),
	]
	_hexa(st, c)
