extends Node

signal cutscene_started(id: String)
signal cutscene_finished(id: String)

var running: bool = false
var current_id: String = ""

func is_active() -> bool:
	return running

func play(cutscene: CutsceneData) -> void:
	if running or cutscene == null:
		return
	if cutscene.run_once and Story.has_flag("_cutscene_done:" + cutscene.cutscene_id):
		return
	running = true
	current_id = cutscene.cutscene_id
	cutscene_started.emit(current_id)
	for step in cutscene.steps:
		if step == null: continue
		var aborted := await _execute(step)
		if aborted:
			break
	if cutscene.run_once:
		Story.set_flag("_cutscene_done:" + cutscene.cutscene_id, true)
	cutscene_finished.emit(current_id)
	running = false
	current_id = ""

func _execute(step: CutsceneStep) -> bool:
	match step.type:
		CutsceneStep.StepType.SAY:
			var dlg := DialogueData.new()
			dlg.speaker_name = step.speaker_name
			dlg.lines = PackedStringArray([step.text])
			DialogueManager.start(dlg)
			await DialogueManager.dialogue_ended
		CutsceneStep.StepType.WAIT:
			await get_tree().create_timer(max(0.01, step.wait_seconds)).timeout
		CutsceneStep.StepType.SET_FLAG:
			Story.set_flag(step.flag_key, step.flag_value)
		CutsceneStep.StepType.CLEAR_FLAG:
			Story.clear_flag(step.flag_key)
		CutsceneStep.StepType.ADVANCE_CHAPTER:
			Story.advance_chapter(step.chapter_to)
		CutsceneStep.StepType.GIVE_ITEM:
			if step.item:
				GameState.give_item(step.item)
		CutsceneStep.StepType.GIVE_GOLD:
			GameState.add_gold(step.gold)
		CutsceneStep.StepType.PLAY_DIALOGUE:
			if step.dialogue:
				DialogueManager.start(step.dialogue)
				await DialogueManager.dialogue_ended
		CutsceneStep.StepType.CHANGE_SCENE:
			if step.scene_path != "":
				MapManager.travel_to(step.scene_path, step.portal_id)
				await MapManager.scene_changed
		CutsceneStep.StepType.FADE_OUT:
			await _fade(true, step.fade_seconds)
		CutsceneStep.StepType.FADE_IN:
			await _fade(false, step.fade_seconds)
		CutsceneStep.StepType.MOVE_NODE:
			var n := _resolve_node(step.target_node_path)
			if n and n is Node2D:
				var node2d := n as Node2D
				var dist := node2d.position.distance_to(step.target_position)
				var duration: float = clamp(dist / max(1.0, step.move_speed), 0.1, 4.0)
				var tw := create_tween()
				tw.tween_property(node2d, "position", step.target_position, duration)
				await tw.finished
		CutsceneStep.StepType.HIDE_NODE:
			var n := _resolve_node(step.target_node_path)
			if n: n.visible = false
		CutsceneStep.StepType.SHOW_NODE:
			var n := _resolve_node(step.target_node_path)
			if n: n.visible = true
		CutsceneStep.StepType.START_BATTLE:
			if step.enemies.size() > 0:
				BattleLoader.start_battle(step.enemies.duplicate(), get_tree().current_scene.scene_file_path)
		CutsceneStep.StepType.REQUIRE_FLAG:
			if not Story.has_flag(step.flag_key):
				return true  # abortar
	return false

func _resolve_node(p: NodePath) -> Node:
	var scene := get_tree().current_scene
	if scene == null or p.is_empty(): return null
	return scene.get_node_or_null(p)

func _fade(out: bool, seconds: float) -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var rect := ColorRect.new()
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.color = Color(0, 0, 0, 1.0 if not out else 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(layer)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 1.0 if out else 0.0, max(0.05, seconds))
	await tw.finished
	if not out and is_instance_valid(layer):
		layer.queue_free()
	return rect
