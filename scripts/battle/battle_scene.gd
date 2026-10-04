extends Node2D

const TILE_SIZE := 32
const GRID_OFFSET := Vector2(160, 30)

enum Phase { IDLE, CHOOSE_MOVE, CHOOSE_ACTION, PICK_TARGET_ATTACK, PICK_TARGET_SKILL, PICK_SKILL }

@onready var manager: BattleManager = $BattleManager
@onready var grid_node: Node2D = $GridLayer
@onready var battlers_node: Node2D = $BattlersLayer
@onready var highlight_node: Node2D = $HighlightLayer
@onready var hover_node: Node2D = $HoverLayer
@onready var log_label: RichTextLabel = $UI/BottomPanel/VBox/LogPanel/LogLabel
@onready var action_panel: Panel = $UI/BottomPanel/VBox/ActionPanel
@onready var btn_move: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Move
@onready var btn_attack: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Attack
@onready var btn_art: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Art
@onready var btn_craft: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Craft
@onready var btn_defend: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Defend
@onready var btn_item: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Item
@onready var btn_wait: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Wait
@onready var btn_run: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Run
@onready var skill_panel: Panel = $UI/SkillPanel
@onready var skill_list: VBoxContainer = $UI/SkillPanel/VBox/List
@onready var skill_title: Label = $UI/SkillPanel/VBox/Title
@onready var status_box: VBoxContainer = $UI/StatusPanel/VBox
@onready var atb_box: VBoxContainer = $UI/ATBPanel/VBox
@onready var turn_label: Label = $UI/TurnLabel
@onready var prompt_label: Label = $UI/PromptLabel
@onready var auto_btn: CheckButton = $UI/AutoBtn

var battler_views: Dictionary = {}
var phase: int = Phase.IDLE
var pending_skill: SkillData = null
var pending_kind: int = -1
var pending_item: ItemData = null
var has_moved: bool = false

var _hover_cell: Vector2i = Vector2i(-999, -999)
var _hover_rect: ColorRect = null
var _hover_tween: Tween = null
var _active_marker: ColorRect = null
var _active_tween: Tween = null
var auto_battle: bool = false

func _ready() -> void:
	skill_panel.visible = false
	action_panel.visible = false
	prompt_label.text = ""
	auto_btn.toggled.connect(_on_auto_toggled)
	manager.log_message.connect(_on_log)
	manager.need_player_action.connect(_on_need_action)
	manager.battle_ended.connect(_on_battle_ended)
	manager.stats_changed.connect(_refresh_stats)
	manager.turn_started.connect(_on_turn_started)
	manager.grid_changed.connect(_refresh_grid_positions)
	manager.preview_changed.connect(_refresh_atb)
	var party := GameState.party
	var enemies := GameState.pending_battle_enemies
	if enemies.is_empty():
		enemies = [_default_enemy()]
	manager.setup(party, enemies)
	_draw_grid()
	_build_status_panel()
	_spawn_battler_views()
	_refresh_grid_positions()
	_refresh_stats()
	_refresh_atb()
	manager.start()

func _default_enemy() -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = "Slime"
	return e

# ---------- Render grid y battlers ----------

func _draw_grid() -> void:
	for child in grid_node.get_children():
		child.queue_free()
	for y in BattleGrid.HEIGHT:
		for x in BattleGrid.WIDTH:
			var tile := ColorRect.new()
			tile.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
			tile.position = GRID_OFFSET + Vector2(x * TILE_SIZE + 1, y * TILE_SIZE + 1)
			var dark := (x + y) % 2 == 0
			tile.color = Color(0.12, 0.10, 0.16) if dark else Color(0.16, 0.13, 0.22)
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid_node.add_child(tile)

func _cell_to_pos(cell: Vector2i) -> Vector2:
	return GRID_OFFSET + Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2, cell.y * TILE_SIZE + TILE_SIZE / 2)

func _pos_to_cell(pos: Vector2) -> Vector2i:
	var local := pos - GRID_OFFSET
	return Vector2i(int(local.x / TILE_SIZE), int(local.y / TILE_SIZE))

func _spawn_battler_views() -> void:
	for child in battlers_node.get_children():
		child.queue_free()
	battler_views.clear()
	for b in manager.allies + manager.enemies:
		var view := _make_token(b)
		battlers_node.add_child(view)
		battler_views[b] = view
		b.damage_taken.connect(_on_battler_damaged.bind(b))
		b.healed.connect(_on_battler_healed.bind(b))
		b.break_triggered.connect(_on_battler_broken.bind(b))

func _make_token(b: Battler) -> Node2D:
	var root := Node2D.new()
	var visual_size: int = b.sprite_size if b.sprite_size > 0 else 24
	var half: float = float(visual_size) / 2.0
	if b.animations != null and b.animations.has_animation(b.default_animation):
		var anim := AnimatedSprite2D.new()
		anim.sprite_frames = b.animations
		anim.animation = b.default_animation
		anim.autoplay = b.default_animation
		anim.play()
		anim.centered = true
		root.add_child(anim)
	elif b.sprite != null:
		var spr := Sprite2D.new()
		spr.texture = b.sprite
		spr.centered = true
		# Escalar al tamaño deseado
		var tex_w := float(b.sprite.get_width())
		if tex_w > 0:
			spr.scale = Vector2.ONE * (float(visual_size) / tex_w)
		root.add_child(spr)
	else:
		var rect := ColorRect.new()
		rect.size = Vector2(visual_size - 4, visual_size - 4)
		rect.position = Vector2(-half + 2, -half + 2)
		rect.color = b.color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(rect)
		var lbl := Label.new()
		lbl.text = b.display_name[0] if b.display_name.length() > 0 else "?"
		lbl.position = Vector2(-6, -10)
		lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(lbl)
	var hp_lbl := Label.new()
	hp_lbl.name = "HPLabel"
	hp_lbl.position = Vector2(-16, 14)
	hp_lbl.add_theme_font_size_override("font_size", 9)
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_lbl)
	var br_bg := ColorRect.new()
	br_bg.name = "BreakBG"
	br_bg.size = Vector2(26, 3)
	br_bg.position = Vector2(-13, 26)
	br_bg.color = Color(0.1, 0.1, 0.2, 0.7)
	br_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(br_bg)
	var br_fill := ColorRect.new()
	br_fill.name = "BreakFill"
	br_fill.size = Vector2(0, 3)
	br_fill.position = Vector2(-13, 26)
	br_fill.color = Color(0.3, 0.7, 1, 1)
	br_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(br_fill)
	var br_lbl := Label.new()
	br_lbl.name = "BreakLabel"
	br_lbl.position = Vector2(-18, -36)
	br_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1))
	br_lbl.add_theme_font_size_override("font_size", 9)
	br_lbl.text = ""
	br_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(br_lbl)
	var cast_lbl := Label.new()
	cast_lbl.name = "CastLabel"
	cast_lbl.position = Vector2(-16, -26)
	cast_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 1))
	cast_lbl.add_theme_font_size_override("font_size", 9)
	cast_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cast_lbl)
	return root

func _refresh_grid_positions() -> void:
	for b in battler_views.keys():
		var view: Node2D = battler_views[b]
		var target := _cell_to_pos(b.grid_pos)
		var tween := create_tween()
		tween.tween_property(view, "position", target, 0.18)
		view.modulate = Color(1,1,1,1) if b.is_alive() else Color(0.3,0.3,0.3,0.4)
		var cast_lbl := view.get_node_or_null("CastLabel") as Label
		if cast_lbl:
			if b.is_casting and b.pending_skill:
				cast_lbl.text = "▷ %s" % b.pending_skill.skill_name
			else:
				cast_lbl.text = ""
	_move_active_marker()

# ---------- Status / ATB ----------

func _build_status_panel() -> void:
	for child in status_box.get_children():
		child.queue_free()
	for b in manager.allies:
		var row := Label.new()
		row.name = "Status_" + b.display_name
		row.add_theme_font_size_override("font_size", 10)
		status_box.add_child(row)

func _refresh_stats() -> void:
	for b in manager.allies:
		var lbl := status_box.get_node_or_null("Status_" + b.display_name) as Label
		if lbl:
			lbl.text = "%s\nHP %d/%d\nMP %d/%d\nCP %d/%d" % [b.display_name, b.hp, b.max_hp, b.mp, b.max_mp, b.cp, b.max_cp]
	for b in battler_views.keys():
		var view: Node2D = battler_views[b]
		var hp_lbl := view.get_node_or_null("HPLabel") as Label
		if hp_lbl:
			hp_lbl.text = "%d/%d" % [b.hp, b.max_hp]
		var br_fill := view.get_node_or_null("BreakFill") as ColorRect
		if br_fill:
			var pct: float = float(b.break_gauge) / max(1.0, float(b.break_threshold))
			br_fill.size.x = clamp(pct, 0.0, 1.0) * 26.0
			br_fill.color = Color(1.0, 0.55, 0.2) if b.broken else Color(0.3, 0.7, 1.0)
		var br_lbl := view.get_node_or_null("BreakLabel") as Label
		if br_lbl:
			br_lbl.text = "BREAK!" if b.broken else ""
		if b.broken:
			view.modulate = Color(0.7, 0.9, 1.2, 1)
		else:
			view.modulate = Color(1,1,1,1) if b.is_alive() else Color(0.3,0.3,0.3,0.4)

func _refresh_atb() -> void:
	for child in atb_box.get_children():
		child.queue_free()
	if manager.queue == null: return
	var slots := manager.queue.preview(8)
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var b: Battler = slot["battler"]
		var bonus: int = slot.get("bonus", TurnQueue.TurnBonus.NONE)
		var row := HBoxContainer.new()
		var idx := Label.new()
		idx.text = "%d." % (i + 1)
		idx.add_theme_font_size_override("font_size", 10)
		row.add_child(idx)
		var dot := ColorRect.new()
		dot.color = b.color
		dot.custom_minimum_size = Vector2(10, 10)
		row.add_child(dot)
		var name_lbl := Label.new()
		name_lbl.text = " " + b.display_name
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 1) if b.is_player else Color(1, 0.6, 0.6))
		row.add_child(name_lbl)
		var label := manager.queue.bonus_label(bonus)
		if label != "":
			var b_lbl := Label.new()
			b_lbl.text = " [" + label + "]"
			b_lbl.add_theme_color_override("font_color", manager.queue.bonus_color(bonus))
			b_lbl.add_theme_font_size_override("font_size", 10)
			row.add_child(b_lbl)
		atb_box.add_child(row)

# ---------- Turno y prompts ----------

func _on_turn_started(b: Battler, _bonus: int) -> void:
	turn_label.text = "Turno: %s" % b.display_name
	_clear_highlights()
	_clear_hover()
	_set_active_marker(b)
	_refresh_atb()

func _on_need_action(b: Battler) -> void:
	if auto_battle:
		action_panel.visible = false
		skill_panel.visible = false
		_clear_highlights()
		_clear_hover()
		prompt_label.text = "AUTO: %s actúa solo" % b.display_name
		await get_tree().create_timer(0.25).timeout
		manager.auto_play_player(b)
		return
	action_panel.visible = true
	skill_panel.visible = false
	has_moved = false
	phase = Phase.CHOOSE_ACTION
	prompt_label.text = "Mover (opcional) → elige acción o Esperar para pasar"
	btn_move.disabled = false
	_clear_highlights()
	_clear_hover()

func _on_auto_toggled(on: bool) -> void:
	auto_battle = on
	if on and manager.current and manager.current.is_player and action_panel.visible:
		# Activar inmediatamente si estábamos esperando
		action_panel.visible = false
		_clear_highlights()
		_clear_hover()
		prompt_label.text = "AUTO activado"
		manager.auto_play_player(manager.current)

func _on_battle_ended(victory: bool) -> void:
	action_panel.visible = false
	skill_panel.visible = false
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	if _active_marker:
		_active_marker.queue_free()
		_active_marker = null
	_on_log("[b]" + ("VICTORIA" if victory else "DERROTA") + "[/b]")
	await get_tree().create_timer(1.5).timeout
	BattleLoader.end_battle(victory)

func _on_log(text: String) -> void:
	log_label.append_text(text + "\n")

func _on_battler_damaged(amount: int, was_crit: bool, was_weak: bool, b: Battler) -> void:
	var pos := _cell_to_pos(b.grid_pos) + Vector2(0, -16)
	var color := Color(1, 1, 1)
	var size := 12
	if was_crit:
		color = Color(1, 0.5, 0.4)
		size = 16
	if was_weak:
		color = Color(1, 0.7, 0.3)
		size = 14
	_spawn_floating_number("-%d" % amount, pos, color, size)
	if was_crit or was_weak:
		_screen_shake(4.0, 0.18)

func _on_battler_healed(amount: int, b: Battler) -> void:
	var pos := _cell_to_pos(b.grid_pos) + Vector2(0, -16)
	_spawn_floating_number("+%d" % amount, pos, Color(0.4, 1, 0.4), 12)

func _on_battler_broken(b: Battler) -> void:
	var pos := _cell_to_pos(b.grid_pos) + Vector2(0, -32)
	_spawn_floating_number("BREAK!", pos, Color(0.4, 0.85, 1), 16)
	_screen_shake(6.0, 0.3)

func _spawn_floating_number(text: String, world_pos: Vector2, color: Color, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.position = world_pos + Vector2(-20, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_node.add_child(lbl)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var jitter_x := rng.randf_range(-6.0, 6.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(lbl, "position:y", world_pos.y - 32, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "position:x", world_pos.x - 20 + jitter_x, 0.65)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.65).set_delay(0.25)
	tween.chain().tween_callback(lbl.queue_free)

func _screen_shake(amount: float, duration: float) -> void:
	var orig := Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var steps := 6
	var step_time := duration / float(steps)
	var tween := create_tween()
	for i in steps:
		var offset := Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))
		tween.tween_property(self, "position", offset, step_time)
	tween.tween_property(self, "position", orig, step_time)

# ---------- Botones ----------

func _on_move_pressed() -> void:
	if has_moved or manager.current == null: return
	phase = Phase.CHOOSE_MOVE
	prompt_label.text = "Click en celda azul para moverse (Esc cancela)"
	_show_move_range(manager.current)

func _on_attack_pressed() -> void:
	if manager.current == null: return
	# Comprobar si hay al menos un enemigo en rango melee
	var has_target := false
	for e in manager.enemies:
		if e.is_alive() and manager.grid.chebyshev(manager.current.grid_pos, e.grid_pos) <= manager.current.melee_range:
			has_target = true
			break
	if not has_target:
		prompt_label.text = "Ningún enemigo en rango melee. Usa Mover primero o elige Arts/Crafts."
		return
	phase = Phase.PICK_TARGET_ATTACK
	prompt_label.text = "Click sobre el enemigo resaltado en rojo"
	_show_attack_targets(manager.current)

func _on_art_pressed() -> void:
	_open_skill_picker(SkillData.Kind.ART)

func _on_craft_pressed() -> void:
	_open_skill_picker(SkillData.Kind.CRAFT)

func _on_defend_pressed() -> void:
	action_panel.visible = false
	_clear_hover()
	_clear_highlights()
	manager.submit_defend()

func _on_item_pressed() -> void:
	if manager.current == null: return
	var inv: Array = manager.current.actor_stats.inventory if manager.current.actor_stats else []
	if inv.is_empty():
		prompt_label.text = "Sin ítems en el inventario."
		return
	skill_panel.visible = true
	skill_title.text = "Ítems"
	for child in skill_list.get_children(): child.queue_free()
	# Agrupar por item_name
	var counts: Dictionary = {}
	var sample: Dictionary = {}
	for it in inv:
		if it == null: continue
		counts[it.item_name] = counts.get(it.item_name, 0) + 1
		sample[it.item_name] = it
	for name in counts.keys():
		var it: ItemData = sample[name]
		var btn := Button.new()
		btn.text = "%s ×%d" % [name, counts[name]]
		btn.pressed.connect(func(): _select_item(it))
		skill_list.add_child(btn)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(func(): skill_panel.visible = false)
	skill_list.add_child(back)

func _select_item(item: ItemData) -> void:
	pending_item = item
	skill_panel.visible = false
	# La mayoría de items heal/buff van al usuario actual por simplicidad
	action_panel.visible = false
	_clear_highlights()
	_clear_hover()
	manager.submit_item(item, manager.current)

func _on_wait_pressed() -> void:
	action_panel.visible = false
	_clear_hover()
	_clear_highlights()
	manager.submit_wait()

func _on_run_pressed() -> void:
	action_panel.visible = false
	_clear_hover()
	_clear_highlights()
	manager.submit_run()

func _open_skill_picker(kind: int) -> void:
	skill_panel.visible = true
	skill_title.text = "Arts" if kind == SkillData.Kind.ART else "Crafts"
	for child in skill_list.get_children(): child.queue_free()
	var b := manager.current
	var filtered: Array = []
	for s in b.skills:
		if s.kind == kind:
			filtered.append(s)
	if filtered.is_empty():
		var lbl := Label.new()
		lbl.text = "Sin habilidades."
		skill_list.add_child(lbl)
	for s in filtered:
		var btn := Button.new()
		var cost_str := ""
		if kind == SkillData.Kind.ART:
			cost_str = "MP %d  Cast %d" % [s.mp_cost, s.cast_time]
			btn.disabled = b.mp < s.mp_cost
		elif s.is_limit_break:
			cost_str = "S-CRAFT  CP ≥ %d (consume todo)" % s.limit_min_cp
			btn.disabled = b.cp < s.limit_min_cp
			btn.add_theme_color_override("font_color", Color(1, 0.5, 0.9))
		else:
			cost_str = "CP %d" % s.cp_cost
			btn.disabled = b.cp < s.cp_cost
		btn.text = "%s  (%s)" % [s.skill_name, cost_str]
		btn.pressed.connect(func(): _select_skill(s))
		skill_list.add_child(btn)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(func(): skill_panel.visible = false)
	skill_list.add_child(back)

func _select_skill(s: SkillData) -> void:
	pending_skill = s
	pending_kind = s.kind
	skill_panel.visible = false
	phase = Phase.PICK_TARGET_SKILL
	prompt_label.text = "Click sobre celda objetivo (rango %d, AoE %d)" % [s.skill_range, s.aoe_radius]
	_show_skill_range(manager.current, s)

# ---------- Highlights ----------

func _clear_highlights() -> void:
	for child in highlight_node.get_children():
		child.queue_free()

func _add_highlight(cell: Vector2i, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(TILE_SIZE - 4, TILE_SIZE - 4)
	rect.position = GRID_OFFSET + Vector2(cell.x * TILE_SIZE + 2, cell.y * TILE_SIZE + 2)
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight_node.add_child(rect)
	return rect

func _show_move_range(b: Battler) -> void:
	_clear_highlights()
	var cells := manager.grid.bfs_reachable(b.grid_pos, b.move_range)
	for c in cells:
		_add_highlight(c, Color(0.3, 0.8, 1.0, 0.25))

func _show_attack_targets(b: Battler) -> void:
	_clear_highlights()
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var cell := b.grid_pos + Vector2i(dx, dy)
			if not manager.grid.in_bounds(cell): continue
			var t = manager.grid.get_at(cell)
			if t and not t.is_player and t.is_alive():
				_add_highlight(cell, Color(1.0, 0.3, 0.3, 0.4))

func _show_skill_range(b: Battler, s: SkillData) -> void:
	_clear_highlights()
	for dy in range(-s.skill_range, s.skill_range + 1):
		for dx in range(-s.skill_range, s.skill_range + 1):
			var cell := b.grid_pos + Vector2i(dx, dy)
			if not manager.grid.in_bounds(cell): continue
			if manager.grid.chebyshev(b.grid_pos, cell) > s.skill_range: continue
			_add_highlight(cell, Color(1.0, 0.6, 0.2, 0.20))

func _preview_aoe(cell: Vector2i, s: SkillData) -> void:
	var aoe := manager.grid.cells_in_aoe(cell, s.aoe_shape, s.aoe_radius)
	for c in aoe:
		_add_highlight(c, Color(1.0, 0.3, 0.3, 0.45))

# ---------- Hover ----------

func _clear_hover() -> void:
	_hover_cell = Vector2i(-999, -999)
	if _hover_tween:
		_hover_tween.kill()
		_hover_tween = null
	if _hover_rect:
		_hover_rect.queue_free()
		_hover_rect = null

func _set_active_marker(b: Battler) -> void:
	if b == null:
		return
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	if _active_marker == null:
		_active_marker = ColorRect.new()
		_active_marker.size = Vector2(TILE_SIZE, TILE_SIZE)
		_active_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hover_node.add_child(_active_marker)
		hover_node.move_child(_active_marker, 0)
	_active_marker.position = GRID_OFFSET + Vector2(b.grid_pos.x * TILE_SIZE, b.grid_pos.y * TILE_SIZE)
	var base := Color(0.4, 0.95, 0.4, 0.25) if b.is_player else Color(0.95, 0.4, 0.4, 0.25)
	_active_marker.color = base
	var bright := Color(base.r, base.g, base.b, 0.6)
	_active_tween = create_tween().set_loops()
	_active_tween.tween_property(_active_marker, "color", bright, 0.5).set_trans(Tween.TRANS_SINE)
	_active_tween.tween_property(_active_marker, "color", base, 0.5).set_trans(Tween.TRANS_SINE)

func _move_active_marker() -> void:
	if _active_marker == null or manager.current == null: return
	var target := GRID_OFFSET + Vector2(manager.current.grid_pos.x * TILE_SIZE, manager.current.grid_pos.y * TILE_SIZE)
	var tw := create_tween()
	tw.tween_property(_active_marker, "position", target, 0.18)

func _set_hover_cell(cell: Vector2i) -> void:
	if cell == _hover_cell:
		return
	_hover_cell = cell
	if _hover_rect == null:
		_hover_rect = ColorRect.new()
		_hover_rect.size = Vector2(TILE_SIZE - 2, TILE_SIZE - 2)
		_hover_rect.color = Color(1.0, 1.0, 0.3, 0.5)
		_hover_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hover_node.add_child(_hover_rect)
	_hover_rect.position = GRID_OFFSET + Vector2(cell.x * TILE_SIZE + 1, cell.y * TILE_SIZE + 1)
	# Tint del hover según fase
	var base := Color(1.0, 1.0, 0.3, 0.5)
	match phase:
		Phase.CHOOSE_MOVE:
			base = Color(0.4, 0.9, 1.0, 0.55) if (cell in manager.grid.bfs_reachable(manager.current.grid_pos, manager.current.move_range)) else Color(1, 0.3, 0.3, 0.35)
		Phase.PICK_TARGET_ATTACK:
			var t = manager.grid.get_at(cell)
			base = Color(1.0, 0.4, 0.4, 0.6) if (t and not t.is_player and t.is_alive() and manager.grid.chebyshev(manager.current.grid_pos, cell) <= manager.current.melee_range) else Color(0.6, 0.6, 0.6, 0.25)
		Phase.PICK_TARGET_SKILL:
			if pending_skill and manager.grid.chebyshev(manager.current.grid_pos, cell) <= pending_skill.skill_range:
				base = Color(1.0, 0.6, 0.2, 0.55)
			else:
				base = Color(0.6, 0.6, 0.6, 0.25)
	_hover_rect.color = base
	# Pulse animation
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_loops()
	var bright := Color(base.r, base.g, base.b, clamp(base.a + 0.25, 0.0, 1.0))
	var dim := Color(base.r, base.g, base.b, clamp(base.a - 0.25, 0.0, 1.0))
	_hover_tween.tween_property(_hover_rect, "color", bright, 0.35).set_trans(Tween.TRANS_SINE)
	_hover_tween.tween_property(_hover_rect, "color", dim, 0.35).set_trans(Tween.TRANS_SINE)

# ---------- Input ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if phase == Phase.CHOOSE_MOVE or phase == Phase.PICK_TARGET_ATTACK or phase == Phase.PICK_TARGET_SKILL:
				_clear_highlights()
				_clear_hover()
				phase = Phase.CHOOSE_ACTION
				prompt_label.text = "Elige acción"
				return
	if event is InputEventMouseMotion:
		var cell := _pos_to_cell(get_local_mouse_position())
		if manager.grid != null and manager.grid.in_bounds(cell):
			_set_hover_cell(cell)
			if phase == Phase.PICK_TARGET_SKILL and pending_skill != null:
				_show_skill_range(manager.current, pending_skill)
				_preview_aoe(cell, pending_skill)
		else:
			_clear_hover()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _pos_to_cell(get_local_mouse_position())
		if not manager.grid.in_bounds(cell): return
		match phase:
			Phase.CHOOSE_MOVE:
				if manager.submit_move(cell):
					has_moved = true
					btn_move.disabled = true
					phase = Phase.CHOOSE_ACTION
					prompt_label.text = "Te moviste. Ahora elige acción (Atacar / Arts / Crafts / Defender / Esperar)"
					_clear_highlights()
					_clear_hover()
			Phase.PICK_TARGET_ATTACK:
				var t: Battler = manager.grid.get_at(cell)
				if t == null or t.is_player or not t.is_alive():
					prompt_label.text = "Click sobre un enemigo (resaltado en rojo). Esc cancela."
					return
				if manager.grid.chebyshev(manager.current.grid_pos, cell) > manager.current.melee_range:
					prompt_label.text = "Fuera de alcance. Mueve más cerca o elige otra acción."
					phase = Phase.CHOOSE_ACTION
					action_panel.visible = true
					_clear_highlights()
					_clear_hover()
					return
				manager.submit_attack(cell)
				phase = Phase.IDLE
				action_panel.visible = false
				_clear_highlights()
				_clear_hover()
			Phase.PICK_TARGET_SKILL:
				if pending_skill == null: return
				if manager.grid.chebyshev(manager.current.grid_pos, cell) > pending_skill.skill_range:
					prompt_label.text = "Fuera de rango (%d tiles). Click más cerca o Esc." % pending_skill.skill_range
					return
				if pending_kind == SkillData.Kind.ART:
					manager.submit_art(pending_skill, cell)
				else:
					manager.submit_craft(pending_skill, cell)
				pending_skill = null
				pending_kind = -1
				phase = Phase.IDLE
				action_panel.visible = false
				_clear_highlights()
				_clear_hover()
