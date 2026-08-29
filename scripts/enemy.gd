class_name Enemy
extends CharacterBody3D

## Draugr-style melee enemy. Finite state machine, all logic on a cheap
## 10 Hz think tick, movement every physics frame:
##
##   PATROL  wanders around its home point
##   CHASE   player inside chase_radius, walks up to attack_range
##   WINDUP  0.45 s telegraph, then a strike if the player is still close
##   STRIKE_RECOVER  0.9 s after the swing
##   STAGGER 0.32 s on being hit, with knockback
##   DEAD    falls over, respawns at home after respawn_delay
##
## Damage/knockback enter through take_damage(). The billboard HP bar is only
## drawn once the enemy is wounded, and its basis is copied from the camera
## every 3rd frame instead of per-particle billboarding.
##
## Facing comes from the rig itself: CharacterRig looks along -Z, and the yaw
## below steers -Z along the walk direction, so draugr run facing forward.

signal died(tag: String)

enum State { PATROL, CHASE, WINDUP, STRIKE_RECOVER, STAGGER, DEAD }

@export var max_hp: float = 100.0
@export var damage: float = 15.0
@export var chase_radius: float = 13.0
@export var give_up_radius: float = 19.0
@export var attack_range: float = 2.05
@export var walk_speed: float = 1.7
@export var chase_speed: float = 3.3
@export var gravity: float = 9.8
@export var respawn_delay: float = 20.0
## Quest kill-counter tag ("" = not counted). main.gd forwards died(tag)
## into QuestManager.notify_kill().
@export var kill_tag: String = ""

const WINDUP_TIME: float = 0.45
const RECOVER_TIME: float = 0.9
const STAGGER_TIME: float = 0.32
const THINK_INTERVAL: float = 0.1
const PATROL_RADIUS: float = 4.5

var hp: float = 100.0
var _state: int = State.PATROL
var _timer: float = 0.0
var _dead_t: float = 0.0
var _home: Vector3
var _patrol_target: Vector3
var _patrol_wait: float = 0.0
var _knock: Vector3 = Vector3.ZERO
var _think_accum: float = 0.0
var _rig: CharacterRig
var _hp_bar: Node3D
var _hp_fill: MeshInstance3D
var _bar_frame: int = 0


func _ready() -> void:
	add_to_group("enemies")
	_home = global_position
	_patrol_target = _home
	_rig = get_node(^"Rig") as CharacterRig
	hp = max_hp
	_build_hp_bar()


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		_dead_t += delta
		_rig.set_dead(_dead_t / 0.6)
		if _dead_t >= respawn_delay:
			_respawn()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	_think_accum += delta
	var think := _think_accum >= THINK_INTERVAL
	if think:
		_think_accum = 0.0

	var move_dir := Vector3.ZERO
	var move_speed := walk_speed
	var attack_t := -1.0

	match _state:
		State.PATROL:
			_patrol_wait -= delta
			var to_target := _patrol_target - global_position
			to_target.y = 0.0
			if to_target.length() < 0.6:
				move_speed = 0.0
				if think and _patrol_wait <= 0.0:
					_pick_patrol_target()
					_patrol_wait = randf_range(1.5, 5.0)
			else:
				move_dir = to_target.normalized()
			if think:
				var p := _find_player()
				if p != null and p.global_position.distance_to(global_position) < chase_radius:
					_state = State.CHASE
		State.CHASE:
			var p := _find_player()
			if p == null:
				_state = State.PATROL
			else:
				var to_player := p.global_position - global_position
				to_player.y = 0.0
				var dist := to_player.length()
				if dist > give_up_radius:
					_state = State.PATROL
					_patrol_target = _home
				elif dist <= attack_range:
					_state = State.WINDUP
					_timer = 0.0
					move_speed = 0.0
				else:
					move_dir = to_player / maxf(dist, 0.001)
					move_speed = chase_speed
		State.WINDUP:
			_timer += delta
			move_speed = 0.0
			attack_t = clampf(_timer / WINDUP_TIME, 0.0, 1.0) * 0.55
			if _timer >= WINDUP_TIME:
				_strike()
				_state = State.STRIKE_RECOVER
				_timer = 0.0
		State.STRIKE_RECOVER:
			_timer += delta
			move_speed = 0.0
			attack_t = 0.55 + clampf(_timer / RECOVER_TIME, 0.0, 1.0) * 0.45
			if _timer >= RECOVER_TIME:
				_state = State.CHASE
		State.STAGGER:
			_timer += delta
			move_speed = 0.0
			if _timer >= STAGGER_TIME:
				_state = State.CHASE

	if move_speed > 0.0 and move_dir.length() > 0.01:
		velocity.x = move_dir.x * move_speed + _knock.x
		velocity.z = move_dir.z * move_speed + _knock.z
		var yaw := atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-8.0 * delta))
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed) + _knock.x
		velocity.z = move_toward(velocity.z, 0.0, move_speed) + _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)

	move_and_slide()

	var horiz := Vector3(velocity.x - _knock.x, 0.0, velocity.z - _knock.z)
	var move01 := clampf(horiz.length() / chase_speed, 0.0, 1.0)
	_rig.apply_pose(delta, move01, is_on_floor(), attack_t)
	_update_hp_bar(delta)


func _find_player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p


func _pick_patrol_target() -> void:
	var ang := randf_range(0.0, TAU)
	var r := randf_range(1.5, PATROL_RADIUS)
	_patrol_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)


func _strike() -> void:
	var p := _find_player()
	if p == null:
		return
	if p.global_position.distance_to(global_position) <= attack_range + 0.45 and p.has_method("take_damage"):
		p.take_damage(damage, global_position)


func take_damage(amount: float, from_pos: Vector3) -> void:
	if _state == State.DEAD:
		return
	hp = maxf(hp - amount, 0.0)
	_knock = global_position - from_pos
	_knock.y = 0.0
	if _knock.length() > 0.01:
		_knock = _knock.normalized() * 5.5
	_rig.flash_hurt()
	_update_fill()
	if hp <= 0.0:
		_die()
	else:
		_state = State.STAGGER
		_timer = 0.0


func _die() -> void:
	_state = State.DEAD
	_dead_t = 0.0
	velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	# Deferred: physics state must not be modified during a physics callback
	# that may have originated from an Area overlap.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	_hp_bar.visible = false
	died.emit(kill_tag)


func _respawn() -> void:
	_state = State.PATROL
	_dead_t = 0.0
	hp = max_hp
	global_position = _home + Vector3(0.0, 0.1, 0.0)
	velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	_patrol_target = _home
	_patrol_wait = 1.0
	set_deferred("collision_layer", 4)
	set_deferred("collision_mask", 7)
	_rig.reset_pose()
	_update_fill()


func _build_hp_bar() -> void:
	_hp_bar = Node3D.new()
	_hp_bar.name = "HPBar"
	_hp_bar.position = Vector3(0.0, 2.2, 0.0)
	add_child(_hp_bar)

	var bg := QuadMesh.new()
	bg.size = Vector2(0.9, 0.1)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var bg_mi := MeshInstance3D.new()
	bg_mi.mesh = bg
	bg_mi.material_override = bg_mat
	bg_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.add_child(bg_mi)

	var fill := QuadMesh.new()
	fill.size = Vector2(0.84, 0.055)
	_hp_fill = MeshInstance3D.new()
	_hp_fill.mesh = fill
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_color = Color(0.85, 0.2, 0.15)
	_hp_fill.material_override = fill_mat
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Left-anchored shrink: pivot at the bar's left edge, quad offset right.
	var pivot := Node3D.new()
	pivot.position = Vector3(-0.42, 0.0, 0.01)
	pivot.add_child(_hp_fill)
	_hp_fill.position = Vector3(0.42, 0.0, 0.0)
	_hp_bar.add_child(pivot)
	_hp_bar.visible = false


func _update_fill() -> void:
	var ratio := clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_hp_fill.scale = Vector3(ratio, 1.0, 1.0)
	_hp_bar.visible = ratio < 0.999 and _state != State.DEAD


func _update_hp_bar(_delta: float) -> void:
	if not _hp_bar.visible:
		return
	_bar_frame += 1
	if _bar_frame % 3 != 0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		# Rigid billboard: copy the camera basis so both quads stay aligned.
		_hp_bar.global_transform.basis = cam.global_transform.basis
