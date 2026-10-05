extends Node3D

## Vista del combate, al estilo del remake de Trails in the Sky.
##
## No hay casillas: el campo es continuo (BattleField) y el alcance de
## movimiento es un círculo alrededor de quien tiene el turno. Las reglas
## siguen fuera de aquí; esto solo dibuja el campo, los círculos y el ratón.

## Velocidad a la que camina un combatiente al reposicionarse, en m/s.
const WALK_SPEED := 2.6
const GROUND_Y := 0.0
## Altura de los círculos sobre el suelo, para que no parpadeen contra él.
const MARK_Y := 0.015

enum Phase { IDLE, CHOOSE_MOVE, CHOOSE_ACTION, PICK_TARGET_ATTACK, PICK_TARGET_SKILL, PICK_SKILL }

@onready var manager: BattleManager = $BattleManager
@onready var arena: Node3D = $Arena
@onready var battlers_node: Node3D = $Battlers
@onready var marks_node: Node3D = $Marks
@onready var fx_node: Node3D = $FX
@onready var cam_target: Node3D = $CamTarget
@onready var cam_rig: ThirdPersonCamera = $CamTarget/CamRig
@onready var camera: Camera3D = $CamTarget/CamRig/SpringArm3D/Camera3D

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

var _anims: Dictionary = {}
var _range_mark: MeshInstance3D = null
var _ghost: MeshInstance3D = null
var _aoe_mark: MeshInstance3D = null
var _active_mark: MeshInstance3D = null
var _active_tween: Tween = null
var _walking: int = 0
var _focus: Vector3 = Vector3.ZERO

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
	manager.field_changed.connect(_refresh_positions)
	manager.preview_changed.connect(_refresh_atb)

	var party := GameState.party
	var enemies := GameState.pending_battle_enemies
	if enemies.is_empty():
		enemies = [_default_enemy()]
	manager.setup(party, enemies)
	_build_arena()
	_build_status_panel()
	_spawn_battler_views()
	_refresh_positions(true)
	_refresh_stats()
	_refresh_atb()
	manager.start()

## La cámara sigue a quien tiene el turno. Se lee la posición de su NODO, no
## la del campo, para que también acompañe durante la caminata.
func _process(delta: float) -> void:
	if manager.current != null and battler_views.has(manager.current):
		var v: Node3D = battler_views[manager.current]
		_focus = v.position + Vector3(0, 0.95, 0)
	cam_target.position = cam_target.position.lerp(_focus, 1.0 - exp(-5.0 * delta))

func _default_enemy() -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = "Slime"
	return e

# ---------- Campo <-> mundo ----------

func _field_to_world(p: Vector2) -> Vector3:
	return Vector3(p.x, GROUND_Y, p.y)

func _world_to_field(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

## Punto del campo bajo el ratón. Se corta el rayo de la cámara contra el
## plano del suelo: para una arena plana no hace falta física.
func _mouse_point() -> Vector2:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return Vector2(99999, 99999)
	var t := (GROUND_Y - from.y) / dir.y
	if t < 0.0:
		return Vector2(99999, 99999)
	return _world_to_field(from + dir * t)

func _valid(p: Vector2) -> bool:
	return absf(p.x) < 9000.0

# ---------- Arena ----------

func _flat_material(color: Color, unshaded: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _disc(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.01
	c.radial_segments = 48
	c.rings = 0
	mi.mesh = c
	mi.material_override = _flat_material(color)
	return mi

func _ring(radius: float, grosor: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = maxf(0.01, radius - grosor)
	t.outer_radius = radius
	t.rings = 56
	t.ring_segments = 6
	mi.mesh = t
	mi.material_override = _flat_material(color)
	return mi

func _build_arena() -> void:
	for child in arena.get_children():
		child.queue_free()
	# Suelo: un disco achatado en Z para que la arena sea una elipse, más
	# ancha que profunda, con los dos bandos enfrentados por el eje largo.
	var suelo := _disc(1.0, Color(0.27, 0.29, 0.40))
	suelo.material_override = _flat_material(Color(0.27, 0.29, 0.40), false)
	suelo.scale = Vector3(BattleField.RADIUS_X, 1.0, BattleField.RADIUS_Z)
	suelo.position.y = -0.01
	arena.add_child(suelo)

	var borde := _ring(1.0, 0.045, Color(0.55, 0.62, 0.85, 0.75))
	borde.scale = Vector3(BattleField.RADIUS_X, 1.0, BattleField.RADIUS_Z)
	borde.position.y = MARK_Y
	arena.add_child(borde)

	# Línea de separación entre bandos: ayuda a leer el campo de un vistazo.
	var media := _disc(1.0, Color(0.42, 0.46, 0.62, 0.5))
	media.scale = Vector3(0.035, 1.0, BattleField.RADIUS_Z * 0.92)
	media.position.y = MARK_Y * 0.5
	arena.add_child(media)

# ---------- Unidades ----------

func _spawn_battler_views() -> void:
	for child in battlers_node.get_children():
		child.queue_free()
	battler_views.clear()
	_anims.clear()
	for b in manager.allies + manager.enemies:
		var view := _make_unit(b)
		battlers_node.add_child(view)
		battler_views[b] = view
		b.damage_taken.connect(_on_battler_damaged.bind(b))
		b.healed.connect(_on_battler_healed.bind(b))
		b.break_triggered.connect(_on_battler_broken.bind(b))

func _facing_yaw(b: Battler) -> float:
	# Los bandos se miran: aliados hacia +X, enemigos hacia -X. El "adelante"
	# de un Node3D es -Z, de ahí el atan2 con los dos signos cambiados.
	var f := Vector3(1, 0, 0) if b.is_player else Vector3(-1, 0, 0)
	return atan2(-f.x, -f.z)

func _make_unit(b: Battler) -> Node3D:
	var root := Node3D.new()
	root.name = "Unit_" + b.display_name

	var model_holder := Node3D.new()
	model_holder.name = "Model"
	model_holder.rotation.y = _facing_yaw(b)
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
			_anims[b] = anim
	else:
		# Sin modelo, una cápsula de su color. Es feo, pero un hueco invisible
		# en el campo sería peor.
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 1.1
		mi.mesh = cap
		mi.position.y = 0.55
		mi.material_override = _flat_material(b.color, false)
		model_holder.add_child(mi)
		push_warning("battle_3d: %s no tiene modelo 3D." % b.display_name)

	# Sombra de apoyo: sin ella los personajes parecen flotar sobre la arena.
	var pie := _disc(BattleField.BODY * 0.95, Color(0, 0, 0, 0.28))
	pie.name = "Pie"
	pie.position.y = MARK_Y * 0.3
	root.add_child(pie)

	root.add_child(_label3d("HP", Vector3(0, 1.62, 0), 0.10, Color(1, 1, 1)))
	root.add_child(_label3d("Cast", Vector3(0, 1.84, 0), 0.085, Color(0.9, 0.6, 1)))
	root.add_child(_label3d("BreakLabel", Vector3(0, 2.02, 0), 0.10, Color(0.4, 0.85, 1)))

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
	l.pixel_size = size * 0.045
	l.font_size = 48
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
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

func _play_anim(b: Battler, nombre: String) -> void:
	var ap: AnimationPlayer = _anims.get(b)
	if ap == null or not ap.has_animation(nombre):
		return
	if ap.current_animation != nombre:
		ap.play(nombre)

## True mientras alguien esté caminando: sirve para no dejar actuar a medias.
func is_walking() -> bool:
	return _walking > 0

func _refresh_positions(instant: bool = false) -> void:
	for b in battler_views.keys():
		var view: Node3D = battler_views[b]
		var target := _field_to_world(b.field_pos)
		if instant or view.position.distance_to(target) < 0.03:
			view.position = target
		else:
			_walk(view, b, target)
		var cast_lbl := view.get_node_or_null("Cast") as Label3D
		if cast_lbl:
			cast_lbl.text = ("▷ %s" % b.pending_skill.skill_name) if (b.is_casting and b.pending_skill) else ""
	_move_active_mark()

## Camina hasta el destino en vez de teletransportarse: gira el modelo hacia
## donde va, pone la animación de paso y al llegar vuelve a mirar al enemigo.
func _walk(view: Node3D, b: Battler, target: Vector3) -> void:
	var model := view.get_node_or_null("Model") as Node3D
	var dir := target - view.position
	dir.y = 0.0
	var dist := dir.length()
	if dist < 0.03:
		return
	var dur: float = clampf(dist / WALK_SPEED, 0.18, 3.0)
	_walking += 1
	_play_anim(b, "walk")
	var tw := create_tween()
	if model:
		tw.parallel().tween_property(model, "rotation:y", atan2(-dir.x, -dir.z), 0.16)
	tw.parallel().tween_property(view, "position", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func():
		_walking = maxi(0, _walking - 1)
		_play_anim(b, "idle"))
	if model:
		tw.parallel().tween_property(model, "rotation:y", _facing_yaw(b), 0.22)

# ---------- Círculos ----------

func _clear_marks() -> void:
	if _range_mark:
		_range_mark.queue_free()
		_range_mark = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _aoe_mark:
		_aoe_mark.queue_free()
		_aoe_mark = null

## Área alcanzable, recortada contra el borde de la arena. Un círculo a secas
## se sale del campo y enseña sitios a los que no se puede ir.
func _reach_mesh(center: Vector2, radius: float, grosor: float) -> ArrayMesh:
	var pasos := 72
	var relleno := PackedVector3Array()
	var banda := PackedVector3Array()
	var radios := PackedFloat32Array()
	for i in pasos + 1:
		var ang := TAU * float(i) / float(pasos)
		var d := Vector2(cos(ang), sin(ang))
		radios.append(manager.field.reach_in_direction(center, d, radius))
	for i in pasos:
		var a0 := TAU * float(i) / float(pasos)
		var a1 := TAU * float(i + 1) / float(pasos)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var r0: float = radios[i]
		var r1: float = radios[i + 1]
		var p0 := Vector3(d0.x * r0, 0.0, d0.y * r0)
		var p1 := Vector3(d1.x * r1, 0.0, d1.y * r1)
		# Abanico del relleno, con el centro como vértice común.
		relleno.append(Vector3.ZERO)
		relleno.append(p1)
		relleno.append(p0)
		# Banda del borde, hacia dentro.
		var q0 := Vector3(d0.x * maxf(r0 - grosor, 0.0), 0.0, d0.y * maxf(r0 - grosor, 0.0))
		var q1 := Vector3(d1.x * maxf(r1 - grosor, 0.0), 0.0, d1.y * maxf(r1 - grosor, 0.0))
		banda.append(p0); banda.append(p1); banda.append(q1)
		banda.append(p0); banda.append(q1); banda.append(q0)

	var mesh := ArrayMesh.new()
	var a1_arr := []
	a1_arr.resize(Mesh.ARRAY_MAX)
	a1_arr[Mesh.ARRAY_VERTEX] = relleno
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a1_arr)
	var a2_arr := []
	a2_arr.resize(Mesh.ARRAY_MAX)
	a2_arr[Mesh.ARRAY_VERTEX] = banda
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2_arr)
	return mesh

func _show_range(center: Vector2, radius: float, color: Color) -> void:
	if _range_mark:
		_range_mark.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = _reach_mesh(center, radius, 0.09)
	mi.set_surface_override_material(0, _flat_material(Color(color.r, color.g, color.b, 0.12)))
	mi.set_surface_override_material(1, _flat_material(color))
	mi.position = _field_to_world(center) + Vector3(0, MARK_Y, 0)
	_range_mark = mi
	marks_node.add_child(_range_mark)

func _show_ghost(p: Vector2, color: Color) -> void:
	if _ghost == null:
		_ghost = _disc(BattleField.BODY, color)
		marks_node.add_child(_ghost)
	_ghost.material_override = _flat_material(color)
	_ghost.position = _field_to_world(p) + Vector3(0, MARK_Y * 2.0, 0)

func _show_aoe(p: Vector2, radius: float, color: Color) -> void:
	if _aoe_mark:
		_aoe_mark.queue_free()
	_aoe_mark = _ring(maxf(radius, BattleField.BODY), 0.05, color)
	_aoe_mark.position = _field_to_world(p) + Vector3(0, MARK_Y * 2.5, 0)
	var relleno := _disc(maxf(radius, BattleField.BODY), Color(color.r, color.g, color.b, 0.18))
	relleno.position.y = -MARK_Y * 0.4
	_aoe_mark.add_child(relleno)
	marks_node.add_child(_aoe_mark)

func _set_active_mark(b: Battler) -> void:
	if b == null:
		return
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	if _active_mark:
		_active_mark.queue_free()
	var color := Color(0.4, 0.95, 0.5) if b.is_player else Color(0.95, 0.4, 0.4)
	_active_mark = _ring(BattleField.BODY * 1.45, 0.07, color)
	_active_mark.position = _field_to_world(b.field_pos) + Vector3(0, MARK_Y * 0.6, 0)
	marks_node.add_child(_active_mark)
	var mat := _active_mark.material_override as StandardMaterial3D
	_active_tween = create_tween().set_loops()
	_active_tween.tween_property(mat, "albedo_color", Color(color.r, color.g, color.b, 0.35), 0.55).set_trans(Tween.TRANS_SINE)
	_active_tween.tween_property(mat, "albedo_color", color, 0.55).set_trans(Tween.TRANS_SINE)

func _move_active_mark() -> void:
	if _active_mark == null or manager.current == null:
		return
	var target := _field_to_world(manager.current.field_pos) + Vector3(0, MARK_Y * 0.6, 0)
	var tw := create_tween()
	tw.tween_property(_active_mark, "position", target, 0.25)

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
		var pie := view.get_node_or_null("Pie") as MeshInstance3D
		if pie:
			pie.visible = b.is_alive()

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
	_clear_marks()
	_set_active_mark(b)
	_refresh_atb()

func _on_need_action(b: Battler) -> void:
	if auto_battle:
		action_panel.visible = false
		skill_panel.visible = false
		_clear_marks()
		prompt_label.text = "AUTO: %s actúa solo" % b.display_name
		await get_tree().create_timer(0.25).timeout
		manager.auto_play_player(b)
		return
	action_panel.visible = true
	skill_panel.visible = false
	has_moved = false
	phase = Phase.CHOOSE_ACTION
	prompt_label.text = "Mover (opcional) → elige acción. Botón derecho gira la cámara."
	btn_move.disabled = false
	_clear_marks()

func _on_auto_toggled(on: bool) -> void:
	auto_battle = on
	if on and manager.current and manager.current.is_player and action_panel.visible:
		action_panel.visible = false
		_clear_marks()
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
	_clear_marks()
	_on_log("[b]" + ("VICTORIA" if victory else "DERROTA") + "[/b]")
	await get_tree().create_timer(1.5).timeout
	BattleLoader.end_battle(victory)

func _on_log(text: String) -> void:
	log_label.append_text(text + "\n")

# ---------- Efectos ----------

func _on_battler_damaged(amount: int, was_crit: bool, was_weak: bool, b: Battler) -> void:
	var color := Color(1, 1, 1)
	var size := 0.11
	if was_crit:
		color = Color(1, 0.5, 0.4)
		size = 0.15
	if was_weak:
		color = Color(1, 0.7, 0.3)
		size = 0.13
	_floating("-%d" % amount, b, color, size)
	if was_crit or was_weak:
		_shake(0.14, 0.18)

func _on_battler_healed(amount: int, b: Battler) -> void:
	_floating("+%d" % amount, b, Color(0.4, 1, 0.4), 0.11)

func _on_battler_broken(b: Battler) -> void:
	_floating("BREAK!", b, Color(0.4, 0.85, 1), 0.15)
	_shake(0.22, 0.3)

func _floating(text: String, b: Battler, color: Color, size: float) -> void:
	var start := _field_to_world(b.field_pos) + Vector3(0, 1.3, 0)
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

## Sacude la cámara dentro del brazo. No se mueve el rig: ese persigue al
## personaje activo y el tirón se pelearía con el seguimiento.
func _shake(amount: float, duration: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var steps := 6
	var step := duration / float(steps)
	var tw := create_tween()
	for i in steps:
		tw.tween_property(camera, "position", Vector3(
			rng.randf_range(-amount, amount), rng.randf_range(-amount, amount), 0.0), step)
	tw.tween_property(camera, "position", Vector3.ZERO, step)

# ---------- Entrada ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if phase in [Phase.CHOOSE_MOVE, Phase.PICK_TARGET_ATTACK, Phase.PICK_TARGET_SKILL]:
			_clear_marks()
			if manager.current:
				_set_active_mark(manager.current)
			phase = Phase.CHOOSE_ACTION
			action_panel.visible = true
			prompt_label.text = "Elige acción"
			return
	if manager.current == null:
		return

	if event is InputEventMouseMotion:
		var p := _mouse_point()
		if not _valid(p):
			return
		match phase:
			Phase.CHOOSE_MOVE:
				# Se enseña el punto RECORTADO, no el del ratón: así se ve de
				# antemano dónde se va a acabar si el click se pasa del círculo.
				var destino := manager.field.clamp_reachable(manager.current, p, float(manager.current.move_range))
				_show_ghost(destino, Color(0.35, 0.85, 1.0, 0.55))
			Phase.PICK_TARGET_ATTACK:
				var t = manager.field.get_at(p)
				var ok: bool = t != null and not t.is_player and t.is_alive() and BattleField.distance(manager.current.field_pos, t.field_pos) <= float(manager.current.melee_range) + BattleField.BODY * 2.0
				_show_ghost(t.field_pos if t else p, Color(1.0, 0.35, 0.35, 0.6) if ok else Color(0.6, 0.6, 0.6, 0.3))
			Phase.PICK_TARGET_SKILL:
				if pending_skill:
					var centro := p
					var alcance := float(pending_skill.skill_range)
					if BattleField.distance(manager.current.field_pos, centro) > alcance:
						centro = manager.current.field_pos + (centro - manager.current.field_pos).normalized() * alcance
					_show_aoe(centro, float(pending_skill.aoe_radius), Color(1.0, 0.6, 0.2, 0.75))
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _mouse_point()
		if not _valid(p):
			return
		match phase:
			Phase.CHOOSE_MOVE:
				if manager.submit_move(p):
					has_moved = true
					btn_move.disabled = true
					phase = Phase.CHOOSE_ACTION
					prompt_label.text = "Te moviste. Ahora elige acción (Atacar / Arts / Crafts / Defender / Esperar)"
					_clear_marks()
					_set_active_mark(manager.current)
			Phase.PICK_TARGET_ATTACK:
				var t = manager.field.get_at(p)
				if t == null or t.is_player or not t.is_alive():
					prompt_label.text = "Click encima de un enemigo. Esc cancela."
					return
				if BattleField.distance(manager.current.field_pos, t.field_pos) > float(manager.current.melee_range) + BattleField.BODY * 2.0:
					prompt_label.text = "Fuera de alcance. Muévete más cerca o elige otra acción."
					return
				manager.submit_attack(t.field_pos)
				phase = Phase.IDLE
				action_panel.visible = false
				_clear_marks()
			Phase.PICK_TARGET_SKILL:
				if pending_skill == null:
					return
				var centro := p
				var alcance := float(pending_skill.skill_range)
				if BattleField.distance(manager.current.field_pos, centro) > alcance:
					centro = manager.current.field_pos + (centro - manager.current.field_pos).normalized() * alcance
				if pending_kind == SkillData.Kind.ART:
					manager.submit_art(pending_skill, centro)
				else:
					manager.submit_craft(pending_skill, centro)
				pending_skill = null
				pending_kind = -1
				phase = Phase.IDLE
				action_panel.visible = false
				_clear_marks()

# ---------- Botones ----------

func _on_move_pressed() -> void:
	if has_moved or manager.current == null: return
	phase = Phase.CHOOSE_MOVE
	prompt_label.text = "Click dentro del círculo para colocarte (Esc cancela)"
	_show_range(manager.current.field_pos, float(manager.current.move_range), Color(0.35, 0.85, 1.0, 0.9))

func _on_attack_pressed() -> void:
	if manager.current == null: return
	var alcance: float = float(manager.current.melee_range) + BattleField.BODY * 2.0
	var has_target := false
	for e in manager.enemies:
		if e.is_alive() and BattleField.distance(manager.current.field_pos, e.field_pos) <= alcance:
			has_target = true
			break
	if not has_target:
		prompt_label.text = "Ningún enemigo a tu alcance. Muévete primero o elige Arts/Crafts."
		return
	phase = Phase.PICK_TARGET_ATTACK
	prompt_label.text = "Click sobre el enemigo que quieras golpear"
	_show_range(manager.current.field_pos, alcance, Color(1.0, 0.4, 0.4, 0.9))

func _on_art_pressed() -> void:
	_open_skill_picker(SkillData.Kind.ART)

func _on_craft_pressed() -> void:
	_open_skill_picker(SkillData.Kind.CRAFT)

func _on_defend_pressed() -> void:
	action_panel.visible = false
	_clear_marks()
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
	_clear_marks()
	manager.submit_item(item, manager.current)

func _on_wait_pressed() -> void:
	action_panel.visible = false
	_clear_marks()
	manager.submit_wait()

func _on_run_pressed() -> void:
	action_panel.visible = false
	_clear_marks()
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
	prompt_label.text = "Click en el campo (alcance %d m, área %d m)" % [s.skill_range, s.aoe_radius]
	_show_range(manager.current.field_pos, float(s.skill_range), Color(1.0, 0.6, 0.2, 0.9))
