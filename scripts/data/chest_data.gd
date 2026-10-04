@tool
class_name ChestData
extends Resource

@export var chest_id: String = "cofre"
@export var label: String = "Cofre"
@export var description: String = ""
@export var gold: int = 0
@export var items: Array[ItemData] = []
@export var locked: bool = false
@export var key_item_id: String = ""
@export var sprite: Texture2D
@export var color_closed: Color = Color(0.65, 0.45, 0.18)
@export var color_open: Color = Color(0.35, 0.27, 0.15)
@export var open_dialogue: DialogueData
