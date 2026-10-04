@tool
extends Area3D

@export var encounter: EncounterData
@export var enemies: Array[EnemyData] = []
@export var wander_speed: float = 1.0
@export var wander_radius: float = 1.5

var _origin: Vector3
var _target: Vector3
var _triggered: bool = false

func _ready() -> void:
	_refresh_visual()
	if Engine.is_editor_hint(): return
	_origin = global_position
	_pick_new_target()
	body_entered.connect(_on_body_entered)
	if encounter == null and enemies.is_empty():
		var fallback := load("res://data/enemies/slime.tres") as EnemyData
		if fallback: enemies = [fallback]
		_refresh_visual()

func _first_enemy() -> EnemyData:
	if encounter and encounter.enemies.size() > 0: return encounter.enemies[0]
	if enemies.size() > 0: return enemies[0]
	return null

func _refresh_visual() -> void:
	var sprite := get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null: return
	var d := _first_enemy()
	if d and d.sprite:
		sprite.texture = d.sprite
		sprite.pixel_size = 0.04 if d.sprite_size <= 32 else 0.025
		sprite.modulate = Color.WHITE
	else:
		sprite.modulate = d.color if d else Color(0.8, 0.3, 0.3)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _triggered: return
	var dir := _target - global_position
	dir.y = 0
	if dir.length() < 0.1:
		_pick_new_target()
	else:
		global_position += dir.normalized() * wander_speed * delta

func _pick_new_target() -> void:
	var angle := randf() * TAU
	_target = _origin + Vector3(cos(angle), 0, sin(angle)) * wander_radius

func _on_body_entered(body: Node3D) -> void:
	if _triggered: return
	if body.is_in_group("player"):
		_triggered = true
		var list: Array[EnemyData] = []
		if encounter and encounter.enemies.size() > 0:
			list = encounter.enemies.duplicate()
		else:
			list = enemies.duplicate()
		if list.is_empty():
			var fb := EnemyData.new()
			fb.enemy_name = "Slime"
			list = [fb]
		BattleLoader.call_deferred("start_battle", list, get_tree().current_scene.scene_file_path)
