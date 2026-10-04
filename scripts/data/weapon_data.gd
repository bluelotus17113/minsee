@tool
class_name WeaponData
extends Resource

enum WeaponType { SWORD, DAGGER, STAFF, BOW, AXE, SPEAR }

@export var weapon_name: String = "Espada"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var type: WeaponType = WeaponType.SWORD
@export var attack_bonus: int = 5
@export var speed_penalty: int = 0
@export var crit_bonus: int = 0
@export var price: int = 100
