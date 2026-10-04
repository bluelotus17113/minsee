@tool
extends Area3D

const SHOP_UI := "res://scenes/shop/shop_ui.tscn"
const INN_UI := "res://scenes/shop/inn_ui.tscn"
const RECRUIT_UI := "res://scenes/shop/recruit_ui.tscn"

@export var npc_data: NPCData:
	set(v):
		npc_data = v
		if is_inside_tree():
			_refresh_visual()
@export var override_dialogue: DialogueData
@export var greeting_done: bool = false

var _player_in_range: bool = false
var _busy: bool = false

func _ready() -> void:
	_refresh_visual()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	$Prompt.visible = false

func _refresh_visual() -> void:
	var sprite := get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null: return
	if npc_data and npc_data.sprite:
		sprite.texture = npc_data.sprite
		sprite.pixel_size = 0.04 if npc_data.sprite_size <= 32 else 0.025
		sprite.modulate = Color.WHITE
	else:
		sprite.modulate = npc_data.color if npc_data else Color(0.9, 0.85, 0.5)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		$Prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$Prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _busy: return
	if DialogueManager.is_active(): return
	if event.is_action_pressed("interact"):
		_trigger()
		get_viewport().set_input_as_handled()

func _trigger() -> void:
	if npc_data == null and override_dialogue == null:
		return
	if override_dialogue:
		DialogueManager.start(override_dialogue)
		return
	match npc_data.type:
		NPCData.NPCType.DIALOGUE:
			var dlg := npc_data.dialogue
			if greeting_done and npc_data.repeat_dialogue:
				dlg = npc_data.repeat_dialogue
			greeting_done = true
			if dlg: DialogueManager.start(dlg)
		NPCData.NPCType.QUEST:
			_open_quest()
		NPCData.NPCType.SHOP:
			_open_shop()
		NPCData.NPCType.INN:
			_open_inn()
		NPCData.NPCType.RECRUIT:
			_open_recruit()

func _open_shop() -> void:
	if npc_data == null or npc_data.shop_data == null: return
	_busy = true
	if npc_data.shop_intro_dialogue:
		DialogueManager.start(npc_data.shop_intro_dialogue)
		await DialogueManager.dialogue_ended
	var packed: PackedScene = load(SHOP_UI)
	if packed == null: _busy = false; return
	var ui := packed.instantiate()
	get_tree().current_scene.add_child(ui)
	ui.setup(npc_data.shop_data)
	await ui.closed
	_busy = false

func _open_inn() -> void:
	if npc_data == null: return
	_busy = true
	var packed: PackedScene = load(INN_UI)
	if packed == null: _busy = false; return
	var ui := packed.instantiate()
	get_tree().current_scene.add_child(ui)
	ui.setup(npc_data.npc_name, npc_data.inn_cost, npc_data.inn_prompt, npc_data.inn_success, npc_data.inn_no_gold)
	await ui.closed
	_busy = false

func _open_recruit() -> void:
	if npc_data == null or npc_data.recruit_actor == null: return
	_busy = true
	var packed: PackedScene = load(RECRUIT_UI)
	if packed == null: _busy = false; return
	var ui := packed.instantiate()
	get_tree().current_scene.add_child(ui)
	ui.setup(npc_data.npc_name, npc_data.recruit_actor, npc_data.recruit_cost, npc_data.recruit_pitch, npc_data.recruit_success, npc_data.recruit_no_gold, npc_data.recruit_already)
	await ui.closed
	_busy = false

func _open_quest() -> void:
	if npc_data == null or npc_data.quest == null:
		if npc_data and npc_data.dialogue:
			DialogueManager.start(npc_data.dialogue)
		return
	var q: Resource = npc_data.quest
	var status := GameState.quest_status(str(q.get("quest_id")))
	match status:
		"hidden":
			if npc_data.quest_offer_dialogue:
				DialogueManager.start(npc_data.quest_offer_dialogue)
				await DialogueManager.dialogue_ended
			GameState.start_quest(q)
		"active":
			if npc_data.auto_complete_on_talk:
				if npc_data.quest_complete_dialogue:
					DialogueManager.start(npc_data.quest_complete_dialogue)
					await DialogueManager.dialogue_ended
				GameState.complete_quest(q)
			elif npc_data.quest_active_dialogue:
				DialogueManager.start(npc_data.quest_active_dialogue)
		"completed":
			if npc_data.quest_done_dialogue:
				DialogueManager.start(npc_data.quest_done_dialogue)
			elif npc_data.dialogue:
				DialogueManager.start(npc_data.dialogue)
