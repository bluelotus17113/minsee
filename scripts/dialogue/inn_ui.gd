extends CanvasLayer

signal closed

@onready var title_label: Label = $Panel/VBox/Title
@onready var prompt_label: Label = $Panel/VBox/Prompt
@onready var gold_label: Label = $Panel/VBox/Gold
@onready var yes_btn: Button = $Panel/VBox/Buttons/Yes
@onready var no_btn: Button = $Panel/VBox/Buttons/No

var inn_cost: int = 30
var success_msg: String = "Has recuperado fuerzas."
var no_gold_msg: String = "No tienes suficiente oro."

func _ready() -> void:
	yes_btn.pressed.connect(_on_yes)
	no_btn.pressed.connect(_on_no)
	gold_label.text = "Oro: %d" % GameState.gold

func setup(npc_name: String, cost: int, prompt: String, success: String, no_gold: String) -> void:
	title_label.text = npc_name
	inn_cost = cost
	prompt_label.text = prompt % cost
	success_msg = success
	no_gold_msg = no_gold

func _on_yes() -> void:
	if GameState.can_afford(inn_cost):
		GameState.add_gold(-inn_cost)
		GameState.rest_party()
		prompt_label.text = success_msg
		yes_btn.visible = false
		no_btn.text = "Salir"
	else:
		prompt_label.text = no_gold_msg

func _on_no() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		_on_no()
		get_viewport().set_input_as_handled()
