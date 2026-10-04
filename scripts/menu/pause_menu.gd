extends CanvasLayer

signal closed

@onready var tabs: TabContainer = $Backdrop/Panel/VBox/Tabs
@onready var status_list: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Estado/Scroll/VBox
@onready var items_list: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Items/Scroll/VBox
@onready var equip_list: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Equipo/Scroll/VBox
@onready var skills_list: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Habilidades/Scroll/VBox
@onready var quests_list: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Quests/Scroll/VBox
@onready var affinity_list: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Vínculos/Scroll/VBox
@onready var tree_list: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Árbol/Scroll/VBox
@onready var bestiary_list: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Bestiario/Scroll/VBox
@onready var formation_box: VBoxContainer = $Backdrop/Panel/VBox/Tabs/Formación/VBox
@onready var sys_save_slot1: Button = $Backdrop/Panel/VBox/Tabs/Sistema/VBox/SaveBtns/Slot1
@onready var sys_save_slot2: Button = $Backdrop/Panel/VBox/Tabs/Sistema/VBox/SaveBtns/Slot2
@onready var sys_save_slot3: Button = $Backdrop/Panel/VBox/Tabs/Sistema/VBox/SaveBtns/Slot3
@onready var sys_main_menu: Button = $Backdrop/Panel/VBox/Tabs/Sistema/VBox/MainMenuBtn
@onready var sys_close: Button = $Backdrop/Panel/VBox/Footer/Close
@onready var gold_label: Label = $Backdrop/Panel/VBox/Header/Gold
@onready var chapter_label: Label = $Backdrop/Panel/VBox/Header/Chapter
@onready var status_msg: Label = $Backdrop/Panel/VBox/Tabs/Sistema/VBox/Status

func _ready() -> void:
	sys_close.pressed.connect(close)
	sys_save_slot1.pressed.connect(_on_save.bind(1))
	sys_save_slot2.pressed.connect(_on_save.bind(2))
	sys_save_slot3.pressed.connect(_on_save.bind(3))
	sys_main_menu.pressed.connect(_on_main_menu)
	GameState.gold_changed.connect(_on_gold)
	_on_gold(GameState.gold)
	chapter_label.text = "Cap %d" % Story.current_chapter
	_refresh()
	status_msg.text = ""

func _on_gold(amount: int) -> void:
	gold_label.text = "Oro: %d" % amount

func _refresh() -> void:
	_build_status()
	_build_items()
	_build_equip()
	_build_skills()
	_build_quests()
	_build_affinity()
	_build_tree()
	_build_bestiary()
	_build_formation()
	for slot in [1, 2, 3]:
		var btn := [sys_save_slot1, sys_save_slot2, sys_save_slot3][slot - 1]
		btn.text = SaveManager.format_slot(slot)

func _build_bestiary() -> void:
	for c in bestiary_list.get_children(): c.queue_free()
	if GameState.bestiary.is_empty():
		var none := Label.new()
		none.text = "Sin entradas. Pelea para descubrir enemigos."
		bestiary_list.add_child(none)
		return
	for path in GameState.bestiary.keys():
		var entry: Dictionary = GameState.bestiary[path]
		var data: EnemyData = load(path) as EnemyData
		if data == null: continue
		var hdr := Label.new()
		hdr.text = "%s · KO ×%d" % [data.enemy_name, int(entry.get("kills", 0))]
		hdr.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		bestiary_list.add_child(hdr)
		var stats := Label.new()
		stats.text = "  HP %d · ATK %d · DEF %d · MAG %d · SPD %d" % [data.max_hp, data.attack, data.defense, data.magic, data.speed]
		stats.add_theme_font_size_override("font_size", 10)
		bestiary_list.add_child(stats)
		var weak := _format_flags("Débil", data.weaknesses_flags)
		var resi := _format_flags("Resiste", data.resistances_flags)
		var imm := _format_flags("Inmune", data.immunities_flags)
		for s in [weak, resi, imm]:
			if s != "":
				var lbl := Label.new()
				lbl.text = "  " + s
				lbl.add_theme_font_size_override("font_size", 10)
				lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 1))
				bestiary_list.add_child(lbl)
		bestiary_list.add_child(HSeparator.new())

func _format_flags(prefix: String, flags: int) -> String:
	if flags == 0: return ""
	var names := ["Físico", "Fuego", "Agua", "Hielo", "Rayo", "Tierra", "Viento", "Sagrado", "Sombra", "Arcano"]
	var found: Array = []
	for i in names.size():
		if (flags & (1 << i)) != 0:
			found.append(names[i])
	if found.is_empty(): return ""
	return "%s: %s" % [prefix, ", ".join(found)]

func _build_formation() -> void:
	for c in formation_box.get_children(): c.queue_free()
	var hdr := Label.new()
	hdr.text = "Formación de batalla (4 activos)"
	hdr.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	formation_box.add_child(hdr)
	var sub := Label.new()
	sub.text = "Activos:"
	formation_box.add_child(sub)
	for i in GameState.party.size():
		var a := GameState.party[i]
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "  %d. %s" % [i + 1, a.actor_name]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if GameState.reserve.size() > 0 and GameState.party.size() > 1:
			var bench := Button.new()
			bench.text = "Banca"
			bench.pressed.connect(func():
				GameState.bench_active(i)
				_refresh()
			)
			row.add_child(bench)
		formation_box.add_child(row)
	formation_box.add_child(HSeparator.new())
	var sub2 := Label.new()
	sub2.text = "Reserva:"
	formation_box.add_child(sub2)
	if GameState.reserve.is_empty():
		var lbl := Label.new()
		lbl.text = "  (vacía)"
		formation_box.add_child(lbl)
		return
	for i in GameState.reserve.size():
		var a := GameState.reserve[i]
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "  · %s" % a.actor_name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var activate := Button.new()
		activate.text = "Activar"
		activate.disabled = GameState.party.size() >= GameState.MAX_ACTIVE_PARTY
		activate.pressed.connect(func():
			GameState.activate_reserve(i)
			_refresh()
		)
		row.add_child(activate)
		formation_box.add_child(row)

func _build_tree() -> void:
	for c in tree_list.get_children(): c.queue_free()
	if GameState.party.is_empty():
		var none := Label.new()
		none.text = "Sin party."
		tree_list.add_child(none)
		return
	for actor in GameState.party:
		var hdr := Label.new()
		hdr.text = "%s · SP %d" % [actor.actor_name, GameState.get_sp(actor.actor_name)]
		hdr.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		tree_list.add_child(hdr)
		var tree: SkillTreeData = actor.skill_tree
		if tree == null or tree.entries.is_empty():
			var lbl := Label.new()
			lbl.text = "  (Sin árbol asignado)"
			tree_list.add_child(lbl)
			continue
		var unlocked_idx := GameState.unlocked_index(actor.actor_name)
		for i in tree.entries.size():
			var entry: SkillTreeEntry = tree.entries[i]
			if entry == null or entry.skill == null: continue
			var row := HBoxContainer.new()
			var prefix := "✓ " if i <= unlocked_idx else ("» " if i == unlocked_idx + 1 else "  ")
			var lbl := Label.new()
			lbl.text = "%s%s  (SP %d)" % [prefix, entry.skill.skill_name, entry.sp_cost]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 11)
			if i <= unlocked_idx:
				lbl.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
			row.add_child(lbl)
			if i == unlocked_idx + 1:
				var btn := Button.new()
				btn.text = "Desbloquear"
				btn.disabled = not GameState.can_unlock_next(actor)
				btn.pressed.connect(func():
					GameState.unlock_next(actor)
					_refresh()
				)
				row.add_child(btn)
			tree_list.add_child(row)
		tree_list.add_child(HSeparator.new())

func _build_quests() -> void:
	for c in quests_list.get_children(): c.queue_free()
	var active := GameState.active_quests()
	var done := GameState.completed_quests()
	if active.is_empty() and done.is_empty():
		var none := Label.new()
		none.text = "Sin misiones aún."
		quests_list.add_child(none)
		return
	if active.size() > 0:
		var h := Label.new()
		h.text = "Activas"
		h.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		quests_list.add_child(h)
		for qid in active:
			var entry: Dictionary = GameState.quests[qid]
			var path := str(entry.get("data_path", ""))
			var qr: Resource = load(path) if path != "" else null
			var title := str(qr.get("title")) if qr else qid
			var desc := str(qr.get("description")) if qr else ""
			var lbl := Label.new()
			lbl.text = "• %s\n  %s" % [title, desc]
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			quests_list.add_child(lbl)
	if done.size() > 0:
		var h2 := Label.new()
		h2.text = "Completadas"
		h2.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
		quests_list.add_child(h2)
		for qid in done:
			var entry: Dictionary = GameState.quests[qid]
			var path := str(entry.get("data_path", ""))
			var qr: Resource = load(path) if path != "" else null
			var title := str(qr.get("title")) if qr else qid
			var lbl := Label.new()
			lbl.text = "✓ %s" % title
			lbl.add_theme_font_size_override("font_size", 11)
			quests_list.add_child(lbl)

func _build_affinity() -> void:
	for c in affinity_list.get_children(): c.queue_free()
	if GameState.party.size() < 2:
		var none := Label.new()
		none.text = "Recluta a un aliado para ver vínculos."
		affinity_list.add_child(none)
		return
	for i in GameState.party.size():
		for j in range(i + 1, GameState.party.size()):
			var a := GameState.party[i].actor_name
			var b := GameState.party[j].actor_name
			var lvl := GameState.get_affinity(a, b)
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = "%s · %s" % [a, b]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var bar := ProgressBar.new()
			bar.min_value = 0
			bar.max_value = 100
			bar.value = lvl
			bar.custom_minimum_size = Vector2(140, 14)
			bar.show_percentage = false
			row.add_child(bar)
			var val := Label.new()
			val.text = " %d" % lvl
			row.add_child(val)
			affinity_list.add_child(row)

func _build_status() -> void:
	for c in status_list.get_children(): c.queue_free()
	for a in GameState.party:
		var hp := a.current_hp if a.current_hp >= 0 else a.max_hp
		var mp := a.current_mp if a.current_mp >= 0 else a.max_mp
		var lbl := Label.new()
		lbl.text = "%s · Nv %d (%d / %d EXP)\nHP %d/%d  MP %d/%d\nATK %d · DEF %d · MAG %d · SPD %d · LUK %d" % [a.actor_name, a.level, a.current_exp, a.exp_to_next(), hp, a.max_hp, mp, a.max_mp, a.attack, a.defense, a.magic, a.speed, a.luck]
		lbl.add_theme_font_size_override("font_size", 12)
		status_list.add_child(lbl)
		var sep := HSeparator.new()
		status_list.add_child(sep)

func _build_items() -> void:
	for c in items_list.get_children(): c.queue_free()
	var seen: Dictionary = {}
	for a in GameState.party:
		for item in a.inventory:
			if item == null: continue
			if seen.has(item.item_name):
				seen[item.item_name] += 1
			else:
				seen[item.item_name] = 1
	if seen.is_empty():
		var lbl := Label.new()
		lbl.text = "Inventario vacío."
		items_list.add_child(lbl)
		return
	for name in seen.keys():
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s ×%d" % [name, seen[name]]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		items_list.add_child(row)

func _build_equip() -> void:
	for c in equip_list.get_children(): c.queue_free()
	for a in GameState.party:
		var row := Label.new()
		var weapon_name := a.weapon.weapon_name if a.weapon else "(sin arma)"
		row.text = "%s · arma: %s" % [a.actor_name, weapon_name]
		equip_list.add_child(row)

func _build_skills() -> void:
	for c in skills_list.get_children(): c.queue_free()
	for a in GameState.party:
		var header := Label.new()
		header.text = a.actor_name
		header.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		skills_list.add_child(header)
		if a.skills.is_empty():
			var none := Label.new()
			none.text = "  (sin habilidades)"
			skills_list.add_child(none)
		for s in a.skills:
			var lbl := Label.new()
			var kind := "Art" if s.kind == SkillData.Kind.ART else "Craft"
			var cost := "MP %d" % s.mp_cost if s.kind == SkillData.Kind.ART else "CP %d" % s.cp_cost
			lbl.text = "  [%s] %s · %s · rng %d" % [kind, s.skill_name, cost, s.skill_range]
			lbl.add_theme_font_size_override("font_size", 11)
			skills_list.add_child(lbl)
		skills_list.add_child(HSeparator.new())

func _on_save(slot: int) -> void:
	if SaveManager.save_to_slot(slot):
		status_msg.text = "Guardado en slot %d." % slot
		_refresh()
	else:
		status_msg.text = "No se pudo guardar."

func _on_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")

func close() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") or event.is_action_pressed("open_menu"):
		close()
		get_viewport().set_input_as_handled()
