@tool
class_name ItemData
extends Resource

enum Effect { HEAL_HP, HEAL_MP, REVIVE, BUFF_ATK, BUFF_DEF }

@export var item_name: String = "Potion"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var effect: Effect = Effect.HEAL_HP
@export var power: int = 30
@export var price: int = 50
@export var consumable: bool = true
