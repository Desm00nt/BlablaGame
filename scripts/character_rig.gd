class_name CharacterRig
extends Node3D

## Procedural low-poly humanoid. The project builds every asset from
## primitives (no textures, no imported models), so the character is a small
## node tree of cheap meshes driven by sin() curves instead of an
## AnimationPlayer.
##
## Cost per rig: ~20 low-segment meshes (6-10 segments each) and a handful of
## materials. Poses are pure maths, so they never desync from the actual
## movement speed and cost no allocations.
##
## Pose contract:
##   apply_pose(delta, move01, on_floor, attack_t)
##     move01   0 = idle, 1 = full run
##     attack_t -1 = not attacking, otherwise 0..1 over the whole swing
##   set_dead(t01)  falls on the back, stays down
##   reset_pose()   restores the living pose (respawn)

@export var palette_tunic: Color = Color(0.22, 0.34, 0.58)
@export var palette_armor: Color = Color(0.70, 0.74, 0.80)
@export var palette_skin: Color = Color(0.87, 0.68, 0.52)
@export var palette_leather: Color = Color(0.42, 0.29, 0.17)
@export var palette_cape: Color = Color(0.55, 0.16, 0.16)
@export var palette_eyes: Color = Color(0.95, 0.85, 0.30)
@export var eyes_emissive: bool = false

## Where the equipped weapon is attached (right hand).
var hand_right: Node3D

var _hips: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _cape: Node3D

# Tunic and skin are duplicated per rig because the hurt flash rewrites their
# albedo; armor/leather/cape stay shared per rig (no flash on them).
var _mat_tunic: StandardMaterial3D
var _mat_skin: StandardMaterial3D
var _base_tunic: Color
var _base_skin: Color

var _phase: float = 0.0
var _time: float = 0.0
var _flash: float = 0.0

const HIP_Y: float = 0.88


func _ready() -> void:
	_build()


func _mat(color: Color, rough: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3(),
		shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _build() -> void:
	_base_tunic = palette_tunic
	_base_skin = palette_skin
	_mat_tunic = _mat(palette_tunic, 0.85)
	_mat_skin = _mat(palette_skin, 0.75)
	var mat_armor := _mat(palette_armor, 0.35, 0.55)
	var mat_leather := _mat(palette_leather, 0.9)
	var mat_cape := _mat(palette_cape, 0.95)
	var mat_eyes := _mat(palette_eyes, 0.4)
	if eyes_emissive:
		mat_eyes.emission_enabled = true
		mat_eyes.emission = palette_eyes
		mat_eyes.emission_energy_multiplier = 2.2

	_hips = _pivot(self, "Hips", Vector3(0.0, HIP_Y, 0.0))

	# Torso: chunky 6-sided tapered cylinder.
	var torso := CylinderMesh.new()
	torso.top_radius = 0.235
	torso.bottom_radius = 0.185
	torso.height = 0.62
	torso.radial_segments = 6
	torso.rings = 1
	_mesh(_hips, torso, _mat_tunic, Vector3(0.0, 0.31, 0.0))

	var belt := CylinderMesh.new()
	belt.top_radius = 0.20
	belt.bottom_radius = 0.20
	belt.height = 0.09
	belt.radial_segments = 6
	belt.rings = 1
	_mesh(_hips, belt, mat_leather, Vector3(0.0, 0.045, 0.0))

	# Cape hangs from a pivot at the shoulders so it can swing.
	_cape = _pivot(_hips, "Cape", Vector3(0.0, 0.45, -0.16))
	var cape_mesh := BoxMesh.new()
	cape_mesh.size = Vector3(0.40, 0.72, 0.025)
	_mesh(_cape, cape_mesh, mat_cape, Vector3(0.0, -0.36, 0.0))

	# Head: skull + helmet + horns + eyes.
	_head = _pivot(_hips, "Head", Vector3(0.0, 0.78, 0.0))
	var skull := SphereMesh.new()
	skull.radius = 0.165
	skull.height = 0.33
	skull.radial_segments = 10
	skull.rings = 6
	_mesh(_head, skull, _mat_skin, Vector3.ZERO)

	var helm := CylinderMesh.new()
	helm.top_radius = 0.175
	helm.bottom_radius = 0.185
	helm.height = 0.15
	helm.radial_segments = 8
	helm.rings = 1
	_mesh(_head, helm, mat_armor, Vector3(0.0, 0.075, 0.0))

	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.045
	horn.height = 0.16
	horn.radial_segments = 6
	_mesh(_head, horn, mat_armor, Vector3(-0.16, 0.16, 0.0), Vector3(0.0, 0.0, -30.0))
	_mesh(_head, horn, mat_armor, Vector3(0.16, 0.16, 0.0), Vector3(0.0, 0.0, 30.0))

	var eye := SphereMesh.new()
	eye.radius = 0.021
	eye.height = 0.042
	eye.radial_segments = 6
	eye.rings = 3
	_mesh(_head, eye, mat_eyes, Vector3(-0.055, 0.01, 0.145), Vector3(), false)
	_mesh(_head, eye, mat_eyes, Vector3(0.055, 0.01, 0.145), Vector3(), false)

	# Arms: shoulder pad + hanging capsule; the right one carries the weapon.
	var arm := CapsuleMesh.new()
	arm.radius = 0.068
	arm.height = 0.5
	arm.radial_segments = 7
	arm.rings = 2
	var pad := SphereMesh.new()
	pad.radius = 0.085
	pad.height = 0.17
	pad.radial_segments = 8
	pad.rings = 4
	_arm_l = _pivot(_hips, "ArmL", Vector3(-0.295, 0.52, 0.0))
	_mesh(_arm_l, pad, mat_armor, Vector3.ZERO)
	_mesh(_arm_l, arm, _mat_tunic, Vector3(0.0, -0.24, 0.0))
	_arm_r = _pivot(_hips, "ArmR", Vector3(0.295, 0.52, 0.0))
	_mesh(_arm_r, pad, mat_armor, Vector3.ZERO)
	_mesh(_arm_r, arm, _mat_tunic, Vector3(0.0, -0.24, 0.0))
	hand_right = _pivot(_arm_r, "HandR", Vector3(0.0, -0.5, 0.0))

	# Legs: capsules whose bottoms rest exactly on y=0 (HIP_Y - 0.87).
	var leg := CapsuleMesh.new()
	leg.radius = 0.082
	leg.height = 0.86
	leg.radial_segments = 7
	leg.rings = 2
	_leg_l = _pivot(_hips, "LegL", Vector3(-0.115, 0.0, 0.0))
	_mesh(_leg_l, leg, mat_leather, Vector3(0.0, -0.44, 0.0))
	_leg_r = _pivot(_hips, "LegR", Vector3(0.115, 0.0, 0.0))
	_mesh(_leg_r, leg, mat_leather, Vector3(0.0, -0.44, 0.0))


## Called every physics frame by the owning body.
func apply_pose(delta: float, move01: float, on_floor: bool, attack_t: float) -> void:
	_time += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		var wound := Color(1.0, 0.25, 0.2)
		_mat_tunic.albedo_color = _base_tunic.lerp(wound, _flash)
		_mat_skin.albedo_color = _base_skin.lerp(wound, _flash * 0.7)

	if move01 > 0.02 and on_floor:
		_phase += delta * (4.0 + 7.0 * clampf(move01, 0.0, 1.4))
	var swing := sin(_phase) * clampf(move01, 0.0, 1.0)
	var air_tuck := 0.0 if on_floor else 0.35

	_leg_l.rotation.x = swing * 0.75 + air_tuck
	_leg_r.rotation.x = -swing * 0.75 + air_tuck * 0.6

	_arm_l.rotation.x = -swing * 0.55 + air_tuck * 1.2
	if attack_t < 0.0:
		_arm_r.rotation.x = swing * 0.55 + air_tuck * 1.2
		_arm_r.rotation.z = 0.0
	else:
		_apply_attack(attack_t)

	var bob := absf(swing) * 0.055 + sin(_time * 2.1) * 0.012
	_hips.position.y = HIP_Y + bob
	_hips.rotation.y = swing * 0.08
	_cape.rotation.x = 0.12 + clampf(move01, 0.0, 1.0) * 0.85 + sin(_phase * 0.5) * 0.05 * move01
	_head.rotation.x = -0.04 - clampf(move01, 0.0, 1.0) * 0.05


## Swing timeline: windup 0..0.30, slash 0.30..0.55, recover 0.55..1.
func _apply_attack(t01: float) -> void:
	if t01 < 0.30:
		var k := smoothstep(0.0, 0.30, t01)
		_arm_r.rotation.x = lerpf(0.0, 1.35, k)
		_arm_r.rotation.z = lerpf(0.0, -0.35, k)
	elif t01 < 0.55:
		var k := smoothstep(0.30, 0.55, t01)
		_arm_r.rotation.x = lerpf(1.35, -1.75, k)
		_arm_r.rotation.z = lerpf(-0.35, 0.25, k)
	else:
		var k := smoothstep(0.55, 1.0, t01)
		_arm_r.rotation.x = lerpf(-1.75, 0.0, k)
		_arm_r.rotation.z = lerpf(0.25, 0.0, k)


func flash_hurt() -> void:
	_flash = 1.0


## Falls on the back around the feet pivot, then stays down.
func set_dead(t01: float) -> void:
	rotation.x = -lerpf(0.0, PI * 0.5, clampf(t01, 0.0, 1.0))


func reset_pose() -> void:
	rotation.x = 0.0
	_flash = 0.0
	_mat_tunic.albedo_color = _base_tunic
	_mat_skin.albedo_color = _base_skin
	_phase = 0.0
	apply_pose(0.016, 0.0, true, -1.0)
