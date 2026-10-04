@tool
class_name EncounterData
extends Resource

@export var encounter_name: String = "Encuentro"
@export_multiline var description: String = ""
@export var enemies: Array[EnemyData] = []
@export var background: Texture2D
@export var music: AudioStream

func get_enemy_count() -> int:
	return enemies.size()
