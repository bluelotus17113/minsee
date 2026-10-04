@tool
class_name QuestData
extends Resource

@export var quest_id: String = "quest"
@export var title: String = "Misión"
@export_multiline var description: String = ""
@export var objectives: PackedStringArray = PackedStringArray(["Habla con el NPC"])
@export var reward_gold: int = 0
@export var reward_items: Array[ItemData] = []
@export var reward_exp: int = 0
