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

var camera_distance: float = 5.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var body_mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	# Capture the mouse for third-person look.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_camera()


func _physics_process(delta: float) -> void:
	# Apply gravity while not on the floor.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump when grounded and the jump action is pressed.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Read WASD input in the character's local space.
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Horizontal movement (instant acceleration/deceleration is fine for the prototype).
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()


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
				camera_distance = clamp(camera_distance - zoom_step, first_person_distance, max_camera_distance)
				_update_camera()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_distance = clamp(camera_distance + zoom_step, first_person_distance, max_camera_distance)
				_update_camera()

	# Re-capture on click in case it was released.
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Mouse look only while the cursor is captured.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Horizontal mouse movement rotates the whole body (yaw).
		rotate_y(-event.relative.x * mouse_sensitivity)

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
