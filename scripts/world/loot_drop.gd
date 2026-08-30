class_name LootDrop
extends Node3D

## A piece of loot sitting in the world: gold coins, a potion, a whetstone or
## an inventory item. Spawned by chests and by dying draugr.
##
## Gold auto-picks at close range (magnet), everything else is interactable.
## A tiny manual toss (velocity + gravity) makes chest spills feel physical;
## the drop settles on the terrain surface and bobs gently.

var drop_kind: String = "gold"      # "gold" | "supply" | "item"
var amount: int = 1
var supply_id: String = "health_potion"
var item_id: String = ""

var toss_velocity: Vector3 = Vector3.ZERO

const MAGNET_RADIUS: float = 1.9
const GRAVITY: float = 9.8

var _t: float = 0.0
var _vel: Vector3 = Vector3.ZERO
var _settled: bool = false
var _visual: Node3D
var _rest_y: float = 0.0
var _picked: bool = false


func _ready() -> void:
	_vel = toss_velocity
	if drop_kind == "gold":
		pass  # auto-pickup only, no interactable group
	else:
		add_to_group("interactable")
	_build_visual()
	# Snap below-starting drops straight onto the ground.
	var ground := TerrainNoise.terrain_height(Vector2(global_position.x, global_position.z))
	if _vel.length() < 0.01 and global_position.y < ground + 0.1:
		global_position.y = ground + 0.1
		_settled = true
		_rest_y = global_position.y


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	if drop_kind == "gold":
		var coin_mat := StandardMaterial3D.new()
		coin_mat.albedo_color = Color(0.92, 0.76, 0.28)
		coin_mat.metallic = 0.75
		coin_mat.roughness = 0.3
		coin_mat.emission_enabled = true
		coin_mat.emission = Color(0.9, 0.7, 0.25)
		coin_mat.emission_energy_multiplier = 0.25
		for i in 3:
			var coin := CylinderMesh.new()
			coin.top_radius = 0.06
			coin.bottom_radius = 0.06
			coin.height = 0.018
			coin.radial_segments = 10
			var mi := MeshInstance3D.new()
			mi.mesh = coin
			mi.material_override = coin_mat
			mi.position = Vector3(0.06 * float(i % 2) * (1.0 if i != 1 else -1.0), 0.02 + 0.02 * float(i), 0.05 * float(i) - 0.05)
			mi.rotation = Vector3(randf_range(-0.4, 0.4), randf_range(0.0, TAU), randf_range(-0.4, 0.4))
			_visual.add_child(mi)
	elif drop_kind == "supply" and supply_id == "whetstone":
		var stone_mat := StandardMaterial3D.new()
		stone_mat.albedo_color = Color(0.48, 0.47, 0.45)
		stone_mat.roughness = 0.85
		var stone := BoxMesh.new()
		stone.size = Vector3(0.22, 0.06, 0.12)
		var s_mi := MeshInstance3D.new()
		s_mi.mesh = stone
		s_mi.material_override = stone_mat
		s_mi.position = Vector3(0.0, 0.05, 0.0)
		_visual.add_child(s_mi)
	elif drop_kind == "supply":
		# Health potion: red flask with a neck and a cork.
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.75, 0.16, 0.14)
		glass.roughness = 0.25
		glass.emission_enabled = true
		glass.emission = Color(0.8, 0.2, 0.15)
		glass.emission_energy_multiplier = 0.35
		var flask := SphereMesh.new()
		flask.radius = 0.085
		flask.height = 0.17
		flask.radial_segments = 12
		flask.rings = 6
		var f_mi := MeshInstance3D.new()
		f_mi.mesh = flask
		f_mi.material_override = glass
		f_mi.position = Vector3(0.0, 0.1, 0.0)
		_visual.add_child(f_mi)
		var neck := CylinderMesh.new()
		neck.top_radius = 0.028
		neck.bottom_radius = 0.038
		neck.height = 0.07
		neck.radial_segments = 8
		var cork_mat := StandardMaterial3D.new()
		cork_mat.albedo_color = Color(0.5, 0.38, 0.22)
		cork_mat.roughness = 0.95
		var n_mi := MeshInstance3D.new()
		n_mi.mesh = neck
		n_mi.material_override = cork_mat
		n_mi.position = Vector3(0.0, 0.2, 0.0)
		_visual.add_child(n_mi)
	else:
		# Generic item drop: a small relic prism in the quest-gold palette.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = UIStyle.GOLD
		mat.emission_enabled = true
		mat.emission = UIStyle.GOLD
		mat.emission_energy_multiplier = 0.5
		var gem := PrismMesh.new()
		gem.size = Vector3(0.16, 0.22, 0.12)
		var g_mi := MeshInstance3D.new()
		g_mi.mesh = gem
		g_mi.material_override = mat
		g_mi.position = Vector3(0.0, 0.14, 0.0)
		_visual.add_child(g_mi)


func _physics_process(delta: float) -> void:
	_t += delta
	if not _settled:
		_vel.y -= GRAVITY * delta
		global_position += _vel * delta
		var ground := TerrainNoise.terrain_height(Vector2(global_position.x, global_position.z)) + 0.06
		if global_position.y <= ground:
			global_position.y = ground
			_settled = true
			_rest_y = global_position.y
			_vel = Vector3.ZERO
		return
	if _visual != null and not _picked:
		_visual.position.y = sin(_t * 2.0) * 0.012
		if drop_kind == "gold":
			_visual.rotation.y = _t * 1.2
	if drop_kind != "gold" or _picked:
		return
	# Gold magnet: fly to the player once they come close.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_inside_tree():
		return
	var to_p := player.global_position - global_position
	to_p.y = 0.0
	if to_p.length() > MAGNET_RADIUS:
		return
	_picked = true
	if player is Player:
		(player as Player).add_gold(amount)
	queue_free()


func get_prompt() -> String:
	if drop_kind == "supply":
		var meta := ItemDB.get_item(supply_id)
		return "Взять: " + str(meta.get("name", supply_id))
	if drop_kind == "item":
		return "Взять: " + ItemDB.display_name(item_id)
	return ""


func interact(by: Node) -> void:
	if _picked or drop_kind == "gold":
		return
	_picked = true
	var taker := by as Player
	if taker == null:
		if by.has_method("add_item"):
			by.add_item(item_id)
		queue_free()
		return
	if drop_kind == "supply":
		taker.add_supply(supply_id, amount)
	else:
		taker.add_item(item_id)
	queue_free()
