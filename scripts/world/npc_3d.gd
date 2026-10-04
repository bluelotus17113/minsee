@tool
extends Area3D

const SHOP_UI := "res://scenes/shop/shop_ui.tscn"
## Si un NPCData no trae modelo se usa éste, para que no quede invisible.
const FALLBACK_MODEL := "res://scenes/world/3d/chars/aldeano.glb"
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
	var holder := get_node_or_null("Model") as Node3D
	if holder == null:
		push_warning("npc_3d: falta el nodo Model; el NPC se quedaría invisible.")
		return
	for child in holder.get_children():
		child.queue_free()
		holder.remove_child(child)

	var packed: PackedScene = npc_data.model if npc_data else null
	if packed == null:
		# Sin modelo el NPC sería un área invisible con la que se puede hablar:
		# un fallo que no da error y no se ve hasta jugar.
		push_warning("npc_3d: %s no tiene modelo, se usa el de reserva." %
			(npc_data.npc_name if npc_data else "(sin datos)"))
		packed = load(FALLBACK_MODEL)
	if packed == null:
		return

	var inst := packed.instantiate()
	holder.add_child(inst)
	if Engine.is_editor_hint():
		inst.owner = get_tree().edited_scene_root
	ToonSkin.skin(inst)
	var anim := _find_anim(inst)
	if anim:
		for name in anim.get_animation_list():
			var a := anim.get_animation(name)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
		if anim.has_animation("idle"):
			anim.play("idle")

func _find_anim(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_anim(child)
		if found:
			return found
	return null

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
