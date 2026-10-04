@tool
extends EditorPlugin

var dock: Control

func _enter_tree() -> void:
	dock = preload("res://addons/minsee_map/map_dock.gd").new()
	dock.name = "MinSee Map"
	dock.editor_plugin = self
	add_control_to_bottom_panel(dock, "MinSee Map")

func _exit_tree() -> void:
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
		dock = null
