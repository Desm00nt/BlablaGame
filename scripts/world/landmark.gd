class_name Landmark
extends Node3D

## Story landmarks built from primitives, one node per location:
##   "camp"    - the wrecked caravan the hero wakes in (scorch, burnt tents,
##               fire pit, bodies, the note pickup, the campfire echo)
##   "village" - Каменный Брод: huts, fence, banner, a fire and Ингвар
##   "barrow"  - Аш-Вейл: burial mound, stone door, runestones, the black
##               echo stone (plus colliders for mound/door)
##
## The node sits at ground level (y = terrain height); everything is local.
## One OmniLight per fire with a cheap two-sine flicker; shadows off on
## lights, on for the geometry.

var kind: String = "camp"
var quest_manager: QuestManager = null

var fire_pos: Vector3 = Vector3.ZERO      # local campfire position
var stone_pos: Vector3 = Vector3.ZERO     # local echo-stone position (barrow)
var npc: StoryNPC = null
var echo_point: EchoPoint = null

var _t: float = 0.0
var _flicker_light: OmniLight3D = null
var _flicker_base: float = 1.6
var _rune_mat: StandardMaterial3D = null


func _ready() -> void:
	match kind:
		"camp":
			_build_camp()
		"village":
			_build_village()
		"barrow":
			_build_barrow()
		_:
			push_error("[Landmark] unknown kind '%s'" % kind)


func _process(delta: float) -> void:
	_t += delta
	if _flicker_light != null:
		_flicker_light.light_energy = _flicker_base * (0.86 + 0.10 * sin(_t * 11.0) \
				+ 0.06 * sin(_t * 23.7))
	if _rune_mat != null:
		_rune_mat.emission_energy_multiplier = 1.2 + 0.5 * sin(_t * 1.7)


# --- shared builders ---------------------------------------------------------

func _mat(color: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, sz: Vector3, m: Material, pos: Vector3,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, top: float, bottom: float, h: int, seg: int, m: Material,
		pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = float(h)
	mesh.radial_segments = seg
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Fire pit: stone ring, crossed logs, ember core, flickering light.
func _build_fire(pos: Vector3, light_range: float) -> void:
	var stone := _mat(Color(0.30, 0.29, 0.28), 0.95)
	var log_mat := _mat(Color(0.22, 0.15, 0.09), 0.95)
	var ring := Node3D.new()
	ring.name = "FirePit"
	ring.position = pos
	add_child(ring)
	for i in 7:
		var ang := TAU * float(i) / 7.0
		var r := 0.62 + fmod(float(i) * 0.618, 0.1)
		var s := 0.24 + fmod(float(i) * 0.377, 0.1)
		_box(ring, Vector3(s, 0.18, s * 0.8), stone,
				Vector3(cos(ang) * r, 0.09, sin(ang) * r),
				Vector3(0.0, rad_to_deg(ang), randf_range(-4.0, 4.0)))
	for i in 3:
		var ang2 := TAU * float(i) / 3.0 + 0.4
		_cyl(ring, 0.055, 0.07, 1, 7, log_mat,
				Vector3(cos(ang2) * 0.1, 0.10, sin(ang2) * 0.1),
				Vector3(88.0, rad_to_deg(ang2), 0.0))
	var embers := _cyl(ring, 0.24, 0.28, 1, 9, null, Vector3(0.0, 0.06, 0.0))
	var ember_mat := _mat(Color(0.95, 0.42, 0.10), 0.7)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.45, 0.12)
	ember_mat.emission_energy_multiplier = 2.4
	embers.material_override = ember_mat

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.30)
	light.light_energy = _flicker_base
	light.omni_range = light_range
	light.shadow_enabled = false
	light.position = pos + Vector3(0.0, 0.55, 0.0)
	add_child(light)
	_flicker_light = light
	fire_pos = pos


func _add_collider(shape_owner: StaticBody3D, shape: Shape3D, pos: Vector3,
		scale_v: Vector3 = Vector3.ONE) -> void:
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	col.scale = scale_v
	shape_owner.add_child(col)


func _static_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	return body


# --- camp --------------------------------------------------------------------

func _build_camp() -> void:
	var scorch := _cyl(self, 3.4, 3.6, 1, 14, null, Vector3(0.0, 0.02, 0.0))
	var scorch_mat := _mat(Color(0.10, 0.09, 0.08), 1.0)
	scorch.material_override = scorch_mat

	_build_fire(Vector3(0.0, 0.0, 0.0), 7.0)

	var charred := _mat(Color(0.16, 0.13, 0.10), 0.95)
	var cloth := _mat(Color(0.23, 0.19, 0.15), 0.95)
	# Burnt tent (still standing) and a collapsed one.
	_box(self, Vector3(0.06, 1.7, 0.06), charred, Vector3(-3.0, 0.85, -1.2))
	var tent := PrismMesh.new()
	tent.size = Vector3(2.3, 1.7, 2.6)
	var tent_mi := MeshInstance3D.new()
	tent_mi.mesh = tent
	tent_mi.material_override = cloth
	tent_mi.position = Vector3(-3.2, 0.72, -1.0)
	tent_mi.rotation_degrees = Vector3(0.0, 14.0, 0.0)
	add_child(tent_mi)
	var tent2 := MeshInstance3D.new()
	tent2.mesh = tent
	tent2.material_override = cloth
	tent2.position = Vector3(2.9, 0.25, -2.2)
	tent2.rotation_degrees = Vector3(-64.0, 28.0, 12.0)
	add_child(tent2)

	var wood := _mat(Color(0.34, 0.25, 0.15), 0.9)
	_box(self, Vector3(0.52, 0.5, 0.52), wood, Vector3(1.6, 0.25, 1.2), Vector3(0.0, 18.0, 0.0))
	_box(self, Vector3(0.52, 0.5, 0.52), wood, Vector3(1.65, 0.75, 1.25), Vector3(0.0, -9.0, 3.0))
	_box(self, Vector3(0.48, 0.46, 0.48), wood, Vector3(-1.5, 0.23, 1.7), Vector3(0.0, 33.0, 0.0))
	_cyl(self, 0.28, 0.32, 1, 10, wood, Vector3(-2.6, 0.35, 0.6))

	# The fallen. Grey rigs, frozen mid-fall.
	for i in 4:
		var body := Node3D.new()
		body.position = Vector3(-1.8 + float(i) * 1.35, 0.0, -2.6 + fmod(float(i) * 1.9, 3.2))
		add_child(body)
		var rig := CharacterRig.new()
		rig.palette_tunic = Color(0.30, 0.27, 0.24)
		rig.palette_armor = Color(0.36, 0.34, 0.30)
		rig.palette_skin = Color(0.55, 0.46, 0.38)
		rig.palette_leather = Color(0.22, 0.18, 0.14)
		rig.palette_cape = Color(0.20, 0.16, 0.13)
		body.add_child(rig)
		body.rotation.y = fmod(float(i) * 2.399, TAU)
		rig.set_dead(1.0)
	
	# The echo anchor at the fire.
	echo_point = EchoPoint.new()
	echo_point.echo_id = "campfire"
	echo_point.quest_id = "ash"
	echo_point.expected_stage = 0
	echo_point.position = Vector3(0.0, 0.0, 0.0)
	add_child(echo_point)

	# The note on the crate.
	var note := PickupItem.new()
	note.item_id = "caravan_note"
	note.position = Vector3(1.6, 0.78, 1.2)
	add_child(note)


# --- village -----------------------------------------------------------------

func _build_village() -> void:
	var wall := _mat(Color(0.36, 0.28, 0.19), 0.9)
	var plank := _mat(Color(0.30, 0.23, 0.15), 0.92)
	var straw := _mat(Color(0.52, 0.44, 0.24), 0.95)
	var stone := _mat(Color(0.38, 0.37, 0.36), 0.95)

	var hut_defs := [
		[Vector3(-4.5, 0.0, -3.0), 24.0],
		[Vector3(4.2, 0.0, -3.6), -18.0],
		[Vector3(0.6, 0.0, -6.8), 8.0],
	]
	for hd in hut_defs:
		var pos: Vector3 = hd[0]
		var ang: float = float(hd[1])
		var hut := Node3D.new()
		hut.position = pos
		hut.rotation.y = deg_to_rad(ang)
		add_child(hut)
		_box(hut, Vector3(2.8, 2.1, 2.4), wall, Vector3(0.0, 1.05, 0.0))
		var roof := PrismMesh.new()
		roof.size = Vector3(3.3, 1.3, 3.0)
		var roof_mi := MeshInstance3D.new()
		roof_mi.mesh = roof
		roof_mi.material_override = straw
		roof_mi.position = Vector3(0.0, 2.75, 0.0)
		hut.add_child(roof_mi)
		_box(hut, Vector3(0.8, 1.5, 0.08), plank, Vector3(0.0, 0.75, 1.22))
		_box(hut, Vector3(0.5, 0.5, 0.08), stone, Vector3(-0.9, 1.2, 1.22))

	_build_fire(Vector3(0.0, 0.0, 0.5), 8.0)

	# Fence arc along the road side (+Z).
	for i in 7:
		var x := -6.3 + float(i) * 2.1
		_box(self, Vector3(0.14, 1.05, 0.14), plank, Vector3(x, 0.52, 4.6),
				Vector3(0.0, fmod(float(i) * 1.7, 3.0) - 1.5, 0.0))
	_box(self, Vector3(14.6, 0.10, 0.10), plank, Vector3(0.0, 0.86, 4.6))
	_box(self, Vector3(14.6, 0.10, 0.10), plank, Vector3(0.0, 0.45, 4.6))

	# Banner of the brod.
	_cyl(self, 0.05, 0.07, 1, 8, plank, Vector3(6.8, 1.7, 3.2))
	var flag := _box(self, Vector3(0.05, 0.8, 0.55),
			_mat(Color(0.24, 0.30, 0.42), 0.9), Vector3(6.8, 2.9, 3.5))
	flag.rotation_degrees = Vector3(0.0, 0.0, 4.0)

	# Ингвар Мудрый by the fire.
	npc = StoryNPC.new()
	npc.name = "Ingvar"
	npc.npc_name = "Ингвар Мудрый"
	npc.position = Vector3(-1.4, 0.0, 2.0)
	npc.rotation.y = PI * 0.75
	add_child(npc)
	npc.setup_rig({
		"tunic": Color(0.28, 0.26, 0.36),
		"armor": Color(0.50, 0.48, 0.44),
		"skin": Color(0.76, 0.62, 0.50),
		"leather": Color(0.26, 0.20, 0.14),
		"cape": Color(0.22, 0.20, 0.30),
		"eyes": Color(0.12, 0.12, 0.14),
	})


# --- barrow ------------------------------------------------------------------

func _build_barrow() -> void:
	var mound_mat := _mat(Color(0.24, 0.30, 0.20), 0.98)
	var mound := SphereMesh.new()
	mound.radius = 7.0
	mound.height = 10.0
	mound.radial_segments = 20
	mound.rings = 10
	var mi := MeshInstance3D.new()
	mi.mesh = mound
	mi.material_override = mound_mat
	mi.position = Vector3(0.0, -2.0, 0.0)
	add_child(mi)

	var door_mat := _mat(Color(0.20, 0.20, 0.21), 0.9)
	var door := _box(self, Vector3(2.4, 3.2, 0.5), door_mat, Vector3(0.0, 1.5, 6.1),
			Vector3(-6.0, 0.0, 0.0))
	door.name = "BarrowDoor"
	_box(self, Vector3(3.0, 0.45, 0.7), door_mat, Vector3(0.0, 3.35, 6.15))
	_box(self, Vector3(0.5, 3.4, 0.6), door_mat, Vector3(-1.5, 1.6, 6.2))
	_box(self, Vector3(0.5, 3.4, 0.6), door_mat, Vector3(1.5, 1.6, 6.2))

	var rune_stone := _mat(Color(0.36, 0.36, 0.37), 0.95)
	for i in 6:
		var ang := -1.15 + 2.3 * float(i) / 5.0
		var x := sin(ang) * 7.6
		var z := cos(ang) * 7.6
		_box(self, Vector3(0.5, 1.7, 0.32), rune_stone,
				Vector3(x, 0.75, z),
				Vector3(fmod(float(i) * 2.7, 8.0) - 4.0, rad_to_deg(-ang), 0.0))

	# The black echo stone: obsidian slab with a pulsing cold seam.
	var black := _mat(Color(0.06, 0.06, 0.08), 0.55)
	_box(self, Vector3(0.95, 1.35, 0.6), black, Vector3(2.2, 0.67, 6.9),
			Vector3(0.0, -24.0, 0.0))
	_rune_mat = _mat(Color(0.5, 0.68, 1.0), 0.4)
	_rune_mat.emission_enabled = true
	_rune_mat.emission = Color(0.45, 0.65, 1.0)
	_box(self, Vector3(0.10, 1.05, 0.03), _rune_mat, Vector3(2.2, 0.7, 6.62),
			Vector3(0.0, -24.0, 0.0))
	stone_pos = Vector3(2.2, 0.0, 6.9)

	echo_point = EchoPoint.new()
	echo_point.echo_id = "barrow_stone"
	echo_point.quest_id = "barrow"
	echo_point.expected_stage = 1
	echo_point.position = stone_pos
	add_child(echo_point)

	# Colliders: squashed sphere for the mound, box for the door.
	var body := _static_body()
	var sphere := SphereShape3D.new()
	sphere.radius = 6.9
	_add_collider(body, sphere, Vector3(0.0, 0.1, 0.0), Vector3(1.0, 0.52, 1.0))
	var door_shape := BoxShape3D.new()
	door_shape.size = Vector3(2.4, 3.2, 0.5)
	_add_collider(body, door_shape, Vector3(0.0, 1.5, 6.1))
	var jamb := BoxShape3D.new()
	jamb.size = Vector3(0.5, 3.4, 0.6)
	_add_collider(body, jamb, Vector3(-1.5, 1.6, 6.2))
	_add_collider(body, jamb, Vector3(1.5, 1.6, 6.2))
