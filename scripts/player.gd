extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 9.8
@export var mouse_sensitivity: float = 0.003

# Camera zoom (mouse wheel): 0.0 = first person, max_camera_distance = third person.
@export var max_camera_distance: float = 5.0
@export var first_person_distance: float = 0.0
@export var camera_height: float = 2.0
@export var zoom_step: float = 1.0

# Phase 3 additions.
@export var sprint_multiplier: float = 1.8
@export var camera_lerp_speed: float = 14.0
@export var tilt_amount: float = 0.055   # radians of roll at full turn rate
@export var tilt_lerp_speed: float = 9.0

var camera_distance: float = 5.0

var _target_camera_distance: float = 5.0
var _tilt: float = 0.0
var _yaw_delta: float = 0.0
var _has_sprint: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var body_mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	# Capture the mouse for third-person look.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_target_camera_distance = camera_distance
	# Guarded so the script still runs if project.godot lacks the action.
	_has_sprint = InputMap.has_action("sprint")
	if not _has_sprint:
		push_warning("[Player] input action 'sprint' is not defined - sprint disabled")
	_update_camera()


func _physics_process(delta: float) -> void:
	# Apply gravity while not on the floor.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump when grounded and the jump action is pressed.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Sprint is a simple speed multiplier; the deceleration below scales with it
	# so stopping does not feel slower than running.
	var current_speed := speed
	if _has_sprint and Input.is_action_pressed("sprint"):
		current_speed *= sprint_multiplier

	# Read WASD input in the character's local space.
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Horizontal movement (instant acceleration/deceleration is fine for the prototype).
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)

	move_and_slide()

	_smooth_camera(delta)


## Frame-rate independent exponential smoothing, so the camera behaves the same
## at 30 fps and at 144 fps.
func _smooth_camera(delta: float) -> void:
	var k := 1.0 - exp(-camera_lerp_speed * delta)
	camera_distance = lerpf(camera_distance, _target_camera_distance, k)

	var target_tilt := clampf(_yaw_delta * 7.0, -tilt_amount, tilt_amount)
	_tilt = lerpf(_tilt, target_tilt, 1.0 - exp(-tilt_lerp_speed * delta))
	_yaw_delta = 0.0

	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape.
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Mouse wheel zoom in/out between first and third person.
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_camera_distance = clampf(_target_camera_distance - zoom_step,
						first_person_distance, max_camera_distance)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_camera_distance = clampf(_target_camera_distance + zoom_step,
						first_person_distance, max_camera_distance)

	# Re-capture on click in case it was released.
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Mouse look only while the cursor is captured.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Horizontal mouse movement rotates the whole body (yaw).
		var yaw := -event.relative.x * mouse_sensitivity
		rotate_y(yaw)
		_yaw_delta += yaw

		# Vertical mouse movement rotates the camera pivot (pitch), clamped to +-70 degrees.
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-70.0), deg_to_rad(70.0))


func _update_camera() -> void:
	# The camera sits behind/above the pivot; distance 0 puts it at eye level (first person).
	camera.position = Vector3(0.0, camera_height, camera_distance)

	# At any distance, frame the pivot. At distance 0 (first person) the camera is
	# at the pivot point, so look_at() aims straight along the view direction.
	if camera_distance <= 0.01:
		# Hide the body so the capsule doesn't fill the first-person view.
		body_mesh.visible = false
		var forward: Vector3 = -camera_pivot.global_transform.basis.z
		camera.look_at(camera.global_position + forward, Vector3.UP)
	else:
		body_mesh.visible = true
		camera.look_at(camera_pivot.global_position, Vector3.UP)

	# look_at() rebuilds the basis, so the roll has to be applied afterwards.
	if absf(_tilt) > 0.0001:
		camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), _tilt)
