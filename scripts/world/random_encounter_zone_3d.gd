@tool
extends Area3D

@export var encounter_table: EncounterTableData
@export var zone_size: Vector3 = Vector3(8, 2, 8):
	set(v):
		zone_size = v
		if is_inside_tree():
			_refresh_shape()

var _player_in_zone: bool = false
var _player_ref: Node3D = null
var _last_pos: Vector3
var _distance_since_check: float = 0.0
var _grace_left: float = 0.0
var _rng: RandomNumberGenerator

func _ready() -> void:
	_refresh_shape()
	if Engine.is_editor_hint(): return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_grace_left = encounter_table.initial_grace_seconds if encounter_table else 0.0
	BattleLoader.battle_finished.connect(_on_battle_finished)

func _refresh_shape() -> void:
	var coll := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if coll and coll.shape is BoxShape3D:
		(coll.shape as BoxShape3D).size = zone_size

func _on_body_entered(b: Node3D) -> void:
	if b.is_in_group("player"):
		_player_in_zone = true
		_player_ref = b
		_last_pos = b.global_position
		_distance_since_check = 0.0

func _on_body_exited(b: Node3D) -> void:
	if b == _player_ref:
		_player_in_zone = false
		_player_ref = null

func _on_battle_finished(_v: bool) -> void:
	if encounter_table:
		_grace_left = encounter_table.post_battle_grace_seconds
	_distance_since_check = 0.0
	if _player_ref: _last_pos = _player_ref.global_position

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if encounter_table == null or not _player_in_zone or _player_ref == null: return
	if DialogueManager.is_active() or CutsceneRunner.is_active(): return
	if MapManager.traveling: return
	if _grace_left > 0.0:
		_grace_left -= delta
		_last_pos = _player_ref.global_position
		return
	# Pixels_per_check se reinterpreta como "metros por chequeo / 10" para 3D (1m ~= 10px equivalent)
	var step: float = _player_ref.global_position.distance_to(_last_pos)
	_last_pos = _player_ref.global_position
	if step <= 0.01:
		return
	_distance_since_check += step * 10.0  # escala a "pixels" equivalentes
	if _distance_since_check >= float(encounter_table.pixels_per_check):
		_distance_since_check = 0.0
		if _rng.randf() < encounter_table.encounter_chance:
			_trigger_encounter()

func _trigger_encounter() -> void:
	var entry := _pick_weighted_entry()
	if entry == null or entry.encounter == null: return
	var list: Array[EnemyData] = entry.encounter.enemies.duplicate()
	if list.is_empty(): return
	BattleLoader.call_deferred("start_battle", list, get_tree().current_scene.scene_file_path)

func _pick_weighted_entry() -> EncounterTableEntry:
	var valid: Array[EncounterTableEntry] = []
	var total: int = 0
	for e in encounter_table.entries:
		if e == null or e.encounter == null: continue
		if e.min_chapter > 0 and not Story.chapter_at_least(e.min_chapter): continue
		if e.requires_flag != "" and not Story.has_flag(e.requires_flag): continue
		if e.blocked_by_flag != "" and Story.has_flag(e.blocked_by_flag): continue
		valid.append(e)
		total += e.weight
	if valid.is_empty() or total <= 0: return null
	var roll: int = _rng.randi_range(1, total)
	var acc: int = 0
	for e in valid:
		acc += e.weight
		if roll <= acc: return e
	return valid[0]
