class_name SwordItem
extends Node3D

## A steel sword lying in the world. It spins slowly, bobs and pulses so it
## reads as an interactive item. The player picks it up with the interact
## action; the same model builder is reused for the copy attached to the
## player's hand, so the world item and the equipped weapon are identical.

signal picked_up(by: Node)

var picked: bool = false

var _t: float = 0.0
var _base_y: float = 0.0
var _blade_mat: StandardMaterial3D
var _visual: Node3D
var _area: Area3D


func _ready() -> void:
	add_to_group("sword_item")
	_base_y = position.y
	_visual = build_sword_mesh()
	_visual.position = Vector3(0.0, 0.12, 0.0)
	add_child(_visual)
	# A glowing strip over the blade - the item pulse. The hand-held copy is
	# built by the same static builder and does not carry it.
	var strip := BoxMesh.new()
	strip.size = Vector3(0.05, 0.62, 0.016)
	_blade_mat = StandardMaterial3D.new()
	_blade_mat.albedo_color = Color(0.4, 0.75, 0.9)
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(0.3, 0.6, 0.95)
	_blade_mat.emission_energy_multiplier = 0.6
	var sm := MeshInstance3D.new()
	sm.mesh = strip
	sm.material_override = _blade_mat
	sm.position = Vector3(0.0, 0.5, 0.0)
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(sm)

	_area = Area3D.new()
	_area.name = "PickupArea"
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	cs.shape = sphere
	_area.add_child(cs)
	_area.collision_layer = 0
	_area.collision_mask = 2  # player body
	add_child(_area)


func _physics_process(delta: float) -> void:
	if picked:
		return
	_t += delta
	_visual.rotation.y = _t * 1.6
	_visual.position.y = 0.12 + sin(_t * 2.2) * 0.06
	_blade_mat.emission_energy_multiplier = 0.55 + 0.3 * sin(_t * 3.0)


## Returns true when the pickup happened. If the picker understands swords it
## gets one (duck-typed on purpose: no class cycle between item and player).
func try_pick_up(by: Node) -> bool:
	if picked:
		return false
	picked = true
	visible = false
	_area.set_deferred("monitoring", false)
	if by.has_method("give_sword"):
		by.give_sword()
	picked_up.emit(by)
	return true


## Builds the sword model: blade + tip, golden guard, grip, pommel.
## Origin is at the grip bottom, blade points +Y. ~1.0 m long.
static func build_sword_mesh() -> Node3D:
	var root := Node3D.new()
	root.name = "SwordMesh"

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.80, 0.84)
	steel.metallic = 0.75
	steel.roughness = 0.28
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.30, 0.22, 0.14)
	dark.roughness = 0.9
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.68, 0.25)
	gold.metallic = 0.8
	gold.roughness = 0.35

	var blade := BoxMesh.new()
	blade.size = Vector3(0.045, 0.78, 0.012)
	var bm := MeshInstance3D.new()
	bm.mesh = blade
	bm.material_override = steel
	bm.position = Vector3(0.0, 0.52, 0.0)
	root.add_child(bm)

	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.03
	tip.height = 0.12
	tip.radial_segments = 4
	var tm := MeshInstance3D.new()
	tm.mesh = tip
	tm.material_override = steel
	tm.position = Vector3(0.0, 0.97, 0.0)
	root.add_child(tm)

	var guard := BoxMesh.new()
	guard.size = Vector3(0.17, 0.035, 0.035)
	var gm := MeshInstance3D.new()
	gm.mesh = guard
	gm.material_override = gold
	gm.position = Vector3(0.0, 0.115, 0.0)
	root.add_child(gm)

	var grip := CylinderMesh.new()
	grip.top_radius = 0.018
	grip.bottom_radius = 0.02
	grip.height = 0.14
	grip.radial_segments = 6
	grip.rings = 1
	var pm := MeshInstance3D.new()
	pm.mesh = grip
	pm.material_override = dark
	pm.position = Vector3(0.0, 0.04, 0.0)
	root.add_child(pm)

	var pommel := SphereMesh.new()
	pommel.radius = 0.028
	pommel.height = 0.056
	pommel.radial_segments = 8
	pommel.rings = 4
	var pom := MeshInstance3D.new()
	pom.mesh = pommel
	pom.material_override = gold
	pom.position = Vector3(0.0, -0.045, 0.0)
	root.add_child(pom)

	return root
