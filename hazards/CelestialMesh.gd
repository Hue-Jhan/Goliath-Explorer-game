class_name CelestialMesh
extends RefCounted
## Procedural geometry for the deep-space landmarks.
##
## Same reasoning as [ShipMesh] -- the project has no asset pipeline, and a
## checked-in .glb would be an opaque blob nobody can tune. Every dimension
## below is a number you can edit and re-run.
##
## What is [i]not[/i] here any more is as informative as what is. The remnant's
## gas rings, its instanced knots and the pulsar's beam cones all used to live
## in this file, and all three have been replaced by raymarched volumes. They
## shared one failure: a mesh has a silhouette and gas does not, so they could
## be made to read correctly from one distance and one angle at a time and never
## from all of them. What survives here is the things that genuinely are
## surfaces and curves -- a hull, a star, a field line.

## A smooth sphere. Used for stars and glows, where faceting would be wrong.
static func uv_sphere(radius: float, rings: int = 12, segments: int = 20) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in rings:
		var phi0 := PI * float(ring) / float(rings)
		var phi1 := PI * float(ring + 1) / float(rings)
		for seg in segments:
			var th0 := TAU * float(seg) / float(segments)
			var th1 := TAU * float(seg + 1) / float(segments)
			_quad(st,
				_spherical(radius, phi0, th0), _spherical(radius, phi1, th0),
				_spherical(radius, phi1, th1), _spherical(radius, phi0, th1),
				Vector3.ZERO)
	st.generate_normals()
	return st.commit()


## Dipole magnetic field lines around the local +Y axis, as a line mesh.
##
## Each line follows r = L sin^2(theta), the standard dipole field line, so the
## family closes on the poles and bulges at the equator the way a magnetosphere
## actually does. Lines rather than tubes because at the distances a pulsar is
## seen from a tube would be sub-pixel anyway and cost fifty times the vertices
## -- and because this is the one part of the pulsar that a raymarch cannot do:
## a field line a few hundred units thick inside an eleven-kilometre volume is
## finer than any step size that volume can afford, so a march would step
## straight over it.
##
## Vertex alpha fades with distance from the star over [param fade_extent], so
## the outer shells thin out instead of stopping dead at their last vertex.
static func dipole_lines(shells: Array, azimuths: int, samples: int = 34, fade_extent: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var fade: float = fade_extent if fade_extent > 0.0 else 0.0
	for shell in shells:
		var l_shell: float = shell
		for k in azimuths:
			var az := TAU * float(k) / float(azimuths)
			var radial := Vector3(cos(az), 0.0, sin(az))
			var previous := Vector3.ZERO
			for s in samples + 1:
				# Endpoints are nudged off the poles, where r collapses to 0.
				var theta := lerpf(0.10, PI - 0.10, float(s) / float(samples))
				var r := l_shell * sin(theta) * sin(theta)
				var point := radial * (r * sin(theta)) + Vector3.UP * (r * cos(theta))
				if s > 0:
					_line_vertex(st, previous, fade)
					_line_vertex(st, point, fade)
				previous = point
	return st.commit()


## The 'Oumuamua-class hull: an elongated shard, lofted from irregular rings.
##
## Aspect ratio is the whole silhouette, and [param girth] is a half-width, so
## the hull comes out around 5.4:1 -- close to the 6:1 the real 'Oumuamua's
## light curve implied. Anything stubbier reads as another asteroid at the range
## it is first spotted from.
static func shard(length: float, girth: float, seed_value: int = 1337) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stations := 14
	var rings: Array[PackedVector3Array] = []
	for i in stations:
		var t := float(i) / float(stations - 1)
		var z := lerpf(-length * 0.5, length * 0.5, t)
		# Fat amidships, tapered to blunt points: sin gives the spindle, the
		# rng gives the rock.
		var profile := pow(sin(t * PI), 0.62)
		var ring := PackedVector3Array()
		for k in 7:
			var a := TAU * float(k) / 7.0
			var jitter := rng.randf_range(0.68, 1.28)
			ring.append(Vector3(
				cos(a) * girth * profile * jitter,
				sin(a) * girth * profile * jitter * 0.72,
				z))
		rings.append(ring)

	_fan_to(st, Vector3(0.0, 0.0, -length * 0.54), rings[0])
	for i in stations - 1:
		_loft(st, rings[i], rings[i + 1])
	_fan_to(st, Vector3(0.0, 0.0, length * 0.54), rings[stations - 1])
	st.generate_normals()
	return st.commit()


## Collision proxy for that hull. A capsule, not the mesh: the shard is convex
## enough that the difference is invisible in flight, and the player's rounds
## are raycast anyway.
static func shard_shape(length: float, girth: float) -> Shape3D:
	var shape := CapsuleShape3D.new()
	shape.radius = girth * 0.86
	shape.height = length
	return shape


# --- materials ----------------------------------------------------------------

## Unshaded additive emissive: the workhorse for glows, veins and field lines.
static func glow_material(tint: Color, energy: float, alpha: float = 0.5) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = energy
	mat.disable_receive_shadows = true
	# Must not write depth, or overlapping glows would occlude each other and
	# the accumulation that makes additive blending read as volume would be lost.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


## Dark, dusty rock. The shard's hull and its turrets.
static func rock_material(tint: Color, roughness: float = 0.92) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = roughness
	mat.metallic = 0.08
	mat.rim_enabled = true
	mat.rim = 0.35
	return mat


# --- primitives ---------------------------------------------------------------

static func _spherical(radius: float, phi: float, theta: float) -> Vector3:
	return Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radius


static func _line_vertex(st: SurfaceTool, at: Vector3, fade_extent: float) -> void:
	var a := 1.0
	if fade_extent > 0.0:
		a = clampf(1.0 - at.length() / fade_extent, 0.0, 1.0)
		a = a * a
	st.set_color(Color(1.0, 1.0, 1.0, a))
	st.add_vertex(at)


## Winding chosen so the face points away from [param interior], the same trick
## [ShipMesh] uses: orientation cannot come out inverted if it is derived rather
## than asserted.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, interior: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - interior) < 0.0:
		var swap := b
		b = c
		c = swap
	for v in [a, b, c]:
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, interior: Vector3) -> void:
	_tri(st, a, b, c, interior)
	_tri(st, a, c, d, interior)


static func _fan_to(st: SurfaceTool, tip: Vector3, ring: PackedVector3Array) -> void:
	var interior := Vector3(0.0, 0.0, tip.z * 0.5)
	for i in ring.size():
		_tri(st, tip, ring[i], ring[(i + 1) % ring.size()], interior)


static func _loft(st: SurfaceTool, a: PackedVector3Array, b: PackedVector3Array) -> void:
	var interior := Vector3(0.0, 0.0, (a[0].z + b[0].z) * 0.5)
	for i in a.size():
		var j := (i + 1) % a.size()
		_tri(st, a[i], a[j], b[j], interior)
		_tri(st, a[i], b[j], b[i], interior)
