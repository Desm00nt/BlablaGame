extends Node3D

## Phase 3 world generator.
##
## Everything is placed with MultiMeshInstance3D and every mesh is built
## procedurally at load time - no textures, no imported models.
##
## Heights come from TerrainNoise, which is the CPU mirror of the fbm in
## shaders/terrain.gdshader, so props sit exactly on the surface the GPU
## displaces the terrain to.
##
## HARD BUDGET (2 GB VRAM target):
##   grass 1650 + flowers 3x117 + trees 50 + rocks 30 = 2081 MultiMesh
##   instances, against a project ceiling of 3000. main.gd asserts this at
##   startup, so raising the exports below without raising the ceiling fails
##   loudly instead of silently.

const MAX_MULTIMESH_INSTANCES: int = 3000

@export var grass_count: int = 1650
@export var flower_count_per_color: int = 117
@export var tree_count: int = 50
@export var rock_count: int = 30
@export var seed_value: int = 20260826
@export var visibility_end_grass: float = 55.0
@export var visibility_end_props: float = 80.0
## Props are bucketed into chunk_grid x chunk_grid cells (50 m at 4) so that
## visibility_range_end and frustum culling actually have something to work on.
@export var chunk_grid: int = 4

const FLOWER_COLORS: Array = [
	Color(1.00, 0.82, 0.22),
	Color(0.95, 0.95, 0.98),
	Color(0.95, 0.45, 0.62),
]

var rng := RandomNumberGenerator.new()
var _total_instances: int = 0
var _chunks: int = 0
var _collision_faces: int = 0
var _tree_colliders: int = 0


func _ready() -> void:
	rng.seed = seed_value
	var t0 := Time.get_ticks_msec()
	_build_terrain_collision()
	var t1 := Time.get_ticks_msec()
	_build_grass()
	_build_flowers()
	_build_trees()
	_build_rocks()
	var t2 := Time.get_ticks_msec()
	# GDScript has no implicit string-literal concatenation, so the two parts are
	# joined with an explicit +. The concatenation is parenthesised because %
	# binds tighter than +, and without it the format would apply to the second
	# literal alone.
	print(("[WorldGenerator] collision %d faces in %d ms | %d MultiMesh instances in %d chunks "
			+ "in %d ms (seed %d)")
			% [_collision_faces, t1 - t0, _total_instances, _chunks, t2 - t1, seed_value])


# --- terrain collision -------------------------------------------------------

## Builds the walkable surface straight out of the terrain mesh's own vertices,
## so collision and visuals agree exactly at any subdivide value. A plain box
## collider would leave the player floating metres above the displaced ground.
func _build_terrain_collision() -> void:
	var mesh_node := get_node_or_null(^"../Terrain") as MeshInstance3D
	if mesh_node == null or mesh_node.mesh == null:
		push_error("[WorldGenerator] ../Terrain MeshInstance3D not found - no collision built")
		return
	# get_mesh_arrays() is a PrimitiveMesh method; MeshInstance3D.mesh is typed as
	# Mesh, so the cast is required for GDScript's static check to accept it.
	var primitive := mesh_node.mesh as PrimitiveMesh
	if primitive == null:
		push_error("[WorldGenerator] ../Terrain mesh is not a PrimitiveMesh - no collision built")
		return
	var src: Array = primitive.get_mesh_arrays()
	var raw_verts = src[Mesh.ARRAY_VERTEX]
	if raw_verts == null:
		push_error("[WorldGenerator] terrain mesh has no vertex data")
		return
	var verts: PackedVector3Array = (raw_verts as PackedVector3Array).duplicate()
	for i in verts.size():
		var v: Vector3 = verts[i]
		v.y = TerrainNoise.terrain_height(Vector2(v.x, v.z))
		verts[i] = v

	var faces := PackedVector3Array()
	var raw_index = src[Mesh.ARRAY_INDEX]
	if raw_index != null:
		var idx: PackedInt32Array = raw_index
		if idx.size() >= 3:
			for t in range(0, idx.size() - 2, 3):
				faces.push_back(verts[idx[t]])
				faces.push_back(verts[idx[t + 1]])
				faces.push_back(verts[idx[t + 2]])
	if faces.is_empty():
		faces = verts
	if faces.size() < 3:
		push_error("[WorldGenerator] could not build a terrain collision mesh")
		return

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var col := CollisionShape3D.new()
	col.name = "TerrainCollisionShape"
	col.shape = shape
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.add_child(col)
	# WorldGenerator._ready() runs while the parent (Main) is still setting
	# up its children, so a plain add_child() here is rejected with "Parent
	# node is busy setting up children" and the terrain collision would
	# silently never enter the tree - the player would fall through the
	# world. Deferring runs it right after setup, before the first physics
	# tick can move the player.
	get_parent().add_child.call_deferred(body)
	_collision_faces = faces.size() / 3


## One StaticBody3D holding a cylinder per trunk. WorldGenerator is already
## inside the tree by the time this runs (only its PARENT is still setting
## up), so a plain add_child on self is safe here.
func _build_tree_collision(positions: Array[Vector3], radii: Array) -> void:
	if positions.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "TreesBody"
	body.collision_layer = 1
	body.collision_mask = 0
	for i in positions.size():
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = float(radii[i])
		cyl.height = 3.0
		col.shape = cyl
		col.position = Vector3(positions[i].x, positions[i].y + 1.5, positions[i].z)
		body.add_child(col)
	add_child(body)
	_tree_colliders = positions.size()


# --- prop meshes -------------------------------------------------------------

## Appends one quad twice (front and back) with matching normals, so blades read
## correctly from both sides without relying on backface normal flipping.
func _push_quad(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		idx: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		vcols: Array, n: Vector3) -> void:
	var base := verts.size()
	verts.push_back(a)
	verts.push_back(b)
	verts.push_back(c)
	verts.push_back(d)
	for i in 4:
		norms.push_back(n)
		cols.push_back(vcols[i])
	idx.push_back(base)
	idx.push_back(base + 1)
	idx.push_back(base + 2)
	idx.push_back(base)
	idx.push_back(base + 2)
	idx.push_back(base + 3)
	# Back face: reversed winding, negated normal, colours follow the corners.
	base = verts.size()
	verts.push_back(a)
	verts.push_back(d)
	verts.push_back(c)
	verts.push_back(b)
	var bn := -n
	for i in 4:
		norms.push_back(bn)
	cols.push_back(vcols[0])
	cols.push_back(vcols[3])
	cols.push_back(vcols[2])
	cols.push_back(vcols[1])
	idx.push_back(base)
	idx.push_back(base + 1)
	idx.push_back(base + 2)
	idx.push_back(base)
	idx.push_back(base + 2)
	idx.push_back(base + 3)


func _make_tuft_mesh(flower_color: Color) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var base_col := Color(0.40, 0.50, 0.32)
	var tip_col := Color(1.0, 1.0, 1.0)
	for b in 3:
		var ang := TAU * float(b) / 3.0 + 0.37
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var w := 0.055
		var hgt := 0.32 + 0.14 * float((b + 1) % 3)
		var a := -side * w
		var bq := side * w
		var c := side * (w * 0.22) + dir * 0.11 + Vector3(0.0, hgt, 0.0)
		var d := -side * (w * 0.22) + dir * 0.11 + Vector3(0.0, hgt, 0.0)
		_push_quad(verts, norms, cols, idx, a, bq, c, d,
				[base_col, base_col, tip_col, tip_col], side.normalized())
	if flower_color.a > 0.0:
		# A small upright cross at the tip of the tuft.
		var cy := Vector3(0.0, 0.54, 0.0)
		var s := 0.075
		for b in 2:
			var ang := TAU * float(b) / 2.0 + 0.2
			var side := Vector3(-sin(ang), 0.0, cos(ang))
			var p0 := cy - side * s - Vector3.UP * s
			var p1 := cy + side * s - Vector3.UP * s
			var p2 := cy + side * s + Vector3.UP * s
			var p3 := cy - side * s + Vector3.UP * s
			_push_quad(verts, norms, cols, idx, p0, p1, p2, p3,
					[flower_color, flower_color, flower_color, flower_color], side)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _make_foliage_material())
	return am


func _add_primitive_surface(am: ArrayMesh, prim: PrimitiveMesh, xform: Transform3D, mat: Material) -> void:
	var a: Array = prim.get_mesh_arrays()
	var raw_v = a[Mesh.ARRAY_VERTEX]
	var raw_n = a[Mesh.ARRAY_NORMAL]
	if raw_v == null:
		return
	var verts: PackedVector3Array = (raw_v as PackedVector3Array).duplicate()
	var norms: PackedVector3Array = (raw_n as PackedVector3Array).duplicate() if raw_n != null else PackedVector3Array()
	var normal_basis := xform.basis.inverse().transposed()
	for i in verts.size():
		verts[i] = xform * verts[i]
		if i < norms.size():
			norms[i] = (normal_basis * norms[i]).normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if norms.size() == verts.size():
		arrays[Mesh.ARRAY_NORMAL] = norms
	var raw_i = a[Mesh.ARRAY_INDEX]
	if raw_i != null:
		var idx: PackedInt32Array = raw_i
		if idx.size() >= 3:
			arrays[Mesh.ARRAY_INDEX] = idx
	var surface_index := am.get_surface_count()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(surface_index, mat)


func _make_conifer_mesh(trunk_mat: Material, leaf_mat: Material) -> ArrayMesh:
	var am := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.13
	trunk.bottom_radius = 0.22
	trunk.height = 2.6
	trunk.radial_segments = 6
	trunk.rings = 1
	_add_primitive_surface(am, trunk, Transform3D(Basis(), Vector3(0.0, 1.3, 0.0)), trunk_mat)
	var tiers := [[1.55, 2.5, 2.4], [1.20, 2.1, 3.7], [0.85, 1.7, 4.9]]
	for tier in tiers:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = float(tier[0])
		cone.height = float(tier[1])
		cone.radial_segments = 8
		cone.rings = 1
		_add_primitive_surface(am, cone, Transform3D(Basis(), Vector3(0.0, float(tier[2]), 0.0)), leaf_mat)
	return am


func _make_broadleaf_mesh(trunk_mat: Material, leaf_mat: Material) -> ArrayMesh:
	var am := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.17
	trunk.bottom_radius = 0.30
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 1
	_add_primitive_surface(am, trunk, Transform3D(Basis(), Vector3(0.0, 1.5, 0.0)), trunk_mat)
	var crown := SphereMesh.new()
	crown.radius = 1.9
	crown.height = 3.8
	crown.radial_segments = 10
	crown.rings = 6
	_add_primitive_surface(am, crown, Transform3D(Basis(), Vector3(0.0, 4.4, 0.0)), leaf_mat)
	var crown2 := SphereMesh.new()
	crown2.radius = 1.25
	crown2.height = 2.5
	crown2.radial_segments = 8
	crown2.rings = 5
	_add_primitive_surface(am, crown2, Transform3D(Basis(), Vector3(0.9, 3.4, 0.5)), leaf_mat)
	return am


func _make_rock_mesh(mat: Material) -> ArrayMesh:
	var src := SphereMesh.new()
	src.radius = 0.6
	src.height = 1.2
	src.radial_segments = 7
	src.rings = 5
	var a: Array = src.get_mesh_arrays()
	var verts: PackedVector3Array = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var norms: PackedVector3Array = (a[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	for i in verts.size():
		var v: Vector3 = verts[i]
		# Radial jitter reuses the same value noise as the terrain.
		var d := TerrainNoise.value_noise(Vector2(v.x * 6.0 + 11.0, v.z * 6.0 - v.y * 4.0 + 5.0))
		verts[i] = v * (0.70 + d * 0.62)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var raw_i = a[Mesh.ARRAY_INDEX]
	if raw_i != null:
		var idx: PackedInt32Array = raw_i
		if idx.size() >= 3:
			arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, mat)
	return am


# --- materials ---------------------------------------------------------------

func _make_foliage_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.92
	mat.metallic = 0.0
	return mat


func _make_solid_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.roughness = roughness
	mat.metallic = 0.0
	return mat


# --- placement ---------------------------------------------------------------

## Rejection-samples valid spots. Returns world positions on the terrain.
func _scatter(count: int, min_water_clearance: float, max_height: float, max_slope: float) -> Array:
	var out := []
	var half := 95.0
	var attempts := count * 40
	var guard := 0
	while out.size() < count and guard < attempts:
		guard += 1
		var p := Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		var h := TerrainNoise.terrain_height(p)
		if h < TerrainNoise.WATER_LEVEL + min_water_clearance or h > max_height:
			continue
		if max_slope < 1.0 and TerrainNoise.slope_at(p) > max_slope:
			continue
		out.append(Vector3(p.x, h, p.y))
	if out.size() < count:
		push_warning("[WorldGenerator] placed only %d/%d - terrain rules rejected too many samples"
				% [out.size(), count])
	return out


func _add_multimesh(mesh: Mesh, spots: Array, visibility_end: float, cast_shadows: bool,
			min_scale: float, max_scale: float, tint_spread: float, base_name: String,
			collision_out_pos: Array,
			collision_out_rad: Array) -> void:
	if spots.is_empty():
		return
	# visibility_range_* is measured against the node's AABB, not per instance.
	# One MultiMesh spanning the whole 200 m world would therefore never be
	# culled, so the spots are bucketed into chunk_grid x chunk_grid cells first.
	var cell := 200.0 / float(maxi(chunk_grid, 1))
	var buckets := {}
	for p in spots:
		var cx := clampi(int((p.x + 100.0) / cell), 0, chunk_grid - 1)
		var cz := clampi(int((p.z + 100.0) / cell), 0, chunk_grid - 1)
		var key := Vector2i(cx, cz)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(p)
	for key in buckets:
		_create_chunk(mesh, buckets[key], visibility_end, cast_shadows,
				min_scale, max_scale, tint_spread, "%s_%d_%d" % [base_name, key.x, key.y],
					collision_out_pos, collision_out_rad)


func _create_chunk(mesh: Mesh, spots: Array, visibility_end: float, cast_shadows: bool,
			min_scale: float, max_scale: float, tint_spread: float, node_name: String,
			collision_out_pos: Array,
			collision_out_rad: Array) -> void:
	if _total_instances + spots.size() > MAX_MULTIMESH_INSTANCES:
		push_error("[WorldGenerator] instance budget exceeded at %s (%d + %d > %d)"
				% [node_name, _total_instances, spots.size(), MAX_MULTIMESH_INSTANCES])
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var pos: Vector3 = spots[i]
		var s := rng.randf_range(min_scale, max_scale)
		# Slight per-axis variation so nothing looks stamped out.
		var scl := Vector3(s * rng.randf_range(0.88, 1.12), s, s * rng.randf_range(0.88, 1.12))
		var rot := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		# Sink slightly: the CPU and GPU height fields agree to ~1e-5 m, but this
		# also hides the base of each mesh so nothing appears to float.
		var sink := 0.06 * s
		mm.set_instance_transform(i, Transform3D(rot * Basis.from_scale(scl), pos - Vector3(0.0, sink, 0.0)))
		var v := rng.randf_range(1.0 - tint_spread, 1.0 + tint_spread)
		mm.set_instance_color(i, Color(v, v, v))
		if collision_out_pos != null and collision_out_rad != null:
			# Trunk collider uses the exact same placement as the visual
			# instance, so the hitbox never disagrees with the picture.
			collision_out_pos.append(pos - Vector3(0.0, sink, 0.0))
			collision_out_rad.append(clampf(0.34 * maxf(scl.x, scl.z), 0.2, 0.5))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mmi.visibility_range_end = visibility_end
	add_child(mmi)
	_total_instances += spots.size()
	_chunks += 1


# --- builders ----------------------------------------------------------------

func _build_grass() -> void:
	var spots := _scatter(grass_count, 0.4, TerrainNoise.GRASS_LINE, 0.35)
	_add_multimesh(_make_tuft_mesh(Color(0, 0, 0, 0)), spots, visibility_end_grass, false,
			0.75, 1.35, 0.16, "Grass", [], [])


func _build_flowers() -> void:
	for c in FLOWER_COLORS.size():
		var spots := _scatter(flower_count_per_color, 0.7, 6.0, 0.22)
		_add_multimesh(_make_tuft_mesh(FLOWER_COLORS[c]), spots, visibility_end_grass, false,
				0.80, 1.20, 0.10, "Flowers_%d" % c, [], [])


func _build_trees() -> void:
	var trunk_mat := _make_solid_material(Color(0.30, 0.20, 0.12), 0.95)
	var conifer_mat := _make_solid_material(Color(0.11, 0.26, 0.13), 0.88)
	var broad_mat := _make_solid_material(Color(0.19, 0.38, 0.15), 0.85)
	var half := tree_count / 2
	# Both builders append into the same collision arrays, so all trunks end
	# up in ONE StaticBody3D - 50 shapes, not 50 bodies.
	var trunk_pos: Array[Vector3] = []
	var trunk_rad: Array = []
	_add_multimesh(_make_conifer_mesh(trunk_mat, conifer_mat),
			_scatter(half, 1.0, TerrainNoise.ROCK_LINE, 0.40), visibility_end_props, true,
			0.75, 1.35, 0.14, "TreesConifer", trunk_pos, trunk_rad)
	_add_multimesh(_make_broadleaf_mesh(trunk_mat, broad_mat),
			_scatter(tree_count - half, 1.0, TerrainNoise.ROCK_LINE, 0.40), visibility_end_props, true,
			0.75, 1.30, 0.18, "TreesBroadleaf", trunk_pos, trunk_rad)
	_build_tree_collision(trunk_pos, trunk_rad)


func _build_rocks() -> void:
	_add_multimesh(_make_rock_mesh(_make_solid_material(Color(0.44, 0.43, 0.42), 0.96)),
			_scatter(rock_count, 0.3, 999.0, 2.0), visibility_end_props, true,
			0.60, 2.20, 0.12, "Rocks", [], [])
