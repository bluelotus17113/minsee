@tool
class_name DialogueData
extends Resource

@export var dialogue_id: String = "dialogo"
@export var speaker_name: String = "NPC"
@export var portrait: Texture2D
@export var lines: PackedStringArray = PackedStringArray(["Hola, viajero."])
@export var next_dialogue: DialogueData
@export var auto_advance_seconds: float = 0.0
