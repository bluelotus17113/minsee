@tool
class_name CutsceneData
extends Resource

@export var cutscene_id: String = "cutscene"
@export var label: String = "Cutscene"
@export_multiline var description: String = ""
@export var steps: Array[CutsceneStep] = []
@export var run_once: bool = true
