@tool
class_name EncounterTableData
extends Resource

@export var table_name: String = "Tabla de encuentros"
@export_multiline var description: String = ""
@export var entries: Array[EncounterTableEntry] = []

@export_group("Frecuencia")
@export_range(20, 600) var pixels_per_check: int = 140
@export_range(0.0, 1.0) var encounter_chance: float = 0.25
@export_range(0.0, 1.0) var escape_chance: float = 0.5

@export_group("Margen")
@export_range(0.0, 8.0) var initial_grace_seconds: float = 1.5
@export_range(0.0, 8.0) var post_battle_grace_seconds: float = 2.5
