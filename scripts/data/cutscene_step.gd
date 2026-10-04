@tool
class_name CutsceneStep
extends Resource

enum StepType {
	SAY,
	WAIT,
	SET_FLAG,
	CLEAR_FLAG,
	ADVANCE_CHAPTER,
	GIVE_ITEM,
	GIVE_GOLD,
	PLAY_DIALOGUE,
	CHANGE_SCENE,
	FADE_OUT,
	FADE_IN,
	START_BATTLE,
	MOVE_NODE,
	HIDE_NODE,
	SHOW_NODE,
	REQUIRE_FLAG,  # aborta la cutscene si la flag no se cumple
}

@export var type: StepType = StepType.SAY

@export_group("Say / Diálogo")
@export var speaker_name: String = ""
@export_multiline var text: String = ""
@export var dialogue: DialogueData

@export_group("Tiempo")
@export var wait_seconds: float = 0.5
@export var fade_seconds: float = 0.4

@export_group("Story")
@export var flag_key: String = ""
@export var flag_value: bool = true
@export var chapter_to: int = -1  # -1 = increment

@export_group("Recompensa")
@export var item: ItemData
@export var gold: int = 0

@export_group("Escena / Nodo")
@export_file("*.tscn") var scene_path: String = ""
@export var portal_id: String = ""
@export var target_node_path: NodePath
@export var target_position: Vector2 = Vector2.ZERO
@export var move_speed: float = 80.0

@export_group("Combate")
@export var enemies: Array[EnemyData] = []
