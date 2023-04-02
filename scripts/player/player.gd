extends CharacterBody3D


const WALK_SPEED = 5.0
const SPRINT_MULTIPLIER = 2.0
const CROUCH_MULTIPLIER: float = 0.5

const JUMP_VELOCITY: float = 7.5
const GRAVITY: float = 45.0
const AIR_ACCELERATION: float = 10.0
const REGULAR_ACCELERATION: float = 20.0

const CROUCH_TRANSITION_SPEED: float = 0.1
const COLLIDER_REGULAR_HEIGHT: float = 1.8
const COLLIDER_CROUCH_HEIGHT: float = 0.9
const HEAD_CROUCH_HEIGHT := 0.9
const HEAD_STANDING_HEIGHT := 1.8

const MOUSE_SENSITIVITY: float = 0.002
const CAMERA_UPPER_CLAMP: float = 90.0 # These two are later converted to radians.
const CAMERA_LOWER_CLAMP: float = -90.0

enum MovementStates{ON_GROUND, IN_AIR}

# Camera.
var mouse_rotation := Vector3.ZERO
var camera_upper_clamp_rad: float # These two are the ones used to clamp the vertical look direction.
var camera_lower_clamp_rad: float # They get their values in radians in _ready().
@export var camera_position_offset := Vector3(0, 1.8, 0)

# Movement.
var movement := Vector3() # Final movement direction and magnitude for one tick.
var current_movement_state = MovementStates.IN_AIR
var horizontal_velocity := Vector3.ZERO
var original_horizontal_velocity := Vector3() # Used for preserving momentum when transitioning between different movement states.
var direction := Vector3.ZERO
var gravity_vector := Vector3.ZERO
var current_collider_height: float = 1.8 # Used for shrinking the collider when crouching.

# Input flags.
var request_sprinting: bool = false
var request_crouching: bool = false
var request_jump: bool = false

# Movement flags.
var is_grounded: bool = false
var can_jump: bool = false
var is_momentum_preserved: bool = false
var is_head_bonked: bool = false
var offset_velocity := Vector3.ZERO

@onready var camera: Camera3D = $Camera3D
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var ui = $PlayerUI
@onready var item_manager = $Camera3D/Hands

func _ready() -> void:
	camera.current = true
	
	# Convert these two to radians because Godot likes it, I suppose.
	camera_upper_clamp_rad = deg_to_rad(CAMERA_UPPER_CLAMP)
	camera_lower_clamp_rad = deg_to_rad(CAMERA_LOWER_CLAMP)
	
	# Keep the mouse positioned at screen centre.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta: float) -> void:
	process_camera_position()

func _unhandled_input(event: InputEvent) -> void:
	# Only look around if the mouse is invisible.
	if event is InputEventMouseMotion:
		var relative_mouse_motion: Vector2 = event.relative
		process_camera_rotation(relative_mouse_motion)
	
	# Which way we are going to move.
	direction = Vector3()
	
	# Forwards/backwards and left/right input and movement.
	# Direction is taken according to the camera y axis instead of the actual
	# body so that we don't get weird physics rotation stuff!
	direction += -global_transform.basis.x.rotated(Vector3(0, 1 ,0), camera.rotation.y) * (Input.get_action_strength("move_left") - Input.get_action_strength("move_right"))
	direction += -global_transform.basis.z.rotated(Vector3(0, 1, 0), camera.rotation.y) * (Input.get_action_strength("move_forwards") - Input.get_action_strength("move_backwards"))
	
	# Ensure we aren't faster when moving diagonally.
	direction = direction.normalized()
	
	# These requests influence check_movement_flags(), which determines
	# the outcome of process_movement().
	if Input.is_action_pressed("sprint"):
		request_sprinting = true
	else:
		request_sprinting = false
	
	if Input.is_action_pressed("crouch"):
		request_crouching = true
	else:
		request_crouching = false
	
	if Input.is_action_pressed("jump"):
		request_jump = true
	else:
		request_jump = false
	
	# Items and stuff.
	if Input.is_action_just_pressed("fire"):
		item_manager.request_action("fire")
	if Input.is_action_just_released("fire"):
		item_manager.request_action("fire_stop")
	
	if Input.is_action_just_pressed("fire_2"):
		item_manager.request_action("fire_2")
	if Input.is_action_just_released("fire_2"):
		item_manager.request_action("fire_2_stop")
	
	if Input.is_action_just_pressed("drop_item"):
		item_manager.request_action("drop_item")
	
	if Input.is_action_just_pressed("reload"):
		item_manager.request_action("reload")
	
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					item_manager.next_item()
				MOUSE_BUTTON_WHEEL_DOWN:
					item_manager.previous_item()

func _physics_process(delta: float) -> void:
	
	check_movement_flags()
	handle_crouching()
	process_movement_state(delta)

func check_movement_flags() -> void:
	if is_on_floor():
		current_movement_state = MovementStates.ON_GROUND
	else:
		current_movement_state = MovementStates.IN_AIR

func process_camera_position() -> void:
	camera.global_position = global_position + camera_position_offset

func process_camera_rotation(relative_mouse_motion) -> void:
	# Horizontal mouse look.
	mouse_rotation.y -= relative_mouse_motion.x * MOUSE_SENSITIVITY
	# Vertical mouse look.
	mouse_rotation.x = clampf(mouse_rotation.x - (relative_mouse_motion.y * MOUSE_SENSITIVITY),
			camera_lower_clamp_rad,
			camera_upper_clamp_rad)
	
	# Rotate head independently of body.
	# This camera also determines the local direction of WASD.
	camera.rotation.x = mouse_rotation.x
	camera.rotation.y = mouse_rotation.y

func check_movement_state() -> void:
	if is_on_floor():
		current_movement_state = MovementStates.ON_GROUND
	else:
		current_movement_state = MovementStates.IN_AIR

func process_movement_state(delta) -> void:
	match current_movement_state:
		MovementStates.ON_GROUND:
			ground_move(delta)
		MovementStates.IN_AIR:
			air_move(delta)

func ground_move(delta) -> void:
	is_momentum_preserved = false
	
	# Stick to slopes and stuff.
	gravity_vector = -get_floor_normal()
	
	if request_jump:
		jump()
	
	# Determine if we are sprinting, walking or crouching.
	if request_sprinting:
		horizontal_velocity = horizontal_velocity.lerp(
				direction * (WALK_SPEED * SPRINT_MULTIPLIER),
				REGULAR_ACCELERATION * delta) # TODO: is delta frame-independent?
	# Regular movement / walking.
	else:
		horizontal_velocity = horizontal_velocity.lerp(
				direction * WALK_SPEED,
				REGULAR_ACCELERATION * delta)
	if request_crouching:
		horizontal_velocity = horizontal_velocity * CROUCH_MULTIPLIER
	
	# Velocity vector calculated from horizontal direction and gravity.
	velocity.z = horizontal_velocity.z + gravity_vector.z
	velocity.x = horizontal_velocity.x + gravity_vector.x
	velocity.y = gravity_vector.y
	
	move_and_slide()

func air_move(delta) -> void:
	gravity_vector += Vector3.DOWN * GRAVITY * (delta / 2) # Fall to the ground.
	
	# Makes the player slow down or speed up, depending on what they hit.
	var fr_fr = get_real_velocity()
	horizontal_velocity.x = fr_fr.x
	horizontal_velocity.z = fr_fr.z
	
	# Get the velocity over ground from when we jumped / became airborne.
	if not is_momentum_preserved:
		original_horizontal_velocity = horizontal_velocity
		is_momentum_preserved = true
	
	offset_velocity = direction / 2
	
	horizontal_velocity = horizontal_velocity + offset_velocity
	
	if original_horizontal_velocity.length() <= WALK_SPEED:
		horizontal_velocity = clamp_vector(horizontal_velocity, WALK_SPEED)
	else:
		horizontal_velocity = clamp_vector(horizontal_velocity, original_horizontal_velocity.length())
	
	# Reduce or increase horizontal velocity in case we hit something.
	
	
	# Crouch sliding.
	
	# Movement vector calculated from horizontal direction and gravity.
	movement.z = horizontal_velocity.z + gravity_vector.z
	movement.x = horizontal_velocity.x + gravity_vector.x
	movement.y = gravity_vector.y
	
	# Final velocity calculated from movement.
	set_velocity(movement)
	
	move_and_slide()

func handle_crouching() -> void:
	
	# Change colliders when crouching TODO explain
	# Head movement is 
	if request_crouching or is_head_bonked:
		current_collider_height -= CROUCH_TRANSITION_SPEED
		#head.translation = head.translation.linear_interpolate(Vector3(0, 1.25, 0), CROUCH_TRANSITION_SPEED)
	else:
		current_collider_height += CROUCH_TRANSITION_SPEED
		#head.translation = head.translation.linear_interpolate(Vector3(0, 1.8, 0), CROUCH_TRANSITION_SPEED)
	
	# Crouch and regular height determine the shortest and highest we can stand, respectively.
	current_collider_height = clamp(current_collider_height, COLLIDER_CROUCH_HEIGHT, COLLIDER_REGULAR_HEIGHT)
	
	collider.shape.height = current_collider_height

func jump():
	gravity_vector = Vector3.UP * JUMP_VELOCITY

# Used instead of clamp() so that the vector in question is limited
# to a circle instead of a square.
func clamp_vector(vector: Vector3, clamp_length: float) -> Vector3:
	if vector.length() <= clamp_length:
		return vector
	return vector * (clamp_length / vector.length())
