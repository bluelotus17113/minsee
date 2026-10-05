extends Node3D

## Vista 3D del combate táctico.
##
## Las reglas NO están aquí: viven en BattleManager, BattleGrid, TurnQueue y
## Battler, y no se han tocado. Este script solo traduce la rejilla a un
## tablero en el mundo, dibuja los resaltes y convierte el ratón en casillas.
## La interfaz sigue siendo la misma de la versión 2D, porque es un CanvasLayer
## y no le afecta que debajo haya 3D.

const TILE := 1.0
const BOARD_Y := 0.0
## Altura a la que flotan los resaltes para no pelearse con el suelo.
const MARK_Y := 0.012

enum Phase { IDLE, CHOOSE_MOVE, CHOOSE_ACTION, PICK_TARGET_ATTACK, PICK_TARGET_SKILL, PICK_SKILL }

@onready var manager: BattleManager = $BattleManager
@onready var board: Node3D = $Board
@onready var battlers_node: Node3D = $Battlers
@onready var highlight_node: Node3D = $Highlights
@onready var fx_node: Node3D = $FX
@onready var cam_rig: Node3D = $CamRig
@onready var camera: Camera3D = $CamRig/Camera3D

@onready var log_label: RichTextLabel = $UI/BottomPanel/VBox/LogPanel/LogLabel
@onready var action_panel: Panel = $UI/BottomPanel/VBox/ActionPanel
@onready var btn_move: Button = $UI/BottomPanel/VBox/ActionPanel/HBox/Move
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
var auto_battle: bool = false

var _hover_cell: Vector2i = Vector2i(-999, -999)
var _hover_mark: MeshInstance3D = null
var _hover_tween: Tween = null
var _active_mark: MeshInstance3D = null
var _active_tween: Tween = null
var _quad: QuadMesh = null
var _cam_home: Vector3 = Vector3.ZERO

func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2(TILE * 0.92, TILE * 0.92)
	# El quad nace de pie: tumbarlo es cosa de la malla, no de cada nodo.
	_quad.orientation = PlaneMesh.FACE_Y
	_cam_home = cam_rig.position

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
	_build_board()
	_build_status_panel()
	_spawn_battler_views()
	_refresh_grid_positions(true)
	_refresh_stats()
	_refresh_atb()
	manager.start()

func _default_enemy() -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = "Slime"
	return e

# ---------- Rejilla <-> mundo ----------

## El tablero se centra en el origen: así la cámara no depende de su tamaño.
func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		(float(cell.x) - (BattleGrid.WIDTH - 1) * 0.5) * TILE,
		BOARD_Y,
		(float(cell.y) - (BattleGrid.HEIGHT - 1) * 0.5) * TILE
	)

func _world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(round(pos.x / TILE + (BattleGrid.WIDTH - 1) * 0.5)),
		int(round(pos.z / TILE + (BattleGrid.HEIGHT - 1) * 0.5))
	)

## Casilla bajo el ratón. Se corta el rayo de la cámara contra el plano del
## tablero: no hace falta física ni colisionadores para 60 casillas.
func _mouse_cell() -> Vector2i:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return Vector2i(-999, -999)
	var t := (BOARD_Y - from.y) / dir.y
	if t < 0.0:
		return Vector2i(-999, -999)
	return _world_to_cell(from + dir * t)

# ---------- Tablero ----------

func _flat_material(color: Color, unshaded: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _build_board() -> void:
	for child in board.get_children():
		child.queue_free()
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(TILE * 0.96, 0.12, TILE * 0.96)
	var claro := _flat_material(Color(0.30, 0.33, 0.44), false)
	var oscuro := _flat_material(Color(0.22, 0.24, 0.33), false)
	for y in BattleGrid.HEIGHT:
		for x in BattleGrid.WIDTH:
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			mi.material_override = oscuro if (x + y) % 2 == 0 else claro
			mi.position = _cell_to_world(Vector2i(x, y)) - Vector3(0, 0.06, 0)
			board.add_child(mi)

# ---------- Unidades ----------

func _spawn_battler_views() -> void:
	for child in battlers_node.get_children():
		child.queue_free()
	battler_views.clear()
	for b in manager.allies + manager.enemies:
		var view := _make_unit(b)
		battlers_node.add_child(view)
		battler_views[b] = view
		b.damage_taken.connect(_on_battler_damaged.bind(b))
		b.healed.connect(_on_battler_healed.bind(b))
		b.break_triggered.connect(_on_battler_broken.bind(b))

func _make_unit(b: Battler) -> Node3D:
	var root := Node3D.new()
	root.name = "Unit_" + b.display_name

	var model_holder := Node3D.new()
	model_holder.name = "Model"
	# Los bandos se miran: aliados a +X, enemigos a -X. El "adelante" de un
	# Node3D es -Z, de ahí el atan2 con los dos signos cambiados.
	var facing := Vector3(1, 0, 0) if b.is_player else Vector3(-1, 0, 0)
	model_holder.rotation.y = atan2(-facing.x, -facing.z)
	root.add_child(model_holder)

	if b.model != null:
		var inst := b.model.instantiate()
		model_holder.add_child(inst)
		ToonSkin.skin(inst)
		var anim := _find_anim(inst)
		if anim:
			for n in anim.get_animation_list():
				var a := anim.get_animation(n)
				if a:
					a.loop_mode = Animation.LOOP_LINEAR
			if anim.has_animation("idle"):
				anim.play("idle")
	else:
		# Sin modelo, una cápsula del color del battler. Es feo, pero se ve:
		# un hueco invisible en el tablero sería peor.
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 1.1
		mi.mesh = cap
		mi.position.y = 0.55
		mi.material_override = _flat_material(b.color, false)
		model_holder.add_child(mi)
		push_warning("battle_3d: %s no tiene modelo 3D." % b.display_name)

	var hp := _label3d("HP", Vector3(0, 1.62, 0), 0.085, Color(1, 1, 1))
	root.add_child(hp)
	var cast := _label3d("Cast", Vector3(0, 1.84, 0), 0.075, Color(0.9, 0.6, 1))
	root.add_child(cast)
	var brk := _label3d("BreakLabel", Vector3(0, 2.02, 0), 0.085, Color(0.4, 0.85, 1))
	root.add_child(brk)

	# Barra de break: dos quads planos, el relleno anclado por la izquierda.
	var bar_bg := MeshInstance3D.new()
	bar_bg.name = "BreakBG"
	bar_bg.mesh = _bar_mesh()
	bar_bg.material_override = _flat_material(Color(0.1, 0.1, 0.2, 0.75))
	bar_bg.position = Vector3(0, 1.50, 0)
	root.add_child(bar_bg)
	var bar_fill := MeshInstance3D.new()
	bar_fill.name = "BreakFill"
	bar_fill.mesh = _bar_mesh()
	bar_fill.material_override = _flat_material(Color(0.3, 0.7, 1, 1))
	bar_fill.position = Vector3(0, 1.505, 0)
	root.add_child(bar_fill)
	return root

func _bar_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.07)
	return q

func _label3d(nombre: String, pos: Vector3, size: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.name = nombre
	l.position = pos
	# Sin fixed_size: con él la etiqueta mide lo mismo en pantalla llene lo
	# que llene, y a esta distancia tapaba el tablero entero.
	l.pixel_size = size * 0.045
	l.font_size = 48
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.text = ""
	return l

func _find_anim(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var f := _find_anim(c)
		if f:
			return f
	return null

func _refresh_grid_positions(instant: bool = false) -> void:
	for b in battler_views.keys():
		var view: Node3D = battler_views[b]
		var target := _cell_to_world(b.grid_pos)
		if instant:
			view.position = target
		else:
			var tw := create_tween()
			tw.tween_property(view, "position", target, 0.22).set_trans(Tween.TRANS_SINE)
		var cast_lbl := view.get_node_or_null("Cast") as Label3D
		if cast_lbl:
			cast_lbl.text = ("▷ %s" % b.pending_skill.skill_name) if (b.is_casting and b.pending_skill) else ""
	_move_active_mark()

# ---------- Resaltes ----------

func _clear_highlights() -> void:
	for child in highlight_node.get_children():
		child.queue_free()

func _add_highlight(cell: Vector2i, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _flat_material(color)
	mi.position = _cell_to_world(cell) + Vector3(0, MARK_Y, 0)
	highlight_node.add_child(mi)
	return mi

func _show_move_range(b: Battler) -> void:
	_clear_highlights()
	for c in manager.grid.bfs_reachable(b.grid_pos, b.move_range):
		_add_highlight(c, Color(0.3, 0.8, 1.0, 0.35))

func _show_attack_targets(b: Battler) -> void:
	_clear_highlights()
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var cell := b.grid_pos + Vector2i(dx, dy)
			if not manager.grid.in_bounds(cell): continue
			var t = manager.grid.get_at(cell)
			if t and not t.is_player and t.is_alive():
				_add_highlight(cell, Color(1.0, 0.3, 0.3, 0.5))

func _show_skill_range(b: Battler, s: SkillData) -> void:
	_clear_highlights()
	for dy in range(-s.skill_range, s.skill_range + 1):
		for dx in range(-s.skill_range, s.skill_range + 1):
			var cell := b.grid_pos + Vector2i(dx, dy)
			if not manager.grid.in_bounds(cell): continue
			if manager.grid.chebyshev(b.grid_pos, cell) > s.skill_range: continue
			_add_highlight(cell, Color(1.0, 0.6, 0.2, 0.28))

func _preview_aoe(cell: Vector2i, s: SkillData) -> void:
	for c in manager.grid.cells_in_aoe(cell, s.aoe_shape, s.aoe_radius):
		_add_highlight(c, Color(1.0, 0.3, 0.3, 0.5))

# ---------- Cursor y marcador de turno ----------

func _clear_hover() -> void:
	_hover_cell = Vector2i(-999, -999)
	if _hover_tween:
		_hover_tween.kill()
		_hover_tween = null
	if _hover_mark:
		_hover_mark.queue_free()
		_hover_mark = null

func _set_hover_cell(cell: Vector2i) -> void:
	if cell == _hover_cell:
		return
	_hover_cell = cell
	if _hover_mark == null:
		_hover_mark = MeshInstance3D.new()
		_hover_mark.mesh = _quad
		highlight_node.add_child(_hover_mark)
	_hover_mark.position = _cell_to_world(cell) + Vector3(0, MARK_Y * 2.0, 0)
	var base := Color(1.0, 1.0, 0.3, 0.55)
	match phase:
		Phase.CHOOSE_MOVE:
			base = Color(0.4, 0.9, 1.0, 0.6) if (cell in manager.grid.bfs_reachable(manager.current.grid_pos, manager.current.move_range)) else Color(1, 0.3, 0.3, 0.4)
		Phase.PICK_TARGET_ATTACK:
			var t = manager.grid.get_at(cell)
			base = Color(1.0, 0.4, 0.4, 0.65) if (t and not t.is_player and t.is_alive() and manager.grid.chebyshev(manager.current.grid_pos, cell) <= manager.current.melee_range) else Color(0.6, 0.6, 0.6, 0.3)
		Phase.PICK_TARGET_SKILL:
			base = Color(1.0, 0.6, 0.2, 0.6) if (pending_skill and manager.grid.chebyshev(manager.current.grid_pos, cell) <= pending_skill.skill_range) else Color(0.6, 0.6, 0.6, 0.3)
	var mat := _flat_material(base)
	_hover_mark.material_override = mat
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_loops()
	var alto := Color(base.r, base.g, base.b, clampf(base.a + 0.25, 0.0, 1.0))
	var bajo := Color(base.r, base.g, base.b, clampf(base.a - 0.25, 0.0, 1.0))
	_hover_tween.tween_property(mat, "albedo_color", alto, 0.35).set_trans(Tween.TRANS_SINE)
	_hover_tween.tween_property(mat, "albedo_color", bajo, 0.35).set_trans(Tween.TRANS_SINE)

func _set_active_mark(b: Battler) -> void:
	if b == null:
		return
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	if _active_mark == null:
		_active_mark = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(TILE, TILE)
		q.orientation = PlaneMesh.FACE_Y
		_active_mark.mesh = q
		highlight_node.add_child(_active_mark)
	_active_mark.position = _cell_to_world(b.grid_pos) + Vector3(0, MARK_Y * 0.5, 0)
	var base := Color(0.4, 0.95, 0.4, 0.3) if b.is_player else Color(0.95, 0.4, 0.4, 0.3)
	var mat := _flat_material(base)
	_active_mark.material_override = mat
	var brillo := Color(base.r, base.g, base.b, 0.65)
	_active_tween = create_tween().set_loops()
	_active_tween.tween_property(mat, "albedo_color", brillo, 0.5).set_trans(Tween.TRANS_SINE)
	_active_tween.tween_property(mat, "albedo_color", base, 0.5).set_trans(Tween.TRANS_SINE)

func _move_active_mark() -> void:
	if _active_mark == null or manager.current == null:
		return
	var target := _cell_to_world(manager.current.grid_pos) + Vector3(0, MARK_Y * 0.5, 0)
	var tw := create_tween()
	tw.tween_property(_active_mark, "position", target, 0.22)

# ---------- Estado y cola ----------

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
		var view: Node3D = battler_views[b]
		var hp_lbl := view.get_node_or_null("HP") as Label3D
		if hp_lbl:
			hp_lbl.text = "%d/%d" % [b.hp, b.max_hp]
		var fill := view.get_node_or_null("BreakFill") as MeshInstance3D
		if fill:
			var pct: float = clampf(float(b.break_gauge) / maxf(1.0, float(b.break_threshold)), 0.0, 1.0)
			# El quad escala desde su centro: para anclarlo por la izquierda
			# hay que moverlo la mitad de lo que se encoge.
			fill.scale.x = maxf(pct, 0.001)
			fill.position.x = -(1.0 - pct) * 0.31
			(fill.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.55, 0.2) if b.broken else Color(0.3, 0.7, 1.0)
		var brk := view.get_node_or_null("BreakLabel") as Label3D
		if brk:
			brk.text = "BREAK!" if b.broken else ""
		var model := view.get_node_or_null("Model") as Node3D
		if model:
			model.visible = b.is_alive()

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

# ---------- Turnos ----------

func _on_turn_started(b: Battler, _bonus: int) -> void:
	turn_label.text = "Turno: %s" % b.display_name
	_clear_highlights()
	_clear_hover()
	_set_active_mark(b)
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
	if _active_mark:
		_active_mark.queue_free()
		_active_mark = null
	_on_log("[b]" + ("VICTORIA" if victory else "DERROTA") + "[/b]")
	await get_tree().create_timer(1.5).timeout
	BattleLoader.end_battle(victory)

func _on_log(text: String) -> void:
	log_label.append_text(text + "\n")

# ---------- Efectos ----------

func _on_battler_damaged(amount: int, was_crit: bool, was_weak: bool, b: Battler) -> void:
	var color := Color(1, 1, 1)
	var size := 0.10
	if was_crit:
		color = Color(1, 0.5, 0.4)
		size = 0.14
	if was_weak:
		color = Color(1, 0.7, 0.3)
		size = 0.12
	_floating("-%d" % amount, b, color, size)
	if was_crit or was_weak:
		_shake(0.14, 0.18)

func _on_battler_healed(amount: int, b: Battler) -> void:
	_floating("+%d" % amount, b, Color(0.4, 1, 0.4), 0.10)

func _on_battler_broken(b: Battler) -> void:
	_floating("BREAK!", b, Color(0.4, 0.85, 1), 0.14)
	_shake(0.22, 0.3)

func _floating(text: String, b: Battler, color: Color, size: float) -> void:
	var start := _cell_to_world(b.grid_pos) + Vector3(0, 1.3, 0)
	var lbl := _label3d("Float", start, size, color)
	lbl.text = text
	fx_node.add_child(lbl)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var drift := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.15, 0.15))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position", start + Vector3(0, 1.0, 0) + drift, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.chain().tween_callback(lbl.queue_free)

## Sacude la cámara, no la escena: mover la raíz movería también el tablero
## y el rayo del ratón dejaría de caer donde toca.
func _shake(amount: float, duration: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var steps := 6
	var step := duration / float(steps)
	var tw := create_tween()
	for i in steps:
		tw.tween_property(cam_rig, "position", _cam_home + Vector3(
			rng.randf_range(-amount, amount), rng.randf_range(-amount, amount), 0.0), step)
	tw.tween_property(cam_rig, "position", _cam_home, step)

# ---------- Botones ----------

func _on_move_pressed() -> void:
	if has_moved or manager.current == null: return
	phase = Phase.CHOOSE_MOVE
	prompt_label.text = "Click en casilla azul para moverse (Esc cancela)"
	_show_move_range(manager.current)

func _on_attack_pressed() -> void:
	if manager.current == null: return
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
	var counts: Dictionary = {}
	var sample: Dictionary = {}
	for it in inv:
		if it == null: continue
		counts[it.item_name] = counts.get(it.item_name, 0) + 1
		sample[it.item_name] = it
	for nombre in counts.keys():
		var it: ItemData = sample[nombre]
		var btn := Button.new()
		btn.text = "%s ×%d" % [nombre, counts[nombre]]
		btn.pressed.connect(func(): _select_item(it))
		skill_list.add_child(btn)
	var back := Button.new()
	back.text = "Volver"
	back.pressed.connect(func(): skill_panel.visible = false)
	skill_list.add_child(back)

func _select_item(item: ItemData) -> void:
	pending_item = item
	skill_panel.visible = false
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
	prompt_label.text = "Click sobre casilla objetivo (rango %d, AoE %d)" % [s.skill_range, s.aoe_radius]
	_show_skill_range(manager.current, s)

# ---------- Entrada ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if phase in [Phase.CHOOSE_MOVE, Phase.PICK_TARGET_ATTACK, Phase.PICK_TARGET_SKILL]:
				_clear_highlights()
				_clear_hover()
				phase = Phase.CHOOSE_ACTION
				prompt_label.text = "Elige acción"
				return
	if event is InputEventMouseMotion:
		var cell := _mouse_cell()
		if manager.grid != null and manager.grid.in_bounds(cell):
			_set_hover_cell(cell)
			if phase == Phase.PICK_TARGET_SKILL and pending_skill != null:
				_show_skill_range(manager.current, pending_skill)
				_preview_aoe(cell, pending_skill)
		else:
			_clear_hover()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _mouse_cell()
		if manager.grid == null or not manager.grid.in_bounds(cell): return
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
					prompt_label.text = "Fuera de rango (%d casillas). Click más cerca o Esc." % pending_skill.skill_range
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
