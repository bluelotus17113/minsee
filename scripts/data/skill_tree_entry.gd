@tool
class_name SkillTreeEntry
extends Resource

@export var skill: SkillData
@export_range(1, 10) var sp_cost: int = 1
@export_multiline var note: String = ""
