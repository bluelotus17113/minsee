extends CanvasLayer

signal closed

@onready var title_label: Label = $Panel/VBox/Title
@onready var stats_label: Label = $Panel/VBox/Stats
@onready var prompt_label: Label = $Panel/VBox/Prompt
@onready var gold_label: Label = $Panel/VBox/Gold
@onready var yes_btn: Button = $Panel/VBox/Buttons/Yes
@onready var no_btn: Button = $Panel/VBox/Buttons/No

var recruit_actor: ActorStats
var cost: int = 0
var success_msg: String = "¡Cuenta conmigo!"
var no_gold_msg: String = "Vuelve cuando tengas oro."
var already_msg: String = "Ya estoy en tu grupo."

func _ready() -> void:
	yes_btn.pressed.connect(_on_yes)
	no_btn.pressed.connect(_on_no)
	_refresh_gold()

func setup(npc_name: String, actor: ActorStats, recruit_cost: int, pitch: String, success: String, no_gold: String, already: String) -> void:
	title_label.text = npc_name
	recruit_actor = actor
	cost = recruit_cost
	success_msg = success
	no_gold_msg = no_gold
	already_msg = already
	if actor:
		stats_label.text = "%s · HP %d · MP %d · ATK %d · DEF %d · SPD %d" % [actor.actor_name, actor.max_hp, actor.max_mp, actor.attack, actor.defense, actor.speed]
	else:
		stats_label.text = "(actor no definido)"
	prompt_label.text = pitch % cost if "%d" in pitch else pitch
	if actor and GameState.has_member(actor.actor_name):
		prompt_label.text = already_msg
		yes_btn.visible = false
		no_btn.text = "Salir"

func _refresh_gold() -> void:
	gold_label.text = "Oro: %d" % GameState.gold

func _on_yes() -> void:
	if recruit_actor == null:
		return
	if GameState.has_member(recruit_actor.actor_name):
		prompt_label.text = already_msg
		yes_btn.visible = false
		no_btn.text = "Salir"
		return
	if not GameState.can_afford(cost):
		prompt_label.text = no_gold_msg
		_refresh_gold()
		return
	GameState.add_gold(-cost)
	GameState.add_member(recruit_actor)
	prompt_label.text = success_msg
	yes_btn.visible = false
	no_btn.text = "Salir"
	_refresh_gold()

func _on_no() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		_on_no()
		get_viewport().set_input_as_handled()
