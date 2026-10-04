extends Control

@onready var master_slider: HSlider = $Panel/VBox/Master/Slider
@onready var fullscreen_check: CheckButton = $Panel/VBox/Fullscreen
@onready var close_btn: Button = $Panel/VBox/Close

func _ready() -> void:
	close_btn.pressed.connect(queue_free)
	var bus_idx := AudioServer.get_bus_index("Master")
	master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	master_slider.value_changed.connect(_on_master)
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_check.toggled.connect(_on_fullscreen)

func _on_master(value: float) -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))

func _on_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
