extends Node

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"

signal battle_finished(victory: bool)

func start_battle(enemies: Array[EnemyData], return_scene: String) -> void:
	GameState.pending_battle_enemies = enemies
	GameState.last_world_scene = return_scene
	get_tree().change_scene_to_file(BATTLE_SCENE)

func end_battle(victory: bool) -> void:
	battle_finished.emit(victory)
	get_tree().change_scene_to_file(GameState.last_world_scene)
