@tool
class_name ShopEntry
extends Resource

@export var item: ItemData
@export var price_override: int = -1
@export var stock: int = -1

func effective_price() -> int:
	if price_override >= 0:
		return price_override
	if item:
		return item.price
	return 0
