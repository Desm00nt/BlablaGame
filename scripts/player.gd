class_name Player
extends CharacterBody3D

## Third-person / first-person player with melee combat and a one-slot
## inventory.
##
## Camera: the pivot carries the pitch, the camera sits on a shoulder offset
## at the current distance and always looks along the pivot's -Z. There is no
## look_at() anywhere - the old rig used look_at() with an almost vertical
## view direction at the pitch clamps, where the up hint goes degenerate, and
## that (plus a decorative roll term) is exactly what made the view tilt over.
## Height is the rig's eye height: 1.55 m for the ~1.9 m character.
##
## Combat: LMB swings the sword (windup -> active window -> recover). During
## the active window the SwordArc Area collects enemy bodies once per swing.
## Stamina gates sprint, jump and swings; it regenerates after a short delay.

signal hp_changed(hp: float, max_hp: float)
signal stamina_changed(value: float, max_value: float)
signal sword_state_changed(has_sword: bool, equipped: bool)
signal prompt_changed(text: String)
signal inventory_toggled(open: bool)
signal hurt(amount: float)
signal died
signal respawned

@export var speed: float = 5.0
@export var jump_velocity: float = 4.6
@export var gravity: float = 9.8
@export var mouse_sensitivity: float = 0.0028

# Camera zoom (mouse wheel): 0 = first person, max = third person.
@export var max_camera_distance: float = 5.0
@export var min_camera_distance: float = 0.0
@export var camera_height: float = 1.55
@export var zoom_step: float = 0.8
@export var sprint_multiplier: float = 1.75
@export var camera_lerp_speed: float = 12.0

# Vitals.
@export var max_hp: float = 100.0
@export var max_stamina: float = 100.0
@export var stamina_regen: float = 16.0
@export var stamina_regen_delay: float = 0.8
@export var sprint_cost: float = 10.0
@export var jump_cost: float = 8.0
@export var attack_cost: float = 12.0
@export var attack_damage: float = 34.0

const ATTACK_TIME: float = 0.5
const ATTACK_ACTIVE_FROM: float = 0.34  # fraction of the swing when the blade bites
const ATTACK_ACTIVE_TO: float = 0.62
const PITCH_LIMIT: float = 1.30  # ~74.5 degrees, keeps every view direction safe

var hp: float = 100.0
var stamina: float = 100.0
var has_sword: bool = false
var sword_equipped: bool = false
var is_alive: bool = true
var hand_sword: Node3D

var camera_distance: float = 4.2
var _target_camera_distance: float = 4.2
var _stamina_idle_t: float = 0.0
var _attack_t: float = -1.0  # -1 = not attacking
var _swing_hits: Array = []
var _knock: Vector3 = Vector3.ZERO
var _spawn_point: Vector3
var _dead_t: float = 0.0
var _capture_wanted: bool = true
var _inventory_open: bool = false
var _sword_item: SwordItem
var _prompt_frame: int = 0
var _has_sprint: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var rig: CharacterRig = $Rig
@onready var sword_arc: Area3D = $SwordArc


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	stamina = max_stamina
	_spawn_point = global_position
	_has_sprint = InputMap.has_action("sprint")
	if not _has_sprint:
		push_warning("[Player] input action 'sprint' is not defined - sprint disabled")
	for action: String in ["move_forward", "move_backward", "move_left", "move_right",
			"jump", "attack", "interact", "equip_1"]:
		if not InputMap.has_action(action):
			push_error("[Player] input action '%s' is missing" % action)
	# The hand-held copy of the sword: same model as the world item, hidden
	# until equipped, blade pointing down along the arm.
	hand_sword = SwordItem.build_sword_mesh()
	hand_sword.name = "HandSword"
	hand_sword.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	hand_sword.position = Vector3(0.0, -0.05, 0.03)
	hand_sword.visible = false
	rig.hand_right.add_child(hand_sword)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_camera()
	print("[Player] ready. WASD move, Shift sprint, Space jump, wheel zoom. "
			+ "E pick up, 1 equip, LMB attack, Tab inventory.")


func _physics_process(delta: float) -> void:
	if not is_alive:
		_dead_t += delta
		rig.set_dead(_dead_t / 0.7)
		if _dead_t >= 2.4:
			_respawn()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_stamina(delta)

	if Input.is_action_just_pressed("jump") and is_on_floor() and stamina >= jump_cost:
		velocity.y = jump_velocity
		_spend_stamina(jump_cost)

	var current_speed := speed
	if _has_sprint and Input.is_action_pressed("sprint") and stamina > 1.0:
		var sprint_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		if sprint_dir.length() > 0.1:
			current_speed *= sprint_multiplier
			_spend_stamina(sprint_cost * delta)

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if direction.length() > 1.0:
		direction = direction.normalized()

	if direction.length() > 0.01:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)

	# External knockback rides on top of the controlled velocity and decays.
	velocity.x += _knock.x
	velocity.z += _knock.z
	_knock = _knock.move_toward(Vector3.ZERO, 22.0 * delta)

	move_and_slide()

	_handle_action_keys()
	_update_attack(delta)
	_update_interact_prompt()
	_update_rig_pose(delta)
	_smooth_camera(delta)


func _handle_action_keys() -> void:
	if _inventory_open:
		return
	if Input.is_action_just_pressed("interact") and _sword_item != null and not has_sword:
		_sword_item.try_pick_up(self)
	if InputMap.has_action("equip_1") and Input.is_action_just_pressed("equip_1"):
		toggle_equip()


func toggle_equip() -> void:
	if not has_sword or not is_alive:
		return
	sword_equipped = not sword_equipped
	hand_sword.visible = sword_equipped
	sword_state_changed.emit(has_sword, sword_equipped)


func give_sword() -> void:
	if has_sword:
		return
	has_sword = true
	sword_state_changed.emit(has_sword, sword_equipped)
	prompt_changed.emit("")


func _update_attack(delta: float) -> void:
	if _attack_t >= 0.0:
		_attack_t += delta / ATTACK_TIME
		var t := _attack_t
		if t >= ATTACK_ACTIVE_FROM and t <= ATTACK_ACTIVE_TO:
			_collect_sword_hits()
		if t >= 1.0:
			_attack_t = -1.0
			_swing_hits.clear()
	elif not _inventory_open and Input.is_action_just_pressed("attack") \
			and sword_equipped and stamina >= attack_cost:
		_attack_t = 0.0
		_swing_hits.clear()
		_spend_stamina(attack_cost)


func _collect_sword_hits() -> void:
	for body: Node3D in sword_arc.get_overlapping_bodies():
		if _swing_hits.has(body):
			continue
		if body.has_method("take_damage"):
			_swing_hits.append(body)
			body.take_damage(attack_damage, global_position)


func take_damage(amount: float, from_pos: Vector3) -> void:
	if not is_alive:
		return
	hp = maxf(hp - amount, 0.0)
	var dir := global_position - from_pos
	dir.y = 0.0
	if dir.length() > 0.01:
		_knock += dir.normalized() * 6.5
	velocity.y = maxf(velocity.y, 2.0)
	rig.flash_hurt()
	hp_changed.emit(hp, max_hp)
	hurt.emit(amount)
	if hp <= 0.0:
		_die()


func _die() -> void:
	is_alive = false
	_dead_t = 0.0
	_attack_t = -1.0
	velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	if _inventory_open:
		_set_inventory(false)
	prompt_changed.emit("")
	died.emit()


func _respawn() -> void:
	is_alive = true
	hp = max_hp
	stamina = max_stamina
	global_position = _spawn_point + Vector3(0.0, 0.2, 0.0)
	velocity = Vector3.ZERO
	_knock = Vector3.ZERO
	rig.reset_pose()
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	respawned.emit()


func _update_stamina(delta: float) -> void:
	_stamina_idle_t += delta
	if _stamina_idle_t >= stamina_regen_delay and stamina < max_stamina:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)


func _spend_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_stamina_idle_t = 0.0
	stamina_changed.emit(stamina, max_stamina)


func _update_rig_pose(delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var move01 := clampf(horiz.length() / speed, 0.0, 1.4)
	var at := _attack_t if _attack_t >= 0.0 else -1.0
	rig.apply_pose(delta, move01, is_on_floor(), at)


func _update_interact_prompt() -> void:
	_prompt_frame += 1
	if _prompt_frame % 6 != 0:
		return
	_sword_item = null
	for node: Node in get_tree().get_nodes_in_group("sword_item"):
		var item := node as SwordItem
		if item != null and not item.picked \
				and item.global_position.distance_to(global_position) < 2.2:
			_sword_item = item
			break
	if _sword_item != null and not has_sword:
		prompt_changed.emit("E — подобрать меч")
	else:
		prompt_changed.emit("")


func _set_inventory(open: bool) -> void:
	_inventory_open = open
	inventory_toggled.emit(open)
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _smooth_camera(delta: float) -> void:
	var k := 1.0 - exp(-camera_lerp_speed * delta)
	camera_distance = lerpf(camera_distance, _target_camera_distance, k)
	_update_camera()


func _update_camera() -> void:
	camera_pivot.position = Vector3(0.0, camera_height, 0.0)
	var first_person := camera_distance <= 0.35
	rig.visible = not first_person
	# Shoulder offset fades out as we zoom in, so the transition into the
	# head is continuous.
	var f := clampf(camera_distance / 1.2, 0.0, 1.0)
	camera.position = Vector3(0.42 * f, 0.12 * f + 0.05, camera_distance)


func _notification(what: int) -> void:
	# An exported game can come up without keyboard focus and drop all input
	# until the window is clicked; re-assert the capture when focus returns.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _capture_wanted and not _inventory_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _inventory_open:
			_set_inventory(false)
		else:
			_capture_wanted = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
			if _capture_wanted:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if InputMap.has_action("inventory") and event.is_action_pressed("inventory") and is_alive:
		_set_inventory(not _inventory_open)

	if event is InputEventMouseButton:
		var btn := event as InputEventMouseButton
		if btn.pressed:
			if btn.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_camera_distance = clampf(_target_camera_distance - zoom_step,
						min_camera_distance, max_camera_distance)
			elif btn.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_camera_distance = clampf(_target_camera_distance + zoom_step,
						min_camera_distance, max_camera_distance)
			elif not _inventory_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				_capture_wanted = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not _inventory_open:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x - motion.relative.y * mouse_sensitivity,
				-PITCH_LIMIT, PITCH_LIMIT)
