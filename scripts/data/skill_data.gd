@tool
class_name SkillData
extends Resource

enum Kind { ART, CRAFT }
enum Target { SINGLE_ENEMY, ALL_ENEMIES, SINGLE_ALLY, ALL_ALLIES, SELF, TILE }
enum DamageType { PHYSICAL, MAGICAL, HEAL }
enum AoEShape { SINGLE, CROSS, SQUARE, LINE }
enum CraftEffect { NONE, PUSH, STUN, DRAIN_MP, BUFF_ATK, BUFF_DEF }
enum Element { NONE, FISICO, FUEGO, AGUA, HIELO, RAYO, TIERRA, VIENTO, SAGRADO, SOMBRA, ARCANO }

const ELEMENT_NAMES := ["—", "Físico", "Fuego", "Agua", "Hielo", "Rayo", "Tierra", "Viento", "Sagrado", "Sombra", "Arcano"]

@export var skill_name: String = "Bola de Fuego"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var kind: Kind = Kind.ART
@export var target: Target = Target.SINGLE_ENEMY
@export var damage_type: DamageType = DamageType.MAGICAL
@export var element: Element = Element.NONE
@export var power: int = 25
@export var accuracy: int = 95
@export_range(0, 100) var break_power: int = 15

@export_group("Costo")
@export var mp_cost: int = 6
@export var cp_cost: int = 0

@export_group("Tiempo y alcance")
@export_range(0, 5) var cast_time: int = 1
@export_range(1, 10) var skill_range: int = 3
@export var aoe_shape: AoEShape = AoEShape.SINGLE
@export_range(0, 3) var aoe_radius: int = 0

@export_group("Craft")
@export var craft_effect: CraftEffect = CraftEffect.NONE
@export_range(0, 5) var push_distance: int = 0
@export_range(0, 3) var stun_turns: int = 0
@export_range(0, 100) var buff_amount: int = 0
@export_range(0, 5) var buff_turns: int = 0

@export_group("Limit Break / S-Craft")
@export var is_limit_break: bool = false
@export_range(100, 200) var limit_min_cp: int = 100
@export_range(0, 5) var limit_damage_mult: float = 2.5
