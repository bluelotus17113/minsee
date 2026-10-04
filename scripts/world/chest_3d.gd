@tool
extends Area3D

@export var chest_data: ChestData

var _opened: bool = false
var _player_in_range: bool = false

func _ready() -> void:
	if Engine.is_editor_hint(): return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	$Prompt.visible = false
	if chest_data and GameState.is_chest_open(chest_data.chest_id):
		_opened = true
		_refresh_visual()

func _refresh_visual() -> void:
	var lid := get_node_or_null("Lid") as MeshInstance3D
	if lid:
		lid.rotation_degrees.x = -90.0 if _opened else 0.0

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _opened:
		_player_in_range = true
		$Prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$Prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _opened or DialogueManager.is_active(): return
	if event.is_action_pressed("interact"):
		_open()
		get_viewport().set_input_as_handled()

func _open() -> void:
	if chest_data == null: return
	_opened = true
	$Prompt.visible = false
	GameState.mark_chest_open(chest_data.chest_id)
	if chest_data.gold > 0:
		GameState.add_gold(chest_data.gold)
	for item in chest_data.items:
		GameState.give_item(item)
	_refresh_visual()
	if chest_data.open_dialogue:
		DialogueManager.start(chest_data.open_dialogue)
	else:
		var auto := DialogueData.new()
		auto.speaker_name = "Cofre"
		var contents: Array = []
		if chest_data.gold > 0:
			contents.append("%d oro" % chest_data.gold)
		for item in chest_data.items:
			if item: contents.append(item.item_name)
		auto.lines = PackedStringArray(["Has encontrado: " + (", ".join(contents) if contents.size() > 0 else "polvo")])
		DialogueManager.start(auto)
