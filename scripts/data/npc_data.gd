@tool
class_name NPCData
extends Resource

enum NPCType { DIALOGUE, SHOP, INN, QUEST, RECRUIT }

@export var npc_name: String = "Aldeano"
@export_multiline var description: String = ""
@export var type: NPCType = NPCType.DIALOGUE
@export var portrait: Texture2D
## Modelo 3D del NPC (.glb de scenes/world/3d/chars/). Es lo que se ve en el
## mundo desde el giro a 3D.
@export var model: PackedScene

@export_group("Legado 2D")
## Los cuatro de abajo son del enfoque pixel art anterior. Siguen aquí porque
## scenes/world/*.tscn (las escenas 2D) todavía los leen.
@export var sprite: Texture2D
@export var animations: SpriteFrames
@export var default_animation: String = "idle"
@export_range(8, 128) var sprite_size: int = 24
@export var color: Color = Color(0.9, 0.85, 0.6)

@export_group("Diálogo")
@export var dialogue: DialogueData
@export var repeat_dialogue: DialogueData
@export var can_repeat: bool = true

@export_group("Tienda")
@export var shop_data: ShopData
@export var shop_intro_dialogue: DialogueData

@export_group("Posada")
@export var inn_cost: int = 30
@export var inn_prompt: String = "¿Quieres descansar por %d de oro?"
@export var inn_success: String = "Has recuperado fuerzas."
@export var inn_no_gold: String = "No tienes suficiente oro."

@export_group("Reclutamiento")
@export var recruit_actor: ActorStats
@export var recruit_cost: int = 0
@export_multiline var recruit_pitch: String = "Si me das %d de oro, te acompañaré."
@export_multiline var recruit_success: String = "¡Cuenta conmigo!"
@export_multiline var recruit_no_gold: String = "Vuelve cuando tengas oro suficiente."
@export_multiline var recruit_already: String = "Ya estoy en tu grupo."

@export_group("Quest")
@export var quest: Resource  # QuestData
@export var quest_offer_dialogue: DialogueData
@export var quest_active_dialogue: DialogueData
@export var quest_complete_dialogue: DialogueData
@export var quest_done_dialogue: DialogueData
@export var auto_complete_on_talk: bool = true
