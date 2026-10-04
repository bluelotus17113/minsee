extends Control

@onready var slot_list: VBoxContainer = $Panel/VBox/Slots
@onready var close_btn: Button = $Panel/VBox/Footer/Close

func _ready() -> void:
	close_btn.pressed.connect(queue_free)
	_populate()

func _populate() -> void:
	for child in slot_list.get_children(): child.queue_free()
	for slot in SaveManager.SLOTS:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = SaveManager.format_slot(slot)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn_load := Button.new()
		btn_load.text = "Cargar"
		btn_load.disabled = not SaveManager.has_slot(slot)
		btn_load.pressed.connect(_on_load.bind(slot))
		row.add_child(btn_load)
		var btn_delete := Button.new()
		btn_delete.text = "Borrar"
		btn_delete.disabled = not SaveManager.has_slot(slot)
		btn_delete.pressed.connect(_on_delete.bind(slot))
		row.add_child(btn_delete)
		slot_list.add_child(row)

func _on_load(slot: int) -> void:
	if SaveManager.load_from_slot(slot):
		queue_free()

func _on_delete(slot: int) -> void:
	var path := SaveManager._slot_path(slot)
	var dir := DirAccess.open(path.get_base_dir())
	if dir:
		dir.remove(path.get_file())
	_populate()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
