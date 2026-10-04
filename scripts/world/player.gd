extends CharacterBody2D

const SPEED := 90.0
const PAUSE_MENU := "res://scenes/menu/pause_menu.tscn"

@onready var sprite: ColorRect = $Sprite

var _menu_open: bool = false

func _physics_process(_delta: float) -> void:
	if DialogueManager.is_active() or _menu_open:
		velocity = Vector2.ZERO
		return
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 1.0:
		input = input.normalized()
	velocity = input * SPEED
	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if _menu_open or DialogueManager.is_active():
		return
	if event.is_action_pressed("open_menu"):
		_open_menu()
		get_viewport().set_input_as_handled()

func _open_menu() -> void:
	var packed: PackedScene = load(PAUSE_MENU)
	if packed == null:
		return
	var ui := packed.instantiate()
	get_tree().current_scene.add_child(ui)
	_menu_open = true
	ui.closed.connect(func(): _menu_open = false)

