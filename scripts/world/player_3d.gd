extends CharacterBody3D

const SPEED := 3.5
const PAUSE_MENU := "res://scenes/menu/pause_menu.tscn"
@export var camera_path: NodePath

@onready var sprite: Sprite3D = $Sprite3D

var _menu_open: bool = false

func _physics_process(_delta: float) -> void:
	if DialogueManager.is_active() or _menu_open:
		velocity = Vector3.ZERO
		return
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 1.0:
		input = input.normalized()
	var cam := _get_camera()
	var rx := 0.0
	var rz := 0.0
	if cam:
		var forward := -cam.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var move_vec := right * input.x + forward * input.y
		rx = move_vec.x
		rz = move_vec.z
	else:
		var rot := PI / 4.0
		rx = input.x * cos(rot) - input.y * sin(rot)
		rz = input.x * sin(rot) + input.y * cos(rot)
	velocity.x = rx * SPEED
	velocity.z = rz * SPEED
	velocity.y = 0
	move_and_slide()
	if input.x < -0.1:
		sprite.flip_h = true
	elif input.x > 0.1:
		sprite.flip_h = false

func _get_camera() -> Camera3D:
	if camera_path != NodePath():
		var n := get_node_or_null(camera_path) as Camera3D
		if n: return n
	return get_viewport().get_camera_3d()

func _unhandled_input(event: InputEvent) -> void:
	if _menu_open or DialogueManager.is_active(): return
	if event.is_action_pressed("open_menu"):
		_open_menu()
		get_viewport().set_input_as_handled()

func _open_menu() -> void:
	var packed: PackedScene = load(PAUSE_MENU)
	if packed == null: return
	var ui := packed.instantiate()
	get_tree().current_scene.add_child(ui)
	_menu_open = true
	ui.closed.connect(func(): _menu_open = false)
