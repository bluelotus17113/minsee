@tool
extends VBoxContainer

var editor_plugin: EditorPlugin

const SCAN_ROOTS := ["res://scenes/world", "res://scenes"]
const POSITIONS_PATH := "res://data/map_graph_positions.cfg"

var graph: GraphEdit
var info_label: Label
var bidir_check: CheckBox
var scene_nodes: Dictionary = {}       # scene_path -> GraphNode
var slot_to_portal_id: Dictionary = {} # scene_path -> Array[portal_id]
var node_name_to_scene: Dictionary = {} # StringName -> scene_path

func _init() -> void:
	custom_minimum_size = Vector2(0, 360)

func _ready() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var scan_btn := Button.new()
	scan_btn.text = "Escanear escenas"
	scan_btn.pressed.connect(_scan_and_draw)
	toolbar.add_child(scan_btn)
	var save_btn := Button.new()
	save_btn.text = "Guardar posiciones"
	save_btn.pressed.connect(_save_positions)
	toolbar.add_child(save_btn)
	var open_btn := Button.new()
	open_btn.text = "Abrir escena"
	open_btn.pressed.connect(_open_selected)
	toolbar.add_child(open_btn)
	bidir_check = CheckBox.new()
	bidir_check.text = "Bidireccional al conectar"
	bidir_check.button_pressed = true
	toolbar.add_child(bidir_check)
	info_label = Label.new()
	info_label.text = "Sin escanear."
	info_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.5))
	info_label.add_theme_font_size_override("font_size", 10)
	toolbar.add_child(info_label)
	graph = GraphEdit.new()
	graph.size_flags_vertical = SIZE_EXPAND_FILL
	graph.minimap_enabled = true
	graph.show_grid = true
	graph.right_disconnects = true
	add_child(graph)
	graph.connection_request.connect(_on_connection_request)
	graph.disconnection_request.connect(_on_disconnection_request)
	graph.connection_to_empty.connect(_on_connection_to_empty)

func _scan_and_draw() -> void:
	scene_nodes.clear()
	slot_to_portal_id.clear()
	node_name_to_scene.clear()
	for child in graph.get_children():
		if child is GraphNode:
			child.queue_free()
	graph.clear_connections()
	var portals := _collect_all_portals()
	var by_scene: Dictionary = {}
	for p in portals:
		var s: String = p["scene"]
		if not by_scene.has(s):
			by_scene[s] = []
		by_scene[s].append(p)
	if by_scene.is_empty():
		info_label.text = "No se encontraron PortalNode."
		return
	var positions := _load_positions()
	var col := 0
	for scene_path in by_scene.keys():
		var node := GraphNode.new()
		node.title = scene_path.get_file().get_basename()
		var nname := _safe_node_name(scene_path)
		node.name = nname
		node.set_meta("scene_path", scene_path)
		node.resizable = false
		var saved_pos: Vector2 = positions.get(scene_path, Vector2(col * 320, 80))
		node.position_offset = saved_pos
		col += 1
		var portal_list: Array = by_scene[scene_path]
		var ids: Array = []
		for i in portal_list.size():
			var p: Dictionary = portal_list[i]
			var row := HBoxContainer.new()
			var arrow := _dir_arrow(int(p.get("direction", 0)))
			var lbl := Label.new()
			lbl.text = "%s %s → %s" % [arrow, str(p["portal_id"]), str(p["target_portal_id"]) if str(p["target_portal_id"]) != "" else "(sin destino)"]
			lbl.add_theme_font_size_override("font_size", 10)
			row.add_child(lbl)
			node.add_child(row)
			var col_dir := _dir_color(int(p.get("direction", 0)))
			node.set_slot(i, true, 0, col_dir, true, 0, col_dir)
			ids.append(str(p["portal_id"]))
		slot_to_portal_id[scene_path] = ids
		scene_nodes[scene_path] = node
		node_name_to_scene[nname] = scene_path
		graph.add_child(node)
	# Crear conexiones según los target actuales
	var slot_indices: Dictionary = {}
	for scene_path in by_scene.keys():
		var map_p: Dictionary = {}
		var arr: Array = by_scene[scene_path]
		for i in arr.size():
			map_p[str(arr[i]["portal_id"])] = i
		slot_indices[scene_path] = map_p
	for scene_path in by_scene.keys():
		var arr: Array = by_scene[scene_path]
		for i in arr.size():
			var p: Dictionary = arr[i]
			var target_scene: String = str(p["target_scene"])
			var target_id: String = str(p["target_portal_id"])
			if target_scene == "" or not scene_nodes.has(target_scene):
				continue
			var to_slots: Dictionary = slot_indices[target_scene]
			if not to_slots.has(target_id):
				continue
			var from_name: StringName = scene_nodes[scene_path].name
			var to_name: StringName = scene_nodes[target_scene].name
			graph.connect_node(from_name, i, to_name, int(to_slots[target_id]))
	info_label.text = "Escaneadas %d escenas, %d portales. Arrastra puertos para reasignar." % [by_scene.size(), portals.size()]

# ---------- Edición por arrastre ----------

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var from_scene: String = node_name_to_scene.get(from_node, "")
	var to_scene: String = node_name_to_scene.get(to_node, "")
	if from_scene == "" or to_scene == "": return
	var from_portal_id: String = _slot_id(from_scene, from_port)
	var to_portal_id: String = _slot_id(to_scene, to_port)
	if from_portal_id == "" or to_portal_id == "": return
	# Reemplazar la conexión existente desde from_port (un portal solo tiene un target)
	for c in graph.get_connection_list():
		if c["from_node"] == from_node and c["from_port"] == from_port:
			graph.disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
	graph.connect_node(from_node, from_port, to_node, to_port)
	var ok := _modify_portal(from_scene, from_portal_id, to_scene, to_portal_id)
	if ok and bidir_check.button_pressed:
		# También conectar el destino al origen (si su slot estaba libre o tenía otro destino)
		for c in graph.get_connection_list():
			if c["from_node"] == to_node and c["from_port"] == to_port:
				graph.disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
		graph.connect_node(to_node, to_port, from_node, from_port)
		_modify_portal(to_scene, to_portal_id, from_scene, from_portal_id)
	info_label.text = "Conectado %s ⇄ %s" % [from_portal_id, to_portal_id] if bidir_check.button_pressed else "Conectado %s → %s" % [from_portal_id, to_portal_id]

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph.disconnect_node(from_node, from_port, to_node, to_port)
	var from_scene: String = node_name_to_scene.get(from_node, "")
	if from_scene == "": return
	var portal_id: String = _slot_id(from_scene, from_port)
	if portal_id == "": return
	_modify_portal(from_scene, portal_id, "", "")
	if bidir_check.button_pressed:
		var to_scene: String = node_name_to_scene.get(to_node, "")
		if to_scene != "":
			var tid: String = _slot_id(to_scene, to_port)
			if tid != "":
				_modify_portal(to_scene, tid, "", "")
	info_label.text = "Desconectado %s" % portal_id

var _pending_connection: Dictionary = {}

func _on_connection_to_empty(from_node: StringName, from_port: int, release_position: Vector2) -> void:
	_pending_connection = {
		"from_node": from_node,
		"from_port": from_port,
		"release_position": release_position,
	}
	_show_new_scene_dialog()

func _show_new_scene_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Nueva escena conectada"
	dlg.min_size = Vector2(380, 240)
	var vbox := VBoxContainer.new()
	dlg.add_child(vbox)

	var hint := Label.new()
	hint.text = "Se creará un .tscn nuevo en res://scenes/world/ con un PortalNode que regresa al origen."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.7, 0.85, 0.5))
	vbox.add_child(hint)

	var name_lbl := Label.new()
	name_lbl.text = "Nombre (sin .tscn):"
	vbox.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.text = "nueva_zona"
	vbox.add_child(name_edit)

	var dir_lbl := Label.new()
	dir_lbl.text = "Dirección del portal nuevo:"
	vbox.add_child(dir_lbl)
	var dir_opt := OptionButton.new()
	dir_opt.add_item("• Sin dirección", 0)
	dir_opt.add_item("↑ Norte", 1)
	dir_opt.add_item("↓ Sur", 2)
	dir_opt.add_item("→ Este", 3)
	dir_opt.add_item("← Oeste", 4)
	vbox.add_child(dir_opt)

	var tmpl_lbl := Label.new()
	tmpl_lbl.text = "Plantilla:"
	vbox.add_child(tmpl_lbl)
	var tmpl_opt := OptionButton.new()
	tmpl_opt.add_item("Interior (sala con paredes)", 0)
	tmpl_opt.add_item("Exterior (pueblo abierto)", 1)
	tmpl_opt.add_item("Vacía", 2)
	vbox.add_child(tmpl_opt)

	add_child(dlg)
	dlg.confirmed.connect(func():
		_create_connected_scene(name_edit.text.strip_edges(), dir_opt.get_selected_id(), tmpl_opt.get_selected_id())
		dlg.queue_free()
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
		_pending_connection.clear()
	)
	dlg.popup_centered()
	name_edit.grab_focus()

func _sanitize_filename(raw: String) -> String:
	var out := ""
	for c in raw.to_lower():
		if c == " " or c == "-":
			out += "_"
		elif (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			out += c
	if out == "":
		out = "nueva_zona"
	return out

func _create_connected_scene(raw_name: String, new_dir: int, template_id: int) -> void:
	if _pending_connection.is_empty():
		return
	var filename := _sanitize_filename(raw_name if raw_name != "" else "nueva_zona")
	var from_node: StringName = _pending_connection["from_node"]
	var from_port: int = _pending_connection["from_port"]
	var release_pos: Vector2 = _pending_connection.get("release_position", Vector2.ZERO)
	_pending_connection.clear()
	var from_scene: String = node_name_to_scene.get(from_node, "")
	if from_scene == "":
		info_label.text = "Origen desconocido."
		return
	var from_portal_id: String = _slot_id(from_scene, from_port)
	if from_portal_id == "":
		info_label.text = "Puerto origen inválido."
		return
	# Path nuevo en res://scenes/world/
	var dir_path := "res://scenes/world"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var new_path := "%s/%s.tscn" % [dir_path, filename]
	var counter := 1
	while FileAccess.file_exists(new_path):
		new_path = "%s/%s_%d.tscn" % [dir_path, filename, counter]
		counter += 1
	var new_portal_id := "entry_%s" % from_portal_id
	var ok := _create_new_scene_file(new_path, new_portal_id, from_scene, from_portal_id, new_dir, template_id)
	if not ok:
		info_label.text = "Error creando escena %s." % new_path
		return
	# Asignar el portal origen al destino nuevo
	_modify_portal(from_scene, from_portal_id, new_path, new_portal_id)
	# Persistir posición del nuevo nodo en el grafo en la zona donde soltó
	var positions := _load_positions()
	positions[new_path] = release_pos + graph.scroll_offset
	_save_position_dict(positions)
	_scan_and_draw()
	if editor_plugin:
		editor_plugin.get_editor_interface().get_resource_filesystem().scan()
	info_label.text = "Creada %s y conectada." % new_path

func _create_new_scene_file(path: String, portal_id: String, target_scene: String, target_portal_id: String, new_dir: int, template_id: int) -> bool:
	var root := Node2D.new()
	root.name = path.get_file().get_basename()

	# Background
	var bg := ColorRect.new()
	bg.name = "Floor"
	bg.offset_left = -180.0
	bg.offset_top = -120.0
	bg.offset_right = 180.0
	bg.offset_bottom = 120.0
	match template_id:
		1: bg.color = Color(0.18, 0.27, 0.15)  # Exterior verde
		2: bg.color = Color(0.10, 0.10, 0.14)  # Vacía oscura
		_: bg.color = Color(0.30, 0.22, 0.18)  # Interior cálida
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	bg.owner = root

	# Título
	var lbl := Label.new()
	lbl.name = "Title"
	lbl.text = root.name
	lbl.offset_left = -150.0
	lbl.offset_top = -110.0
	lbl.offset_right = 150.0
	lbl.offset_bottom = -94.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	root.add_child(lbl)
	lbl.owner = root

	# Hint
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "[E] sobre el portal para volver"
	hint.offset_left = -160.0
	hint.offset_top = -92.0
	hint.offset_right = 160.0
	hint.offset_bottom = -78.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	hint.add_theme_font_size_override("font_size", 10)
	root.add_child(hint)
	hint.owner = root

	# Player
	var player_packed: PackedScene = load("res://scenes/world/player.tscn")
	if player_packed:
		var player: Node = player_packed.instantiate()
		player.name = "Player"
		(player as Node2D).position = Vector2(0, 60)
		root.add_child(player)
		player.owner = root

	# Portal
	var portal_packed: PackedScene = load("res://scenes/world/portal_node.tscn")
	if portal_packed:
		var portal: Node = portal_packed.instantiate()
		portal.name = "PortalBack"
		(portal as Node2D).position = _portal_position_for_direction(new_dir)
		root.add_child(portal)
		portal.owner = root
		portal.set("portal_id", portal_id)
		portal.set("target_scene", target_scene)
		portal.set("target_portal_id", target_portal_id)
		portal.set("direction", new_dir)
		portal.set("prompt_text", "Volver")

	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err != OK:
		root.queue_free()
		return false
	var save_err: int = ResourceSaver.save(packed, path)
	root.queue_free()
	return save_err == OK

func _portal_position_for_direction(d: int) -> Vector2:
	match d:
		1: return Vector2(0, -90)   # Norte
		2: return Vector2(0, 90)    # Sur
		3: return Vector2(160, 0)   # Este
		4: return Vector2(-160, 0)  # Oeste
		_: return Vector2(0, -60)

func _save_position_dict(positions: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for k in positions:
		cfg.set_value("positions", k, positions[k])
	cfg.save(POSITIONS_PATH)

func _slot_id(scene_path: String, slot: int) -> String:
	var arr = slot_to_portal_id.get(scene_path, [])
	if slot < 0 or slot >= arr.size(): return ""
	return str(arr[slot])

func _modify_portal(scene_path: String, portal_id: String, target_scene: String, target_portal_id: String) -> bool:
	var packed := load(scene_path) as PackedScene
	if packed == null: return false
	var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if instance == null: return false
	var portals: Array = []
	_find_portals(instance, portals)
	var found: Node = null
	for p in portals:
		if str(p.portal_id) == portal_id:
			found = p
			break
	if found == null:
		instance.queue_free()
		return false
	found.target_scene = target_scene
	found.target_portal_id = target_portal_id
	var new_packed := PackedScene.new()
	var pack_err: int = new_packed.pack(instance)
	if pack_err != OK:
		instance.queue_free()
		return false
	var save_err: int = ResourceSaver.save(new_packed, scene_path)
	instance.queue_free()
	if save_err == OK and editor_plugin:
		# Notificar al editor que el archivo cambió
		editor_plugin.get_editor_interface().get_resource_filesystem().update_file(scene_path)
		# Si la escena está abierta en el editor, recargarla para evitar desincronización
		var ei := editor_plugin.get_editor_interface()
		var open_scenes: PackedStringArray = ei.get_open_scenes()
		if scene_path in open_scenes:
			ei.reload_scene_from_path(scene_path)
		return true
	return false

# ---------- Scan ----------

func _collect_all_portals() -> Array:
	var out: Array = []
	var scenes: Array = []
	for root in SCAN_ROOTS:
		scenes.append_array(_list_scenes(root))
	# Quitar duplicados manteniendo orden
	var seen: Dictionary = {}
	var unique: Array = []
	for s in scenes:
		if not seen.has(s):
			seen[s] = true
			unique.append(s)
	for path in unique:
		var packed: PackedScene = load(path)
		if packed == null: continue
		var instance: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		if instance == null: continue
		var portals: Array = []
		_find_portals(instance, portals)
		for p in portals:
			out.append({
				"scene": path,
				"portal_id": p.portal_id,
				"target_scene": p.target_scene,
				"target_portal_id": p.target_portal_id,
				"direction": p.direction,
			})
		instance.queue_free()
	return out

func _list_scenes(dir_path: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir() and not f.begins_with("."):
			out.append_array(_list_scenes(dir_path + "/" + f))
		elif f.ends_with(".tscn"):
			out.append(dir_path + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out

func _find_portals(node: Node, out: Array) -> void:
	if node is PortalNode:
		out.append(node)
	for c in node.get_children():
		_find_portals(c, out)

func _safe_node_name(scene_path: String) -> StringName:
	return StringName(scene_path.replace("/", "_").replace(":", "_").replace(".", "_"))

func _dir_arrow(direction: int) -> String:
	match direction:
		1: return "↑"
		2: return "↓"
		3: return "→"
		4: return "←"
		_: return "•"

func _dir_color(direction: int) -> Color:
	match direction:
		1: return Color(0.4, 0.85, 1.0)
		2: return Color(1.0, 0.7, 0.4)
		3: return Color(1.0, 0.5, 0.8)
		4: return Color(0.7, 1.0, 0.5)
		_: return Color(0.7, 0.85, 1.0)

func _open_selected() -> void:
	for n in graph.get_children():
		if n is GraphNode and n.selected:
			var sp: String = n.get_meta("scene_path", "")
			if sp != "" and editor_plugin:
				editor_plugin.get_editor_interface().open_scene_from_path(sp)
				return

func _save_positions() -> void:
	var cfg := ConfigFile.new()
	for sp in scene_nodes.keys():
		var node: GraphNode = scene_nodes[sp]
		cfg.set_value("positions", sp, node.position_offset)
	var err := cfg.save(POSITIONS_PATH)
	if err == OK:
		info_label.text = "Posiciones guardadas."
	else:
		info_label.text = "Error al guardar: %d" % err

func _load_positions() -> Dictionary:
	var out: Dictionary = {}
	var cfg := ConfigFile.new()
	if cfg.load(POSITIONS_PATH) != OK:
		return out
	for k in cfg.get_section_keys("positions"):
		out[k] = cfg.get_value("positions", k)
	return out
