class_name Chest
extends Node3D

## An openable loot chest. Body + rotating lid, built from primitives like
## everything else in the project. Interact once: the lid swings open, the
## contents spill out as LootDrop nodes (gold auto-magnets to the player,
## items wait to be grabbed) and the chest stays open forever.
##
## contents entries:
##   {"kind": "gold", "amount": int}
##   {"kind": "supply", "id": "health_potion"|"whetstone", "count": int}
##   {"kind": "item", "id": "oak_shield"}

signal opened

var contents: Array = []
var opened_state: bool = false

var _lid: Node3D
var _t: float = 0.0
var _open_k: float = 0.0


func _ready() -> void:
	add_to_group("interactable")
	_build()


func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.34, 0.24, 0.14)
	wood.roughness = 0.9
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.36, 0.35, 0.34)
	iron.metallic = 0.6
	iron.roughness = 0.45

	var body := BoxMesh.new()
	body.size = Vector3(0.95, 0.55, 0.6)
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body
	body_mi.material_override = wood
	body_mi.position = Vector3(0.0, 0.275, 0.0)
	add_child(body_mi)

	_lid = Node3D.new()
	_lid.position = Vector3(0.0, 0.55, -0.3)
	add_child(_lid)
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(0.98, 0.16, 0.63)
	var lid_mi := MeshInstance3D.new()
	lid_mi.mesh = lid_mesh
	lid_mi.material_override = wood
	lid_mi.position = Vector3(0.0, 0.08, 0.3)
	_lid.add_child(lid_mi)

	# Iron straps across the lid and the body.
	for sx in [-0.32, 0.32]:
		var strap := BoxMesh.new()
		strap.size = Vector3(0.08, 0.58, 0.64)
		var strap_mi := MeshInstance3D.new()
		strap_mi.mesh = strap
		strap_mi.material_override = iron
		strap_mi.position = Vector3(sx, 0.29, 0.0)
		add_child(strap_mi)
		var lid_strap := BoxMesh.new()
		lid_strap.size = Vector3(0.08, 0.18, 0.66)
		var ls_mi := MeshInstance3D.new()
		ls_mi.mesh = lid_strap
		ls_mi.material_override = iron
		ls_mi.position = Vector3(sx, 0.08, 0.3)
		_lid.add_child(ls_mi)

	# Lock plate.
	var lock := BoxMesh.new()
	lock.size = Vector3(0.14, 0.16, 0.05)
	var lock_mi := MeshInstance3D.new()
	lock_mi.mesh = lock
	lock_mi.material_override = iron
	lock_mi.position = Vector3(0.0, 0.5, 0.32)
	add_child(lock_mi)

	var body_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.72, 0.66)
	body_shape.shape = box
	body_shape.position = Vector3(0.0, 0.36, 0.0)
	var col_body := StaticBody3D.new()
	col_body.collision_layer = 1
	col_body.collision_mask = 0
	col_body.add_child(body_shape)
	add_child(col_body)


func _process(delta: float) -> void:
	if _open_k > 0.0 and _open_k < 1.0:
		_open_k = minf(_open_k + delta * 2.2, 1.0)
		_lid.rotation.x = -1.9 * smoothstep(0.0, 1.0, _open_k)
	_t += delta


func get_prompt() -> String:
	if opened_state:
		return ""
	return "Открыть сундук"


func interact(by: Node) -> void:
	if opened_state:
		return
	opened_state = true
	_open_k = 0.001
	opened.emit()
	if by is Node3D:
		_spill(by as Node3D)


## Throws the contents out of the chest as physical drops.
func _spill(by: Node3D) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in contents.size():
		var entry: Dictionary = contents[i]
		var drop := LootDrop.new()
		var kind := str(entry.get("kind", "gold"))
		if kind == "gold":
			drop.drop_kind = "gold"
			drop.amount = int(entry.get("amount", 5))
		elif kind == "supply":
			drop.drop_kind = "supply"
			drop.supply_id = str(entry.get("id", "health_potion"))
			drop.amount = int(entry.get("count", 1))
		else:
			drop.drop_kind = "item"
			drop.item_id = str(entry.get("id", ""))
		var ang := TAU * float(i) / maxf(float(contents.size()), 1.0) + 0.4
		var out_dir := Vector3(cos(ang), 0.0, sin(ang)) * randf_range(0.5, 1.1)
		drop.position = global_position + Vector3(0.0, 0.62, 0.0)
		drop.toss_velocity = out_dir + Vector3(0.0, 2.4, 0.0)
		parent.add_child(drop)
