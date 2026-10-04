extends CanvasLayer

signal closed

@onready var title_label: Label = $Panel/VBox/Header/Title
@onready var gold_label: Label = $Panel/VBox/Header/Gold
@onready var greeting_label: Label = $Panel/VBox/Greeting
@onready var item_list: VBoxContainer = $Panel/VBox/Scroll/List
@onready var close_btn: Button = $Panel/VBox/Footer/Close
@onready var status_label: Label = $Panel/VBox/Footer/Status

var shop_data: ShopData

func _ready() -> void:
	close_btn.pressed.connect(_on_close_pressed)
	GameState.gold_changed.connect(_refresh_gold)

func setup(data: ShopData) -> void:
	shop_data = data
	title_label.text = data.shop_name
	greeting_label.text = data.greeting
	_refresh_gold(GameState.gold)
	_populate()
	status_label.text = ""

func _refresh_gold(g: int) -> void:
	gold_label.text = "Oro: %d" % g

func _populate() -> void:
	for child in item_list.get_children():
		child.queue_free()
	if shop_data == null:
		return
	for entry in shop_data.entries:
		if entry == null or entry.item == null:
			continue
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = entry.item.item_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var price_lbl := Label.new()
		price_lbl.text = "%d oro" % entry.effective_price()
		row.add_child(price_lbl)
		var buy_btn := Button.new()
		buy_btn.text = "Comprar"
		buy_btn.disabled = not GameState.can_afford(entry.effective_price())
		buy_btn.pressed.connect(_on_buy.bind(entry))
		row.add_child(buy_btn)
		item_list.add_child(row)

func _on_buy(entry: ShopEntry) -> void:
	if GameState.buy_item(entry.item, entry.effective_price()):
		status_label.text = "Compraste %s." % entry.item.item_name
	else:
		status_label.text = "No tienes oro suficiente."
	_populate()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
