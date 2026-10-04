@tool
class_name EncounterTableEntry
extends Resource

@export var encounter: EncounterData
@export_range(1, 100) var weight: int = 10
@export_multiline var note: String = ""

@export_group("Condiciones")
@export_range(0, 20) var min_chapter: int = 0
@export var requires_flag: String = ""
@export var blocked_by_flag: String = ""
