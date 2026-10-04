@tool
class_name EventData
extends Resource

enum EventAction { DIALOGUE_ONLY, GIVE_ITEM, GIVE_GOLD, RECRUIT, TELEPORT, COMBAT, CUSTOM, CUTSCENE }

@export var event_id: String = "evento_unico"
@export var label: String = "Evento"
@export_multiline var description: String = ""
@export var trigger_dialogue: DialogueData
@export var action: EventAction = EventAction.DIALOGUE_ONLY
@export var reward_items: Array[ItemData] = []
@export var reward_gold: int = 0
@export var recruit_actor: ActorStats
@export var teleport_scene: String = ""
@export var teleport_position: Vector2 = Vector2.ZERO
@export var combat_enemies: Array[EnemyData] = []
@export var post_dialogue: DialogueData
@export var cutscene: CutsceneData

@export_group("Condiciones de aparición")
@export var requires_flag: String = ""
@export var requires_chapter_at_least: int = 0
@export var blocked_by_flag: String = ""
