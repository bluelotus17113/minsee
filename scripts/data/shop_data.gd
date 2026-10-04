@tool
class_name ShopData
extends Resource

@export var shop_name: String = "Tienda"
@export_multiline var greeting: String = "¿Qué te llevarías?"
@export var entries: Array[ShopEntry] = []
@export var sell_back_multiplier: float = 0.5
