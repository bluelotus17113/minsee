extends Control

const WORLD_SCENE := "res://scenes/world/3d/patio_pueblo_3d.tscn"
const DEBUG_SCENE := "res://scenes/debug/debug_map.tscn"
const LOAD_PANEL := preload("res://scenes/menu/load_panel.tscn")
const OPTIONS_PANEL := preload("res://scenes/menu/options_panel.tscn")

@onready var title: Label = $Title
@onready var subtitle: Label = $Subtitle
@onready var btn_continue: Button = $Center/VBox/Continue
@onready var btn_new: Button = $Center/VBox/NewGame
@onready var btn_load: Button = $Center/VBox/Load
@onready var btn_options: Button = $Center/VBox/Options
@onready var btn_debug: Button = $Center/VBox/Debug
@onready var btn_quit: Button = $Center/VBox/Quit
@onready var version_label: Label = $VersionLabel

func _ready() -> void:
	btn_continue.pressed.connect(_on_continue)
	btn_new.pressed.connect(_on_new)
	btn_load.pressed.connect(_on_load)
	btn_options.pressed.connect(_on_options)
	btn_debug.pressed.connect(_on_debug)
	btn_quit.pressed.connect(_on_quit)
	version_label.text = "MinSee v0.1 — Demo"
	btn_continue.visible = _latest_slot() > 0
	_animate_in()

func _latest_slot() -> int:
	var best := 0
	var best_ts := 0.0
	for s in [1, 2, 3]:
		if SaveManager.has_slot(s):
			var info := SaveManager.get_slot_info(s)
			var ts := float(info.get("timestamp", 0))
			if ts > best_ts:
				best_ts = ts
				best = s
	return best

func _animate_in() -> void:
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	for b in [btn_continue, btn_new, btn_load, btn_options, btn_debug, btn_quit]:
		b.modulate.a = 0.0
		b.position.x -= 40
	var tween := create_tween()
	tween.tween_property(title, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(subtitle, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	var buttons := [btn_continue, btn_new, btn_load, btn_options, btn_debug, btn_quit]
	for b in buttons:
		if not b.visible: continue
		tween.parallel().tween_property(b, "modulate:a", 1.0, 0.4)
		tween.tween_property(b, "position:x", b.position.x + 40, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if btn_continue.visible:
		btn_continue.grab_focus.call_deferred()
	else:
		btn_new.grab_focus.call_deferred()

func _on_continue() -> void:
	var slot := _latest_slot()
	if slot > 0:
		SaveManager.load_from_slot(slot)

func _on_new() -> void:
	GameState.party.clear()
	GameState.reserve.clear()
	GameState.gold = 100
	GameState._init_default_party()
	get_tree().change_scene_to_file(WORLD_SCENE)

func _on_debug() -> void:
	GameState.party.clear()
	GameState.reserve.clear()
	GameState.gold = 500
	GameState._init_default_party()
	get_tree().change_scene_to_file(DEBUG_SCENE)

func _on_load() -> void:
	var panel := LOAD_PANEL.instantiate()
	add_child(panel)

func _on_options() -> void:
	var panel := OPTIONS_PANEL.instantiate()
	add_child(panel)

func _on_quit() -> void:
	get_tree().quit()
