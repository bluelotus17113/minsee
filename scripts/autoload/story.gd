extends Node

signal flag_changed(key: String, value: Variant)
signal chapter_changed(chapter: int)

var current_chapter: int = 1
var flags: Dictionary = {}

func has_flag(key: String) -> bool:
	if not flags.has(key): return false
	var v = flags[key]
	if typeof(v) == TYPE_BOOL: return v
	if typeof(v) == TYPE_INT: return v != 0
	return v != null

func get_flag(key: String, default = null):
	return flags.get(key, default)

func set_flag(key: String, value = true) -> void:
	flags[key] = value
	flag_changed.emit(key, value)

func clear_flag(key: String) -> void:
	flags.erase(key)
	flag_changed.emit(key, null)

func advance_chapter(to: int = -1) -> void:
	if to >= 0:
		current_chapter = to
	else:
		current_chapter += 1
	chapter_changed.emit(current_chapter)

func is_chapter(n: int) -> bool:
	return current_chapter == n

func chapter_at_least(n: int) -> bool:
	return current_chapter >= n

func reset() -> void:
	current_chapter = 1
	flags.clear()

func to_dict() -> Dictionary:
	return { "chapter": current_chapter, "flags": flags.duplicate(true) }

func from_dict(data: Dictionary) -> void:
	current_chapter = int(data.get("chapter", 1))
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	chapter_changed.emit(current_chapter)
