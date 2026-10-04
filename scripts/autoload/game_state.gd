extends Node

signal gold_changed(new_total: int)
signal party_changed

const MAX_ACTIVE_PARTY := 4
const MAX_TOTAL_PARTY := 8

var party: Array[ActorStats] = []
var reserve: Array[ActorStats] = []
var gold: int = 100
var party_position: Vector2 = Vector2.ZERO
var pending_battle_enemies: Array[EnemyData] = []
var last_world_scene: String = "res://scenes/world/world.tscn"
var opened_chests: Dictionary = {}
var completed_events: Dictionary = {}
var affinity: Dictionary = {}
var quests: Dictionary = {}  # quest_id -> { status, progress }
var skill_points: Dictionary = {}  # actor_name -> int
var unlocked_tree_index: Dictionary = {}  # actor_name -> int (last unlocked entry idx; -1 = none)
var bestiary: Dictionary = {}  # enemy_resource_path -> { seen: true, kills: int }

signal skill_points_changed(actor_name: String, value: int)

signal affinity_changed(a: String, b: String, level: int)
signal quest_changed(quest_id: String)

func is_chest_open(id: String) -> bool:
	return opened_chests.get(id, false)

func mark_chest_open(id: String) -> void:
	opened_chests[id] = true

func is_event_done(id: String) -> bool:
	return completed_events.get(id, false)

func mark_event_done(id: String) -> void:
	completed_events[id] = true

func give_item(item: ItemData) -> void:
	if item == null or party.is_empty(): return
	party[0].inventory.append(item)
	party_changed.emit()

# ---------- Affinity ----------
func _pair_key(a: String, b: String) -> String:
	if a <= b: return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]

func get_affinity(a: String, b: String) -> int:
	return int(affinity.get(_pair_key(a, b), 0))

func gain_affinity(a: String, b: String, amount: int) -> void:
	if a == b: return
	var key := _pair_key(a, b)
	var lvl := int(affinity.get(key, 0))
	lvl = clamp(lvl + amount, 0, 100)
	affinity[key] = lvl
	affinity_changed.emit(a, b, lvl)

func gain_party_affinity(amount: int) -> void:
	for i in party.size():
		for j in range(i + 1, party.size()):
			gain_affinity(party[i].actor_name, party[j].actor_name, amount)

# ---------- Quests ----------
func quest_status(quest_id: String) -> String:
	var entry: Dictionary = quests.get(quest_id, {})
	return str(entry.get("status", "hidden"))

func start_quest(quest: Resource) -> bool:
	if quest == null: return false
	var id := str(quest.get("quest_id"))
	if quests.has(id): return false
	quests[id] = { "status": "active", "data_path": quest.resource_path }
	quest_changed.emit(id)
	return true

func complete_quest(quest: Resource) -> bool:
	if quest == null: return false
	var id := str(quest.get("quest_id"))
	if not quests.has(id) or quests[id].get("status") != "active":
		return false
	quests[id]["status"] = "completed"
	if "reward_gold" in quest:
		add_gold(int(quest.get("reward_gold")))
	if "reward_items" in quest:
		for it in quest.get("reward_items"):
			if it is ItemData:
				give_item(it)
	quest_changed.emit(id)
	return true

func active_quests() -> Array:
	var out: Array = []
	for id in quests.keys():
		if quests[id].get("status") == "active":
			out.append(id)
	return out

func completed_quests() -> Array:
	var out: Array = []
	for id in quests.keys():
		if quests[id].get("status") == "completed":
			out.append(id)
	return out

# ---------- Skill Tree ----------
func get_sp(actor_name: String) -> int:
	return int(skill_points.get(actor_name, 0))

func add_sp(actor_name: String, amount: int) -> void:
	var v := get_sp(actor_name) + amount
	skill_points[actor_name] = v
	skill_points_changed.emit(actor_name, v)

func unlocked_index(actor_name: String) -> int:
	return int(unlocked_tree_index.get(actor_name, -1))

func can_unlock_next(actor: ActorStats) -> bool:
	if actor == null or actor.skill_tree == null: return false
	var next_idx := unlocked_index(actor.actor_name) + 1
	if next_idx >= actor.skill_tree.entries.size(): return false
	var entry: SkillTreeEntry = actor.skill_tree.entries[next_idx]
	if entry == null or entry.skill == null: return false
	return get_sp(actor.actor_name) >= entry.sp_cost

func register_enemy_seen(enemy_data: EnemyData) -> void:
	if enemy_data == null or enemy_data.resource_path == "": return
	var key := enemy_data.resource_path
	if not bestiary.has(key):
		bestiary[key] = { "seen": true, "kills": 0 }
	else:
		bestiary[key]["seen"] = true

func register_enemy_killed(enemy_data: EnemyData) -> void:
	if enemy_data == null or enemy_data.resource_path == "": return
	var key := enemy_data.resource_path
	if not bestiary.has(key):
		bestiary[key] = { "seen": true, "kills": 1 }
	else:
		bestiary[key]["kills"] = int(bestiary[key].get("kills", 0)) + 1

func unlock_next(actor: ActorStats) -> bool:
	if not can_unlock_next(actor): return false
	var next_idx := unlocked_index(actor.actor_name) + 1
	var entry: SkillTreeEntry = actor.skill_tree.entries[next_idx]
	add_sp(actor.actor_name, -entry.sp_cost)
	unlocked_tree_index[actor.actor_name] = next_idx
	if not actor.skills.has(entry.skill):
		actor.skills.append(entry.skill)
	party_changed.emit()
	return true

func _ready() -> void:
	_init_default_party()

func _init_default_party() -> void:
	var hero := load("res://data/actors/hero.tres") as ActorStats
	if hero == null:
		hero = ActorStats.new()
		hero.actor_name = "Min"
	party = [hero]

signal level_up(actor_name: String, new_level: int)

func add_exp_and_gold(exp_total: int, gold_total: int) -> void:
	add_gold(gold_total)
	if party.is_empty(): return
	var per_actor: int = max(1, int(float(exp_total) / float(party.size())))
	for a in party:
		var levels := a.gain_exp(per_actor)
		if levels > 0:
			level_up.emit(a.actor_name, a.level)
			print("[GameState] %s subió a nivel %d (+%d)" % [a.actor_name, a.level, levels])
		add_sp(a.actor_name, 1)
	party_changed.emit()

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func can_afford(price: int) -> bool:
	return gold >= price

func buy_item(item: ItemData, price: int) -> bool:
	if not can_afford(price) or item == null:
		return false
	gold -= price
	if party.size() > 0:
		party[0].inventory.append(item)
	gold_changed.emit(gold)
	party_changed.emit()
	return true

func rest_party() -> void:
	for a in party:
		a.current_hp = -1
		a.current_mp = -1
	party_changed.emit()

func has_member(actor_name: String) -> bool:
	for a in party:
		if a and a.actor_name == actor_name:
			return true
	for a in reserve:
		if a and a.actor_name == actor_name:
			return true
	return false

func add_member(actor: ActorStats) -> bool:
	if actor == null:
		return false
	if has_member(actor.actor_name):
		return false
	if party.size() + reserve.size() >= MAX_TOTAL_PARTY:
		return false
	actor.current_hp = -1
	actor.current_mp = -1
	if party.size() < MAX_ACTIVE_PARTY:
		party.append(actor)
	else:
		reserve.append(actor)
	party_changed.emit()
	return true

func bench_active(index: int) -> bool:
	if index < 0 or index >= party.size(): return false
	if party.size() <= 1: return false
	var a := party[index]
	party.remove_at(index)
	reserve.append(a)
	party_changed.emit()
	return true

func activate_reserve(index: int) -> bool:
	if index < 0 or index >= reserve.size(): return false
	if party.size() >= MAX_ACTIVE_PARTY: return false
	var a := reserve[index]
	reserve.remove_at(index)
	party.append(a)
	party_changed.emit()
	return true
