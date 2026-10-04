@tool
class_name EnemyData
extends Resource

@export var enemy_name: String = "Slime"
@export_multiline var description: String = ""
@export var sprite: Texture2D
@export var animations: SpriteFrames
@export var default_animation: String = "idle"
@export_range(8, 128) var sprite_size: int = 32
@export var color: Color = Color(0.4, 0.7, 0.3)

@export_group("Stats")
@export var max_hp: int = 40
@export var max_mp: int = 10
@export var max_cp: int = 100
@export var attack: int = 8
@export var defense: int = 4
@export var magic: int = 4
@export var speed: int = 6
@export var luck: int = 2

@export_group("Táctica")
@export_range(1, 8) var move_range: int = 2
@export_range(1, 4) var melee_range: int = 1

@export_group("Resistencias elementales")
@export_flags("Físico", "Fuego", "Agua", "Hielo", "Rayo", "Tierra", "Viento", "Sagrado", "Sombra", "Arcano") var weaknesses_flags: int = 0
@export_flags("Físico", "Fuego", "Agua", "Hielo", "Rayo", "Tierra", "Viento", "Sagrado", "Sombra", "Arcano") var resistances_flags: int = 0
@export_flags("Físico", "Fuego", "Agua", "Hielo", "Rayo", "Tierra", "Viento", "Sagrado", "Sombra", "Arcano") var immunities_flags: int = 0
@export_range(50, 500) var break_threshold: int = 100

@export_group("Rewards")
@export var exp_reward: int = 10
@export var gold_reward: int = 8
@export var drop_item: ItemData
@export var drop_chance: float = 0.1

@export_group("AI")
@export var skills: Array[SkillData] = []
@export var skill_use_chance: float = 0.3
