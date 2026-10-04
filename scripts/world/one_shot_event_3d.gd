@tool
extends Area3D

@export var event_data: EventData
@export var trigger_on: TriggerMode = TriggerMode.ENTER_AREA

enum TriggerMode { ENTER_AREA, INTERACT }

var _done: bool = false
var _player_in_range: bool = false

func _ready() -> void:
	if Engine.is_editor_hint(): return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	$Prompt.visible = false
	if event_data and GameState.is_event_done(event_data.event_id):
		_done = true
		visible = false
		return
	if event_data and not _meets_conditions(event_data):
		visible = false
		monitoring = false

func _meets_conditions(d: EventData) -> bool:
	if d.requires_flag != "" and not Story.has_flag(d.requires_flag): return false
	if d.blocked_by_flag != "" and Story.has_flag(d.blocked_by_flag): return false
	if d.requires_chapter_at_least > 0 and not Story.chapter_at_least(d.requires_chapter_at_least): return false
	return true

func _on_body_entered(body: Node3D) -> void:
	if _done or event_data == null: return
	if not body.is_in_group("player"): return
	_player_in_range = true
	if trigger_on == TriggerMode.ENTER_AREA:
		_run()
	else:
		$Prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$Prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if trigger_on != TriggerMode.INTERACT: return
	if not _player_in_range or _done: return
	if DialogueManager.is_active(): return
	if event.is_action_pressed("interact"):
		_run()
		get_viewport().set_input_as_handled()

func _run() -> void:
	if event_data == null or _done: return
	_done = true
	GameState.mark_event_done(event_data.event_id)
	$Prompt.visible = false
	if event_data.trigger_dialogue:
		DialogueManager.start(event_data.trigger_dialogue)
		await DialogueManager.dialogue_ended
	if event_data.cutscene:
		await CutsceneRunner.play(event_data.cutscene)
	match event_data.action:
		EventData.EventAction.GIVE_ITEM:
			for it in event_data.reward_items: GameState.give_item(it)
		EventData.EventAction.GIVE_GOLD:
			GameState.add_gold(event_data.reward_gold)
		EventData.EventAction.RECRUIT:
			if event_data.recruit_actor: GameState.add_member(event_data.recruit_actor)
		EventData.EventAction.TELEPORT:
			if event_data.teleport_scene != "":
				get_tree().change_scene_to_file(event_data.teleport_scene)
				return
		EventData.EventAction.COMBAT:
			if event_data.combat_enemies.size() > 0:
				BattleLoader.start_battle(event_data.combat_enemies.duplicate(), get_tree().current_scene.scene_file_path)
				return
		_:
			pass
	if event_data.post_dialogue:
		DialogueManager.start(event_data.post_dialogue)
	visible = false
