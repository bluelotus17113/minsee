@tool
extends Area3D

@export var portal_id: String = "portal_1"
@export_file("*.tscn") var target_scene: String = ""
@export var target_portal_id: String = ""
@export var prompt_text: String = "Entrar"
@export var auto_enter: bool = false

var _player_in_range: bool = false
var _cooldown: bool = false

func _ready() -> void:
	if Engine.is_editor_hint(): return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	$Prompt.visible = false
	if MapManager.pending_portal_id == portal_id:
		_cooldown = true
		await get_tree().create_timer(0.45).timeout
		_cooldown = false
	$Prompt.text = "[E] " + prompt_text

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or _cooldown: return
	_player_in_range = true
	if auto_enter:
		_travel()
	else:
		$Prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$Prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _cooldown: return
	if DialogueManager.is_active(): return
	if event.is_action_pressed("interact"):
		_travel()
		get_viewport().set_input_as_handled()

func _travel() -> void:
	if target_scene == "": return
	_cooldown = true
	$Prompt.visible = false
	MapManager.travel_to(target_scene, target_portal_id)
