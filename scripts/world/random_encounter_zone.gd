@tool
extends Area2D

@export var encounter_table: EncounterTableData:
	set(v):
		encounter_table = v
		if is_inside_tree():
			_refresh()
@export var zone_size: Vector2 = Vector2(420, 300):
	set(v):
		zone_size = v
		if is_inside_tree():
			_refresh()
@export var debug_visible_in_game: bool = false
@export var debug_color: Color = Color(0.3, 0.9, 0.4, 0.10)

var _player_in_zone: bool = false
var _player_ref: Node2D = null
var _last_player_pos: Vector2 = Vector2.ZERO
var _distance_since_check: float = 0.0
var _grace_left: float = 0.0
var _rng: RandomNumberGenerator

func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_grace_left = encounter_table.initial_grace_seconds if encounter_table else 0.0
	BattleLoader.battle_finished.connect(_on_battle_finished)
	$DebugRect.visible = debug_visible_in_game

func _refresh() -> void:
	var coll := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if coll and coll.shape is RectangleShape2D:
		(coll.shape as RectangleShape2D).size = zone_size
	var rect := get_node_or_null("DebugRect") as ColorRect
	if rect:
		rect.size = zone_size
		rect.position = -zone_size * 0.5
		rect.color = debug_color
		if Engine.is_editor_hint():
			rect.visible = true
		else:
			rect.visible = debug_visible_in_game

func _on_body_entered(b: Node2D) -> void:
	if b.is_in_group("player"):
		_player_in_zone = true
		_player_ref = b
		_last_player_pos = b.global_position
		_distance_since_check = 0.0

func _on_body_exited(b: Node2D) -> void:
	if b == _player_ref:
		_player_in_zone = false
		_player_ref = null

func _on_battle_finished(_victory: bool) -> void:
	if encounter_table:
		_grace_left = encounter_table.post_battle_grace_seconds
	_distance_since_check = 0.0
	if _player_ref:
		_last_player_pos = _player_ref.global_position

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if encounter_table == null: return
	if not _player_in_zone or _player_ref == null: return
	if DialogueManager.is_active(): return
	if CutsceneRunner.is_active(): return
	if MapManager.traveling: return

	if _grace_left > 0.0:
		_grace_left -= delta
		_last_player_pos = _player_ref.global_position
		return

	var step := _player_ref.global_position.distance_to(_last_player_pos)
	_last_player_pos = _player_ref.global_position
	if step <= 0.5:
		return  # ignora micro-movimientos / paradas
	_distance_since_check += step
	if _distance_since_check >= float(encounter_table.pixels_per_check):
		_distance_since_check = 0.0
		if _rng.randf() < encounter_table.encounter_chance:
			_trigger_encounter()

func _trigger_encounter() -> void:
	var entry := _pick_weighted_entry()
	if entry == null or entry.encounter == null: return
	var enemies: Array[EnemyData] = entry.encounter.enemies.duplicate()
	if enemies.is_empty(): return
	BattleLoader.call_deferred("start_battle", enemies, get_tree().current_scene.scene_file_path)

func _pick_weighted_entry() -> EncounterTableEntry:
	var valid: Array[EncounterTableEntry] = []
	var total_weight: int = 0
	for e in encounter_table.entries:
		if e == null or e.encounter == null: continue
		if e.min_chapter > 0 and not Story.chapter_at_least(e.min_chapter): continue
		if e.requires_flag != "" and not Story.has_flag(e.requires_flag): continue
		if e.blocked_by_flag != "" and Story.has_flag(e.blocked_by_flag): continue
		valid.append(e)
		total_weight += e.weight
	if valid.is_empty() or total_weight <= 0:
		return null
	var roll: int = _rng.randi_range(1, total_weight)
	var acc: int = 0
	for e in valid:
		acc += e.weight
		if roll <= acc:
			return e
	return valid[0]
