extends CanvasLayer

@onready var box_panel: Panel = $Panel
@onready var speaker_label: Label = $Panel/VBox/Header/SpeakerLabel
@onready var portrait_rect: TextureRect = $Panel/VBox/Header/Portrait
@onready var text_label: RichTextLabel = $Panel/VBox/Text
@onready var hint_label: Label = $Panel/VBox/Hint

const CHARS_PER_SECOND := 50.0

var _full_text: String = ""
var _revealed: float = 0.0
var _finished_typing: bool = false

func _ready() -> void:
	DialogueManager.line_changed.connect(_on_line_changed)
	DialogueManager.dialogue_ended.connect(queue_free)
	hint_label.text = "[E] Continuar"

func _on_line_changed(speaker: String, text: String, portrait: Texture2D) -> void:
	speaker_label.text = speaker
	if portrait:
		portrait_rect.visible = true
		portrait_rect.texture = portrait
	else:
		portrait_rect.visible = false
	_full_text = text
	_revealed = 0.0
	_finished_typing = false
	text_label.text = ""

func _process(delta: float) -> void:
	if _finished_typing or _full_text == "":
		return
	_revealed += delta * CHARS_PER_SECOND
	var n: int = min(int(_revealed), _full_text.length())
	text_label.text = _full_text.substr(0, n)
	if n >= _full_text.length():
		_finished_typing = true

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("confirm"):
		if not _finished_typing:
			_finished_typing = true
			text_label.text = _full_text
		else:
			DialogueManager.advance()
		get_viewport().set_input_as_handled()
