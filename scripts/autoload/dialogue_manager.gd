extends Node

signal dialogue_started(data: DialogueData)
signal dialogue_ended
signal line_changed(speaker: String, text: String, portrait: Texture2D)

const UI_SCENE := "res://scenes/dialogue/dialogue_ui.tscn"

var current_data: DialogueData = null
var current_line_index: int = 0
var _active_ui: Node = null
var _ui_packed: PackedScene

func _ready() -> void:
	_ui_packed = load(UI_SCENE)

func is_active() -> bool:
	return current_data != null

func start(data: DialogueData) -> void:
	if data == null:
		return
	current_data = data
	current_line_index = 0
	if _active_ui == null and _ui_packed != null:
		_active_ui = _ui_packed.instantiate()
		get_tree().current_scene.add_child(_active_ui)
	dialogue_started.emit(data)
	_show_current_line()

func advance() -> void:
	if current_data == null:
		return
	current_line_index += 1
	_show_current_line()

func end() -> void:
	if _active_ui:
		_active_ui.queue_free()
		_active_ui = null
	current_data = null
	current_line_index = 0
	dialogue_ended.emit()

func _show_current_line() -> void:
	if current_data == null:
		return
	if current_line_index >= current_data.lines.size():
		if current_data.next_dialogue:
			current_data = current_data.next_dialogue
			current_line_index = 0
			_show_current_line()
		else:
			end()
		return
	var text: String = current_data.lines[current_line_index]
	line_changed.emit(current_data.speaker_name, text, current_data.portrait)
