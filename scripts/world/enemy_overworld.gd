@tool
extends Area2D

@export var encounter: EncounterData:
	set(v):
		encounter = v
		if is_inside_tree():
			_refresh_visual()
@export var enemies: Array[EnemyData] = []:
	set(v):
		enemies = v
		if is_inside_tree():
			_refresh_visual()
@export var wander_speed: float = 25.0
@export var wander_radius: float = 40.0
@export var token_color: Color = Color(0.82, 0.27, 0.28, 1):
	set(v):
		token_color = v
		if is_inside_tree():
			_refresh_visual()

var _origin: Vector2
var _target: Vector2
var _triggered: bool = false

func _ready() -> void:
	_refresh_visual()
	if Engine.is_editor_hint():
		return
	_origin = global_position
	_pick_new_target()
	body_entered.connect(_on_body_entered)
	if encounter == null and enemies.is_empty():
		var fallback := load("res://data/enemies/slime.tres") as EnemyData
		if fallback:
			enemies = [fallback]
			_refresh_visual()

func _first_enemy_data() -> EnemyData:
	if encounter and encounter.enemies.size() > 0:
		return encounter.enemies[0]
	if enemies.size() > 0:
		return enemies[0]
	return null

func _refresh_visual() -> void:
	var color_rect := get_node_or_null("Sprite") as ColorRect
	var static_sprite := get_node_or_null("StaticSprite") as Sprite2D
	var anim_sprite := get_node_or_null("AnimatedSprite") as AnimatedSprite2D
	var data := _first_enemy_data()
	if data and data.animations != null and data.animations.has_animation(data.default_animation):
		if color_rect: color_rect.visible = false
		if static_sprite: static_sprite.visible = false
		if anim_sprite:
			anim_sprite.visible = true
			anim_sprite.sprite_frames = data.animations
			anim_sprite.animation = data.default_animation
			anim_sprite.play()
	elif data and data.sprite != null:
		if color_rect: color_rect.visible = false
		if anim_sprite: anim_sprite.visible = false
		if static_sprite:
			static_sprite.visible = true
			static_sprite.texture = data.sprite
			var w := float(data.sprite.get_width())
			if w > 0:
				static_sprite.scale = Vector2.ONE * (float(data.sprite_size) / w)
	else:
		if anim_sprite: anim_sprite.visible = false
		if static_sprite: static_sprite.visible = false
		if color_rect:
			color_rect.visible = true
			color_rect.color = data.color if data else token_color

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _triggered:
		return
	var dir := (_target - global_position)
	if dir.length() < 4.0:
		_pick_new_target()
	else:
		global_position += dir.normalized() * wander_speed * delta

func _pick_new_target() -> void:
	var angle := randf() * TAU
	_target = _origin + Vector2(cos(angle), sin(angle)) * wander_radius

func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if body.is_in_group("player"):
		_triggered = true
		var enemy_list: Array[EnemyData] = []
		if encounter and encounter.enemies.size() > 0:
			enemy_list = encounter.enemies.duplicate()
		else:
			enemy_list = enemies.duplicate()
		if enemy_list.is_empty():
			var fallback := EnemyData.new()
			fallback.enemy_name = "Slime"
			enemy_list = [fallback]
		BattleLoader.call_deferred("start_battle", enemy_list, get_tree().current_scene.scene_file_path)
