extends Node

signal scene_changed(scene_path: String, portal_id: String)

var pending_portal_id: String = ""
var traveling: bool = false

func travel_to(target_scene: String, target_portal_id: String) -> void:
	if traveling: return
	if target_scene == "": return
	traveling = true
	pending_portal_id = target_portal_id
	# Fade out simple
	var fade := _make_fade()
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.18)
	await tween.finished
	get_tree().change_scene_to_file(target_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_position_player_at_portal(target_portal_id)
	scene_changed.emit(target_scene, target_portal_id)
	# Fade in
	var fade2 := _make_fade()
	fade2.color.a = 1.0
	var tween2 := create_tween()
	tween2.tween_property(fade2, "color:a", 0.0, 0.18)
	await tween2.finished
	if is_instance_valid(fade2) and fade2.get_parent():
		fade2.get_parent().queue_free()
	traveling = false
	pending_portal_id = ""

func _make_fade() -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := ColorRect.new()
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(layer)
	return rect

func _position_player_at_portal(portal_id: String) -> void:
	var scene := get_tree().current_scene
	if scene == null: return
	var portals: Array = []
	_collect_portals(scene, portals)
	for p in portals:
		if str(p.portal_id) == portal_id:
			var player_node := _find_player(scene)
			if player_node == null: return
			if player_node is Node3D and p is Node3D:
				var pos3d := (p as Node3D).global_position
				(player_node as Node3D).global_position = pos3d + Vector3(0, 0, 1.2)
			elif player_node is Node2D and p is Node2D:
				var pos2d := (p as Node2D).global_position
				(player_node as Node2D).global_position = pos2d + Vector2(0, 24)
			return

func _find_player(node: Node) -> Node:
	if node == null: return null
	if node.is_in_group("player"): return node
	var direct := node.get_node_or_null("Player")
	if direct: return direct
	for c in node.get_children():
		var f := _find_player(c)
		if f: return f
	return null

func _collect_portals(node: Node, out: Array) -> void:
	# Acepta tanto PortalNode (2D) como Area3D con script de portal 3D (tienen portal_id)
	if node is PortalNode:
		out.append(node)
	elif node is Area3D and "portal_id" in node and "target_scene" in node:
		out.append(node)
	for c in node.get_children():
		_collect_portals(c, out)
