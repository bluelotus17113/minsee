@tool
class_name ActorStats
extends Resource

@export var actor_name: String = "Hero"
@export var portrait: Texture2D
@export var sprite: Texture2D
@export var animations: SpriteFrames
@export var default_animation: String = "idle"
@export_range(8, 128) var sprite_size: int = 32
@export var color: Color = Color(0.35, 0.49, 0.81)

# Estado entre batallas (no serializado, -1 = usar max)
var current_hp: int = -1
var current_mp: int = -1

@export_group("Progresión")
@export var level: int = 1
@export var current_exp: int = 0
@export_range(0, 80) var hp_growth: int = 15
@export_range(0, 40) var mp_growth: int = 5
@export_range(0, 40) var cp_growth: int = 10
@export_range(0, 20) var atk_growth: int = 2
@export_range(0, 20) var def_growth: int = 2
@export_range(0, 20) var mag_growth: int = 2
@export_range(0, 20) var spd_growth: int = 1
@export_range(0, 20) var luk_growth: int = 1

@export_group("Base Stats")
@export var max_hp: int = 100
@export var max_mp: int = 30
@export var max_cp: int = 200
@export var attack: int = 12
@export var defense: int = 8
@export var magic: int = 10
@export var speed: int = 10
@export var luck: int = 5

@export_group("Táctica")
@export_range(1, 8) var move_range: int = 3
@export_range(1, 4) var melee_range: int = 1

@export_group("Resistencias elementales")
@export_flags("Físico", "Fuego", "Agua", "Hielo", "Rayo", "Tierra", "Viento", "Sagrado", "Sombra", "Arcano") var weaknesses_flags: int = 0
@export_flags("Físico", "Fuego", "Agua", "Hielo", "Rayo", "Tierra", "Viento", "Sagrado", "Sombra", "Arcano") var resistances_flags: int = 0
@export_flags("Físico", "Fuego", "Agua", "Hielo", "Rayo", "Tierra", "Viento", "Sagrado", "Sombra", "Arcano") var immunities_flags: int = 0
@export_range(50, 500) var break_threshold: int = 100

@export_group("Equipment & Skills")
@export var weapon: WeaponData
@export var skills: Array[SkillData] = []
@export var inventory: Array[ItemData] = []
@export var skill_tree: SkillTreeData

func effective_attack() -> int:
	var bonus := weapon.attack_bonus if weapon else 0
	return attack + bonus

func effective_speed() -> int:
	var penalty := weapon.speed_penalty if weapon else 0
	return max(1, speed - penalty)

func exp_to_next() -> int:
	return int(80.0 * pow(float(max(1, level)), 1.5))

func gain_exp(amount: int) -> int:
	# Devuelve niveles ganados
	var levels := 0
	current_exp += amount
	while current_exp >= exp_to_next():
		current_exp -= exp_to_next()
		level += 1
		max_hp += hp_growth
		max_mp += mp_growth
		max_cp += cp_growth
		attack += atk_growth
		defense += def_growth
		magic += mag_growth
		speed += spd_growth
		luck += luk_growth
		current_hp = -1  # full restore al subir nivel
		current_mp = -1
		levels += 1
	return levels
