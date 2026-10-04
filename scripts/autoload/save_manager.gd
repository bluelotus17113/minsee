extends Node

const SAVE_DIR := "user://saves"
const SLOTS := 3
const TIME_KEY := "time_played"
const SAVE_VERSION := 2

signal saved(slot: int)
signal loaded(slot: int)

var session_start_time: float = 0.0
var accumulated_time: float = 0.0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	session_start_time = Time.get_unix_time_from_system()

func _slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

func get_slot_info(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var f := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if f == null: return {}
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}

func save_to_slot(slot: int) -> bool:
	var data := _serialize_state()
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	saved.emit(slot)
	return true

func load_from_slot(slot: int) -> bool:
	var data := get_slot_info(slot)
	if data.is_empty():
		return false
	_apply_state(data)
	loaded.emit(slot)
	if data.has("scene_path") and str(data["scene_path"]) != "":
		get_tree().change_scene_to_file(str(data["scene_path"]))
	return true

func _serialize_actor(a: ActorStats) -> Dictionary:
	return {
		"resource_path": a.resource_path if a.resource_path != "" else "",
		"actor_name": a.actor_name,
		"level": a.level,
		"current_exp": a.current_exp,
		"current_hp": a.current_hp,
		"current_mp": a.current_mp,
		"max_hp": a.max_hp,
		"max_mp": a.max_mp,
		"max_cp": a.max_cp,
		"attack": a.attack,
		"defense": a.defense,
		"magic": a.magic,
		"speed": a.speed,
		"luck": a.luck,
		"inventory_paths": _inventory_to_paths(a.inventory),
	}

func _inventory_to_paths(inv: Array) -> Array:
	var out: Array = []
	for it in inv:
		if it and it.resource_path != "":
			out.append(it.resource_path)
	return out

func _serialize_state() -> Dictionary:
	var party_data: Array = []
	for a in GameState.party:
		party_data.append(_serialize_actor(a))
	var reserve_data: Array = []
	for a in GameState.reserve:
		reserve_data.append(_serialize_actor(a))
	var scene_path := ""
	var pos2 := Vector2.ZERO
	var pos3 := Vector3.ZERO
	var is_3d := false
	var current_scene := get_tree().current_scene
	if current_scene:
		scene_path = current_scene.scene_file_path
		var player := current_scene.get_node_or_null("Player")
		if player and player is Node3D:
			pos3 = (player as Node3D).position
			is_3d = true
		elif player and player is Node2D:
			pos2 = (player as Node2D).position
	return {
		"version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"time_played": _current_time_played(),
		"gold": GameState.gold,
		"party": party_data,
		"reserve": reserve_data,
		"scene_path": scene_path,
		"is_3d": is_3d,
		"player_x": pos2.x if not is_3d else pos3.x,
		"player_y": pos2.y if not is_3d else pos3.y,
		"player_z": pos3.z,
		"opened_chests": GameState.opened_chests,
		"completed_events": GameState.completed_events,
		"bestiary": GameState.bestiary,
		"quests": GameState.quests,
		"affinity": GameState.affinity,
		"skill_points": GameState.skill_points,
		"unlocked_tree_index": GameState.unlocked_tree_index,
		"story": Story.to_dict(),
	}

func _apply_actor_to(actor: ActorStats, entry: Dictionary) -> void:
	actor.level = int(entry.get("level", 1))
	actor.current_exp = int(entry.get("current_exp", 0))
	actor.current_hp = int(entry.get("current_hp", -1))
	actor.current_mp = int(entry.get("current_mp", -1))
	if entry.has("max_hp"): actor.max_hp = int(entry["max_hp"])
	if entry.has("max_mp"): actor.max_mp = int(entry["max_mp"])
	if entry.has("max_cp"): actor.max_cp = int(entry["max_cp"])
	if entry.has("attack"): actor.attack = int(entry["attack"])
	if entry.has("defense"): actor.defense = int(entry["defense"])
	if entry.has("magic"): actor.magic = int(entry["magic"])
	if entry.has("speed"): actor.speed = int(entry["speed"])
	if entry.has("luck"): actor.luck = int(entry["luck"])
	var inv_paths: Array = entry.get("inventory_paths", [])
	if inv_paths.size() > 0:
		actor.inventory.clear()
		for p in inv_paths:
			var it := load(str(p)) as ItemData
			if it != null:
				actor.inventory.append(it)

func _restore_actor(entry: Dictionary) -> ActorStats:
	var path := str(entry.get("resource_path", ""))
	if path == "":
		return null
	var actor := load(path) as ActorStats
	if actor == null:
		return null
	_apply_actor_to(actor, entry)
	return actor

func _apply_state(data: Dictionary) -> void:
	GameState.gold = int(data.get("gold", 0))
	GameState.party.clear()
	GameState.reserve.clear()
	for entry in data.get("party", []):
		var a := _restore_actor(entry)
		if a: GameState.party.append(a)
	for entry in data.get("reserve", []):
		var a := _restore_actor(entry)
		if a: GameState.reserve.append(a)
	GameState.party_position = Vector2(float(data.get("player_x", 0)), float(data.get("player_y", 0)))
	GameState.opened_chests = (data.get("opened_chests", {}) as Dictionary).duplicate(true)
	GameState.completed_events = (data.get("completed_events", {}) as Dictionary).duplicate(true)
	GameState.bestiary = (data.get("bestiary", {}) as Dictionary).duplicate(true)
	GameState.quests = (data.get("quests", {}) as Dictionary).duplicate(true)
	GameState.affinity = (data.get("affinity", {}) as Dictionary).duplicate(true)
	GameState.skill_points = (data.get("skill_points", {}) as Dictionary).duplicate(true)
	GameState.unlocked_tree_index = (data.get("unlocked_tree_index", {}) as Dictionary).duplicate(true)
	Story.from_dict(data.get("story", {}))
	accumulated_time = float(data.get(TIME_KEY, 0.0))
	session_start_time = Time.get_unix_time_from_system()
	GameState.party_changed.emit()
	GameState.gold_changed.emit(GameState.gold)

func _current_time_played() -> float:
	return accumulated_time + (Time.get_unix_time_from_system() - session_start_time)

func format_time(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total / 60) % 60
	var s := total % 60
	return "%02d:%02d:%02d" % [h, m, s]

func format_slot(slot: int) -> String:
	if not has_slot(slot):
		return "Slot %d - vacío" % slot
	var data := get_slot_info(slot)
	var party_data: Array = data.get("party", [])
	var name := "—"
	var level := 1
	if party_data.size() > 0:
		name = str(party_data[0].get("actor_name", "—"))
		level = int(party_data[0].get("level", 1))
	var ch := int(data.get("story", {}).get("chapter", 1))
	var t := format_time(float(data.get(TIME_KEY, 0.0)))
	var gold := int(data.get("gold", 0))
	return "Slot %d · %s Nv%d · Cap %d · %s · %d oro" % [slot, name, level, ch, t, gold]
