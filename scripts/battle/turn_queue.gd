class_name TurnQueue
extends RefCounted

const AT_THRESHOLD: float = 100.0

enum TurnBonus { NONE, CRITICAL, HEAL_HP, HEAL_MP, CP_BOOST, ZERO_ARTS }

var battlers: Array[Battler] = []
var planned: Array = []  # Array[Dictionary]: {battler, bonus, eta}
const PLAN_DEPTH := 8

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func add(b: Battler) -> void:
	battlers.append(b)

func remove(b: Battler) -> void:
	battlers.erase(b)
	for i in range(planned.size() - 1, -1, -1):
		if planned[i]["battler"] == b:
			planned.remove_at(i)

func plan() -> void:
	planned.clear()
	var sim: Array = []
	for b in battlers:
		if b.is_alive():
			sim.append({ "b": b, "v": b.at_value })
	while planned.size() < PLAN_DEPTH and sim.size() > 0:
		var picked_index := -1
		var best: float = INF
		for i in sim.size():
			var entry: Dictionary = sim[i]
			var speed_val: float = float((entry["b"] as Battler).speed)
			var ticks_left: float = (AT_THRESHOLD - float(entry["v"])) / max(0.001, speed_val)
			if ticks_left < best:
				best = ticks_left
				picked_index = i
		if picked_index < 0:
			break
		var chosen: Dictionary = sim[picked_index]
		var slot := {
			"battler": chosen["b"] as Battler,
			"bonus": _roll_bonus(planned.size()),
			"eta": best,
		}
		planned.append(slot)
		# Pasa el tiempo para todos, no solo para quien actúa.
		for i in sim.size():
			var e: Dictionary = sim[i]
			e["v"] = float(e["v"]) + float((e["b"] as Battler).speed) * best
			sim[i] = e
		# Y el que actúa gasta el umbral.
		var usado: Dictionary = sim[picked_index]
		usado["v"] = float(usado["v"]) - AT_THRESHOLD
		sim[picked_index] = usado

func _roll_bonus(slot_index: int) -> int:
	if slot_index == 0:
		return TurnBonus.NONE
	var r: float = _rng.randf()
	if r < 0.50: return TurnBonus.NONE
	if r < 0.62: return TurnBonus.CRITICAL
	if r < 0.74: return TurnBonus.HEAL_HP
	if r < 0.84: return TurnBonus.HEAL_MP
	if r < 0.94: return TurnBonus.CP_BOOST
	return TurnBonus.ZERO_ARTS

func consume_next() -> Dictionary:
	if planned.is_empty():
		plan()
	if planned.is_empty():
		return {}
	var slot: Dictionary = planned.pop_front()
	var b: Battler = slot["battler"]
	# Avanzar AT simulando ticks hasta que actúe
	var eta: float = slot.get("eta", 0.0)
	for entry in battlers:
		if entry.is_alive():
			entry.at_value += float(entry.speed) * eta
	b.at_value -= AT_THRESHOLD
	if b.at_value < 0.0:
		b.at_value = 0.0
	return slot

func preview(count: int = PLAN_DEPTH) -> Array:
	if planned.is_empty():
		plan()
	return planned.slice(0, min(count, planned.size()))

func insert_cast_resolution(b: Battler, after_ticks: float, bonus: int = TurnBonus.NONE) -> void:
	# Replanea: removemos al battler de planned y lo metemos en posición acorde a after_ticks
	for i in range(planned.size() - 1, -1, -1):
		if planned[i]["battler"] == b:
			planned.remove_at(i)
	var insert_at := planned.size()
	var accum := 0.0
	for i in planned.size():
		accum += float(planned[i].get("eta", 0.0))
		if accum >= after_ticks:
			insert_at = i
			break
	planned.insert(insert_at, {
		"battler": b,
		"bonus": bonus,
		"eta": after_ticks,
	})

func bonus_label(bonus: int) -> String:
	match bonus:
		TurnBonus.CRITICAL: return "CRIT"
		TurnBonus.HEAL_HP: return "HP+"
		TurnBonus.HEAL_MP: return "MP+"
		TurnBonus.CP_BOOST: return "CP+"
		TurnBonus.ZERO_ARTS: return "0-CAST"
		_: return ""

func bonus_color(bonus: int) -> Color:
	match bonus:
		TurnBonus.CRITICAL: return Color(1, 0.4, 0.4)
		TurnBonus.HEAL_HP: return Color(0.4, 1, 0.5)
		TurnBonus.HEAL_MP: return Color(0.5, 0.7, 1)
		TurnBonus.CP_BOOST: return Color(1, 0.85, 0.3)
		TurnBonus.ZERO_ARTS: return Color(0.9, 0.5, 1)
		_: return Color(0.7, 0.7, 0.7)
