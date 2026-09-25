class_name Asteroid
extends StaticBody3D
## One procedurally deformed rock.
##
## Geometry is a subdivided icosphere pushed around by layered value noise:
## a few low-frequency lobes give each rock a distinct lumpy silhouette, a
## mid band adds facet-scale relief, and a per-axis squash keeps them from
## reading as potatoes-of-revolution. Vertices are never shared between faces,
## so normals come out per-face and the result is faceted rather than smooth.
##
## Four variants are built once and cached; instances differ by variant, scale
## and orientation, which is enough variety for a field of hundreds at a small
## fraction of the cost of a mesh each.

const VARIANTS := 4
## Awarded for breaking one up.
const POINTS := 15

## Deformation as a fraction of the base radius. Above ~0.45 the hull starts
## self-intersecting on the concave lobes.
const DEFORM := 0.34

static var _mesh_cache: Array[ArrayMesh] = []
static var _shape_cache: Array[ConvexPolygonShape3D] = []
static var _material: StandardMaterial3D = null

## Raised when the rock is shot apart, so the field can drop it from its list.
signal destroyed(rock: Asteroid)

## Which of the [constant VARIANTS] shapes to use. Negative picks at random.
@export var variant: int = -1
## Radius in world units before deformation. ~1 unit is 10 m.
@export var radius: float = 18.0
## Radians per second of idle tumble, applied by [AsteroidField].
@export var spin: Vector3 = Vector3.ZERO
## Hit points per world unit of radius. A pebble goes in a couple of shots, a
## landmark takes sustained fire -- size on screen is the only cue the player
## has for how long something will take, so it had better be the thing that
## decides.
@export var toughness: float = 1.6

var health: float = 0.0

@onready var _mesh_instance: MeshInstance3D = $Mesh
@onready var _collider: CollisionShape3D = $Body


func _ready() -> void:
	if variant < 0:
		variant = randi() % VARIANTS
	variant = variant % VARIANTS
	_mesh_instance.mesh = mesh_for(variant)
	_mesh_instance.material_override = material()
	_collider.shape = shape_for(variant)
	scale = Vector3.ONE * radius
	health = maxf(radius * toughness, 14.0)


## Lasers call this. Asteroids do not flinch visibly -- the impact flash the
## cannon spawns at the hit point is the feedback -- they just break when the
## accumulated damage runs the rock out of hit points.
func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		Effects.burst(self, global_position, radius * 1.8, Color(1.0, 0.72, 0.30))
		Globals.add_score(POINTS, "ASTEROID SHATTERED")
		destroyed.emit(self)
		queue_free()


## Remaining integrity, 0..1.
func integrity() -> float:
	return clampf(health / maxf(radius * toughness, 14.0), 0.0, 1.0)


static func material() -> StandardMaterial3D:
	if _material != null:
		return _material
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.022
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.3

	var bump := NoiseTexture2D.new()
	bump.noise = noise
	bump.width = 512
	bump.height = 512
	bump.seamless = true
	bump.as_normal_map = true
	bump.bump_strength = 12.0

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.31, 0.28, 0.26)
	_material.roughness = 0.94
	_material.metallic = 0.04
	_material.normal_enabled = true
	_material.normal_texture = bump
	_material.normal_scale = 1.5
	# Triplanar: the icosphere's spherical UVs pinch at the poles, and no amount
	# of seam fixing hides that on a heavily deformed sphere. Projecting from
	# local space instead is both cheaper to author and artefact-free.
	_material.uv1_triplanar = true
	_material.uv1_scale = Vector3(3.4, 3.4, 3.4)
	return _material


static func mesh_for(variant_index: int) -> ArrayMesh:
	_ensure_built()
	return _mesh_cache[variant_index % VARIANTS]


static func shape_for(variant_index: int) -> ConvexPolygonShape3D:
	_ensure_built()
	return _shape_cache[variant_index % VARIANTS]


static func _ensure_built() -> void:
	if not _mesh_cache.is_empty():
		return
	for i in VARIANTS:
		var mesh := _build(i * 977 + 13)
		_mesh_cache.append(mesh)
		_shape_cache.append(mesh.create_convex_shape(true, true))


static func _build(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var lobes := FastNoiseLite.new()
	lobes.noise_type = FastNoiseLite.TYPE_SIMPLEX
	lobes.seed = seed_value
	lobes.frequency = 0.55

	var relief := FastNoiseLite.new()
	relief.noise_type = FastNoiseLite.TYPE_SIMPLEX
	relief.seed = seed_value + 71
	relief.frequency = 1.9
	relief.fractal_octaves = 3

	# Per-axis squash, so silhouettes differ even before the noise lands.
	var squash := Vector3(
		rng.randf_range(0.72, 1.12),
		rng.randf_range(0.66, 1.05),
		rng.randf_range(0.78, 1.15))

	var sphere := _icosphere(2)
	var verts: PackedVector3Array = sphere[0]
	var idx: PackedInt32Array = sphere[1]

	var displaced := PackedVector3Array()
	displaced.resize(verts.size())
	for i in verts.size():
		var d := verts[i]
		var h := lobes.get_noise_3dv(d * 3.0) * 0.72 + relief.get_noise_3dv(d * 3.0) * 0.28
		displaced[i] = d * (1.0 + h * DEFORM) * squash

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := 0
	while tri < idx.size():
		# Unique vertices per face -> generate_normals() gives flat shading.
		for k in 3:
			st.add_vertex(displaced[idx[tri + k]])
		tri += 3
	st.generate_normals()
	return st.commit()


# --- icosphere ----------------------------------------------------------------

## Returns [vertices (unit sphere), indices] for an icosahedron subdivided
## [param subdivisions] times. 2 gives 320 faces, which is the sweet spot for a
## faceted rock: enough to carve a silhouette, few enough to read as low-poly.
static func _icosphere(subdivisions: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	])
	for i in verts.size():
		verts[i] = verts[i].normalized()

	var idx := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])

	for _s in subdivisions:
		var next := PackedInt32Array()
		var midpoints := {}
		var i := 0
		while i < idx.size():
			var a := idx[i]
			var b := idx[i + 1]
			var c := idx[i + 2]
			var ab := _midpoint(verts, midpoints, a, b)
			var bc := _midpoint(verts, midpoints, b, c)
			var ca := _midpoint(verts, midpoints, c, a)
			next.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
			i += 3
		idx = next

	return [verts, idx]


static func _midpoint(verts: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var key := (mini(a, b) << 16) | maxi(a, b)
	if cache.has(key):
		return cache[key]
	var m := ((verts[a] + verts[b]) * 0.5).normalized()
	verts.append(m)
	var index := verts.size() - 1
	cache[key] = index
	return index
