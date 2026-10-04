@tool
class_name PortalNode
extends Area2D

@export var portal_id: String = "portal_1"
@export_file("*.tscn") var target_scene: String = ""
@export var target_portal_id: String = ""
@export var prompt_text: String = "Entrar"
@export var auto_enter: bool = false
@export var direction: Direction = Direction.NONE

enum Direction { NONE, NORTH, SOUTH, EAST, WEST }

var _player_in_range: bool = false
var _cooldown: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_visual()
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	$Prompt.visible = false
	_refresh_visual()
	# Si fuimos colocados como destino de un viaje, ignorar el primer trigger
	if MapManager.pending_portal_id == portal_id:
		_cooldown = true
		await get_tree().create_timer(0.4).timeout
		_cooldown = false

func _refresh_visual() -> void:
	var rect := get_node_or_null("Sprite") as ColorRect
	if rect == null: return
	match direction:
		Direction.NORTH: rect.color = Color(0.4, 0.85, 1.0, 0.9)
		Direction.SOUTH: rect.color = Color(1.0, 0.7, 0.4, 0.9)
		Direction.EAST: rect.color = Color(1.0, 0.5, 0.8, 0.9)
		Direction.WEST: rect.color = Color(0.7, 1.0, 0.5, 0.9)
		_: rect.color = Color(0.6, 0.8, 1.0, 0.9)
	var lbl := get_node_or_null("Prompt") as Label
	if lbl:
		lbl.text = "[E] " + prompt_text

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"): return
	if _cooldown: return
	_player_in_range = true
	if auto_enter:
		_travel()
	else:
		$Prompt.visible = true

func _on_body_exited(body: Node2D) -> void:
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
	if target_scene == "":
		push_warning("Portal %s sin escena destino." % portal_id)
		return
	_cooldown = true
	$Prompt.visible = false
	MapManager.travel_to(target_scene, target_portal_id)
