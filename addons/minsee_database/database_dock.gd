@tool
extends VBoxContainer

var editor_plugin: EditorPlugin

const ENEMY_OVERWORLD_SCENE := "res://scenes/world/enemy_overworld.tscn"
const NPC_SCENE := "res://scenes/world/npc.tscn"
const CHEST_SCENE := "res://scenes/world/chest.tscn"
const EVENT_SCENE := "res://scenes/world/one_shot_event.tscn"
const ZONE_SCENE := "res://scenes/world/random_encounter_zone.tscn"

const CATEGORIES := [
	{ "label": "Items", "dir": "res://data/items", "script": "res://scripts/data/item_data.gd", "ext": "tres", "spawnable": false, "sprite_prop": "icon", "anim_prop": "" },
	{ "label": "Armas", "dir": "res://data/weapons", "script": "res://scripts/data/weapon_data.gd", "ext": "tres", "spawnable": false, "sprite_prop": "icon", "anim_prop": "" },
	{ "label": "Habilidades", "dir": "res://data/skills", "script": "res://scripts/data/skill_data.gd", "ext": "tres", "spawnable": false, "sprite_prop": "icon", "anim_prop": "" },
	{ "label": "Enemigos", "dir": "res://data/enemies", "script": "res://scripts/data/enemy_data.gd", "ext": "tres", "spawnable": true, "sprite_prop": "sprite", "anim_prop": "animations" },
	{ "label": "Encuentros", "dir": "res://data/encounters", "script": "res://scripts/data/encounter_data.gd", "ext": "tres", "spawnable": true, "sprite_prop": "background", "anim_prop": "" },
	{ "label": "Actores", "dir": "res://data/actors", "script": "res://scripts/data/actor_stats.gd", "ext": "tres", "spawnable": false, "sprite_prop": "sprite", "anim_prop": "animations" },
	{ "label": "NPCs", "dir": "res://data/npcs", "script": "res://scripts/data/npc_data.gd", "ext": "tres", "spawnable": true, "sprite_prop": "sprite", "anim_prop": "animations" },
	{ "label": "Diálogos", "dir": "res://data/dialogues", "script": "res://scripts/data/dialogue_data.gd", "ext": "tres", "spawnable": false, "sprite_prop": "portrait", "anim_prop": "" },
	{ "label": "Tiendas", "dir": "res://data/shops", "script": "res://scripts/data/shop_data.gd", "ext": "tres", "spawnable": false, "sprite_prop": "", "anim_prop": "" },
	{ "label": "Cofres", "dir": "res://data/chests", "script": "res://scripts/data/chest_data.gd", "ext": "tres", "spawnable": true, "sprite_prop": "sprite", "anim_prop": "" },
	{ "label": "Eventos", "dir": "res://data/events", "script": "res://scripts/data/event_data.gd", "ext": "tres", "spawnable": true, "sprite_prop": "", "anim_prop": "" },
	{ "label": "Quests", "dir": "res://data/quests", "script": "res://scripts/data/quest_data.gd", "ext": "tres", "spawnable": false, "sprite_prop": "", "anim_prop": "" },
	{ "label": "Skill Trees", "dir": "res://data/skill_trees", "script": "res://scripts/data/skill_tree_data.gd", "ext": "tres", "spawnable": false, "sprite_prop": "", "anim_prop": "" },
	{ "label": "Cutscenes", "dir": "res://data/cutscenes", "script": "res://scripts/data/cutscene_data.gd", "ext": "tres", "spawnable": false, "sprite_prop": "", "anim_prop": "" },
	{ "label": "Encuentro-Tablas", "dir": "res://data/encounter_tables", "script": "res://scripts/data/encounter_table_data.gd", "ext": "tres", "spawnable": true, "sprite_prop": "", "anim_prop": "" },
]

var tabs: TabContainer
var lists: Array[ItemList] = []
var paths_per_tab: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(240, 360)

func _ready() -> void:
	_build_ui()
	_refresh_all()

func _build_ui() -> void:
	var header := Label.new()
	header.text = "MinSee Database"
	header.add_theme_font_size_override("font_size", 14)
	add_child(header)

	var refresh_btn := Button.new()
	refresh_btn.text = "Recargar"
	refresh_btn.pressed.connect(_refresh_all)
	add_child(refresh_btn)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(tabs)

	for i in CATEGORIES.size():
		var cat: Dictionary = CATEGORIES[i]
		var page := VBoxContainer.new()
		page.name = cat["label"]
		tabs.add_child(page)

		var item_list := ItemList.new()
		item_list.size_flags_vertical = SIZE_EXPAND_FILL
		item_list.allow_rmb_select = true
		page.add_child(item_list)
		item_list.item_activated.connect(_on_item_activated.bind(i))
		item_list.item_selected.connect(_on_item_selected.bind(i))
		lists.append(item_list)
		paths_per_tab.append([])

		var row1 := HBoxContainer.new()
		page.add_child(row1)

		var new_btn := Button.new()
		new_btn.text = "Nuevo"
		new_btn.pressed.connect(_on_new_pressed.bind(i))
		row1.add_child(new_btn)

		var dup_btn := Button.new()
		dup_btn.text = "Duplicar"
		dup_btn.pressed.connect(_on_duplicate_pressed.bind(i))
		row1.add_child(dup_btn)

		var edit_btn := Button.new()
		edit_btn.text = "Editar"
		edit_btn.pressed.connect(_on_edit_pressed.bind(i))
		row1.add_child(edit_btn)

		var del_btn := Button.new()
		del_btn.text = "Borrar"
		del_btn.pressed.connect(_on_delete_pressed.bind(i))
		row1.add_child(del_btn)

		var media_row := HBoxContainer.new()
		page.add_child(media_row)

		if str(cat.get("sprite_prop", "")) != "":
			var spr_btn := Button.new()
			spr_btn.text = "Sprite..."
			spr_btn.tooltip_text = "Elegir textura (PNG/JPG/WebP) para este recurso."
			spr_btn.pressed.connect(_on_pick_sprite_pressed.bind(i))
			media_row.add_child(spr_btn)

		if str(cat.get("anim_prop", "")) != "":
			var anim_btn := Button.new()
			anim_btn.text = "Animaciones..."
			anim_btn.tooltip_text = "Asignar SpriteFrames (.tres) para animaciones."
			anim_btn.pressed.connect(_on_pick_animations_pressed.bind(i))
			media_row.add_child(anim_btn)

		if cat.get("spawnable", false):
			var spawn_btn := Button.new()
			spawn_btn.text = "+ Mapa"
			spawn_btn.tooltip_text = "Añade un EnemyOverworld al mapa abierto con este recurso asignado."
			spawn_btn.pressed.connect(_on_spawn_pressed.bind(i))
			media_row.add_child(spawn_btn)

		var path_label := Label.new()
		path_label.name = "PathLabel"
		path_label.text = cat["dir"]
		path_label.add_theme_font_size_override("font_size", 10)
		page.add_child(path_label)

func _refresh_all() -> void:
	for i in CATEGORIES.size():
		_refresh_category(i)

func _refresh_category(index: int) -> void:
	var cat: Dictionary = CATEGORIES[index]
	var list: ItemList = lists[index]
	list.clear()
	var dir_path: String = cat["dir"]
	var ext: String = cat["ext"]
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var files: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.ends_with("." + ext):
				files.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	files.sort()
	paths_per_tab[index] = []
	list.fixed_icon_size = Vector2i(28, 28)
	for fname in files:
		var full := dir_path + "/" + fname
		var label := fname
		var res := load(full)
		if res:
			var nice := _nice_name(res)
			if nice != "":
				label = "%s  (%s)" % [nice, fname]
		var item_index := list.add_item(label)
		paths_per_tab[index].append(full)
		if res:
			var preview := _extract_preview(res)
			if preview:
				list.set_item_icon(item_index, preview)

func _nice_name(res: Resource) -> String:
	for prop in ["item_name", "weapon_name", "skill_name", "enemy_name", "actor_name", "encounter_name", "npc_name", "dialogue_id", "shop_name", "label", "chest_id", "event_id", "title", "quest_id", "tree_name", "cutscene_id", "table_name"]:
		if prop in res:
			return str(res.get(prop))
	return ""

func _extract_preview(res: Resource) -> Texture2D:
	# Animaciones tienen prioridad
	if "animations" in res:
		var frames = res.get("animations")
		if frames is SpriteFrames:
			var anim_name: String = res.get("default_animation") if "default_animation" in res else "idle"
			if frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0:
				return frames.get_frame_texture(anim_name, 0)
			# Cualquier animación con frames
			for a in frames.get_animation_names():
				if frames.get_frame_count(a) > 0:
					return frames.get_frame_texture(a, 0)
	for prop in ["icon", "sprite", "portrait", "background"]:
		if prop in res:
			var tex = res.get(prop)
			if tex is Texture2D:
				return tex
	# Encounter: usar el primer enemigo
	if "enemies" in res:
		var arr = res.get("enemies")
		if arr is Array and arr.size() > 0 and arr[0] != null:
			return _extract_preview(arr[0])
	return null

func _on_item_selected(_idx: int, _tab_index: int) -> void:
	pass

func _on_item_activated(idx: int, tab_index: int) -> void:
	_open_in_inspector(tab_index, idx)

func _on_edit_pressed(tab_index: int) -> void:
	var sel := lists[tab_index].get_selected_items()
	if sel.is_empty():
		_toast("Selecciona un recurso primero.")
		return
	_open_in_inspector(tab_index, sel[0])

func _open_in_inspector(tab_index: int, item_idx: int) -> void:
	var path: String = paths_per_tab[tab_index][item_idx]
	var res := load(path)
	if res and editor_plugin:
		editor_plugin.get_editor_interface().edit_resource(res)
		editor_plugin.get_editor_interface().get_file_system_dock().navigate_to_path(path)

# ---------- Nuevo con prompt ----------

func _on_new_pressed(tab_index: int) -> void:
	var cat: Dictionary = CATEGORIES[tab_index]
	var dialog := AcceptDialog.new()
	dialog.title = "Nuevo " + str(cat["label"])
	dialog.min_size = Vector2(320, 110)
	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)
	var lbl := Label.new()
	lbl.text = "Nombre del archivo (sin extensión):"
	vbox.add_child(lbl)
	var line := LineEdit.new()
	line.placeholder_text = "nombre_amigable"
	line.text = str(cat["label"]).to_lower().trim_suffix("s")
	vbox.add_child(line)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var raw := line.text.strip_edges()
		if raw == "":
			raw = str(cat["label"]).to_lower()
		var sanitized := _sanitize_name(raw)
		var save_name := _unique_name(cat["dir"], sanitized, cat["ext"])
		var script: Script = load(cat["script"])
		if script == null:
			printerr("[MinSee DB] No se pudo cargar script: ", cat["script"])
			dialog.queue_free()
			return
		var res: Resource = script.new()
		var save_path: String = "%s/%s.%s" % [cat["dir"], save_name, cat["ext"]]
		ResourceSaver.save(res, save_path)
		_refresh_category(tab_index)
		_select_path(tab_index, save_path)
		var sel := lists[tab_index].get_selected_items()
		if not sel.is_empty():
			_open_in_inspector(tab_index, sel[0])
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
	line.grab_focus()

func _sanitize_name(raw: String) -> String:
	var out := ""
	for c in raw.to_lower():
		if c == " " or c == "-":
			out += "_"
		elif (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			out += c
	if out == "":
		out = "recurso"
	return out

# ---------- Duplicar / borrar ----------

func _on_duplicate_pressed(tab_index: int) -> void:
	var sel := lists[tab_index].get_selected_items()
	if sel.is_empty():
		_toast("Selecciona un recurso primero.")
		return
	var path: String = paths_per_tab[tab_index][sel[0]]
	var res: Resource = load(path)
	if res == null:
		return
	var copy: Resource = res.duplicate(true)
	var cat: Dictionary = CATEGORIES[tab_index]
	var base := path.get_file().get_basename()
	var save_name := _unique_name(cat["dir"], base + "_copy", cat["ext"])
	var save_path: String = "%s/%s.%s" % [cat["dir"], save_name, cat["ext"]]
	ResourceSaver.save(copy, save_path)
	_refresh_category(tab_index)
	_select_path(tab_index, save_path)

func _on_delete_pressed(tab_index: int) -> void:
	var sel := lists[tab_index].get_selected_items()
	if sel.is_empty():
		_toast("Selecciona un recurso primero.")
		return
	var path: String = paths_per_tab[tab_index][sel[0]]
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "¿Eliminar %s?" % path
	add_child(confirm)
	confirm.confirmed.connect(func():
		var dir_path := path.get_base_dir()
		var dir := DirAccess.open(dir_path)
		if dir:
			dir.remove(path.get_file())
		_refresh_category(tab_index)
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	confirm.popup_centered()

# ---------- Spawn en mapa ----------

func _on_spawn_pressed(tab_index: int) -> void:
	var sel := lists[tab_index].get_selected_items()
	if sel.is_empty():
		_toast("Selecciona un enemigo o encuentro primero.")
		return
	var path: String = paths_per_tab[tab_index][sel[0]]
	var res: Resource = load(path)
	if res == null:
		return
	if editor_plugin == null:
		return
	var edited_root := editor_plugin.get_editor_interface().get_edited_scene_root()
	if edited_root == null:
		_toast("Abre una escena (ej. world.tscn) primero.")
		return
	var scene_path: String = ENEMY_OVERWORLD_SCENE
	if res is NPCData:
		scene_path = NPC_SCENE
	elif res is ChestData:
		scene_path = CHEST_SCENE
	elif res is EventData:
		scene_path = EVENT_SCENE
	elif res is EncounterTableData:
		scene_path = ZONE_SCENE
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_toast("Falta " + scene_path)
		return
	var instance := packed.instantiate()
	if res is EncounterData:
		instance.set("encounter", res)
	elif res is EnemyData:
		var arr: Array[EnemyData] = [res]
		instance.set("enemies", arr)
	elif res is NPCData:
		instance.set("npc_data", res)
	elif res is ChestData:
		instance.set("chest_data", res)
	elif res is EventData:
		instance.set("event_data", res)
	elif res is EncounterTableData:
		instance.set("encounter_table", res)
	# Posición: cerca del centro de la escena con un offset aleatorio leve
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	instance.position = Vector2(rng.randf_range(-80, 80), rng.randf_range(-60, 60))
	var nice_name := _nice_name(res)
	if nice_name != "":
		instance.name = nice_name.replace(" ", "_")
	edited_root.add_child(instance)
	instance.set_owner(edited_root)
	editor_plugin.get_editor_interface().get_selection().clear()
	editor_plugin.get_editor_interface().get_selection().add_node(instance)
	_toast("Añadido al mapa. Recuerda guardar la escena (Ctrl+S).")

# ---------- Helpers ----------

func _unique_name(dir_path: String, base: String, ext: String) -> String:
	var candidate := base
	var idx := 1
	while FileAccess.file_exists("%s/%s.%s" % [dir_path, candidate, ext]):
		candidate = "%s_%d" % [base, idx]
		idx += 1
	return candidate

func _select_path(tab_index: int, path: String) -> void:
	for i in paths_per_tab[tab_index].size():
		if paths_per_tab[tab_index][i] == path:
			lists[tab_index].select(i)
			return

func _on_pick_sprite_pressed(tab_index: int) -> void:
	var cat: Dictionary = CATEGORIES[tab_index]
	var prop: String = str(cat.get("sprite_prop", ""))
	if prop == "":
		return
	var sel := lists[tab_index].get_selected_items()
	if sel.is_empty():
		_toast("Selecciona un recurso primero.")
		return
	var res_path: String = paths_per_tab[tab_index][sel[0]]
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Elegir Sprite"
	dialog.add_filter("*.png ; PNG")
	dialog.add_filter("*.jpg, *.jpeg ; JPG")
	dialog.add_filter("*.webp ; WebP")
	dialog.add_filter("*.svg ; SVG")
	dialog.add_filter("*.tres ; Resource (Texture)")
	dialog.size = Vector2(720, 480)
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var tex := load(path) as Texture2D
		if tex == null:
			_toast("Ese archivo no es una textura válida.")
		else:
			var res: Resource = load(res_path)
			if res:
				res.set(prop, tex)
				ResourceSaver.save(res, res_path)
				_refresh_category(tab_index)
				_select_path(tab_index, res_path)
				_toast("Sprite asignado.")
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _on_pick_animations_pressed(tab_index: int) -> void:
	var cat: Dictionary = CATEGORIES[tab_index]
	var prop: String = str(cat.get("anim_prop", ""))
	if prop == "":
		return
	var sel := lists[tab_index].get_selected_items()
	if sel.is_empty():
		_toast("Selecciona un recurso primero.")
		return
	var res_path: String = paths_per_tab[tab_index][sel[0]]
	var menu := PopupMenu.new()
	menu.add_item("Asignar SpriteFrames existente (.tres)", 0)
	menu.add_item("Crear SpriteFrames vacío y abrir editor", 1)
	add_child(menu)
	menu.id_pressed.connect(func(id: int):
		menu.queue_free()
		if id == 0:
			_open_spriteframes_picker(tab_index, res_path, prop)
		else:
			_create_empty_spriteframes(tab_index, res_path, prop)
	)
	menu.popup_centered()

func _open_spriteframes_picker(tab_index: int, res_path: String, prop: String) -> void:
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Elegir SpriteFrames"
	dialog.add_filter("*.tres ; SpriteFrames Resource")
	dialog.add_filter("*.res ; Resource")
	dialog.size = Vector2(720, 480)
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var frames := load(path) as SpriteFrames
		if frames == null:
			_toast("No es un SpriteFrames válido.")
		else:
			var res: Resource = load(res_path)
			if res:
				res.set(prop, frames)
				ResourceSaver.save(res, res_path)
				_refresh_category(tab_index)
				_select_path(tab_index, res_path)
				_toast("Animaciones asignadas.")
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _create_empty_spriteframes(tab_index: int, res_path: String, prop: String) -> void:
	var frames := SpriteFrames.new()
	# SpriteFrames trae "default" como animación por defecto; renombramos a "idle"
	if frames.has_animation("default"):
		frames.rename_animation("default", "idle")
	else:
		frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 6)
	var dir_path := res_path.get_base_dir() + "/sprites"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var base := res_path.get_file().get_basename() + "_frames"
	var save_name := _unique_name(dir_path, base, "tres")
	var save_path := "%s/%s.tres" % [dir_path, save_name]
	ResourceSaver.save(frames, save_path)
	var loaded := load(save_path) as SpriteFrames
	var res: Resource = load(res_path)
	if res and loaded:
		res.set(prop, loaded)
		ResourceSaver.save(res, res_path)
		_refresh_category(tab_index)
		_select_path(tab_index, res_path)
		if editor_plugin:
			editor_plugin.get_editor_interface().edit_resource(loaded)
		_toast("SpriteFrames creado en " + save_path + " — agrega frames y guarda.")

func _toast(msg: String) -> void:
	if editor_plugin and editor_plugin.get_editor_interface().get_editor_toaster():
		editor_plugin.get_editor_interface().get_editor_toaster().push_toast(msg)
	else:
		print("[MinSee DB] ", msg)
