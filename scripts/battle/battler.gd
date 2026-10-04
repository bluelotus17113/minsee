class_name Battler
extends RefCounted

signal hp_changed(new_hp: int)
signal mp_changed(new_mp: int)
signal cp_changed(new_cp: int)
signal died
signal moved(new_pos: Vector2i)
signal damage_taken(amount: int, was_crit: bool, was_weak: bool)
signal healed(amount: int)
signal break_triggered

var display_name: String
var is_player: bool

var max_hp: int
var max_mp: int
var max_cp: int
var hp: int
var mp: int
var cp: int = 0
var attack: int
var defense: int
var magic: int
var speed: int
var luck: int

var move_range: int = 3
var melee_range: int = 1
var grid_pos: Vector2i = Vector2i(-999, -999)
var color: Color = Color.WHITE
var sprite: Texture2D = null
var animations: SpriteFrames = null
var default_animation: String = "idle"
var sprite_size: int = 32

# Break / Stagger
var weaknesses_flags: int = 0
var resistances_flags: int = 0
var immunities_flags: int = 0
var break_threshold: int = 100
var break_gauge: int = 0
var broken: bool = false
var broken_turns: int = 0

var at_value: float = 0.0
var defending: bool = false
var stun_remaining: int = 0
var atk_buff: int = 0
var def_buff: int = 0
var buff_turns: int = 0

# Casting (Arts con cast_time): cuando es no-nulo, en el siguiente turno se resuelve.
var pending_skill: SkillData = null
var pending_target_cell: Vector2i = Vector2i.ZERO
var cast_remaining: int = 0
var is_casting: bool = false

var actor_stats: ActorStats
var enemy_data: EnemyData
var skills: Array[SkillData] = []

static func from_actor(stats: ActorStats) -> Battler:
	var b := Battler.new()
	b.display_name = stats.actor_name
	b.is_player = true
	b.max_hp = stats.max_hp
	b.max_mp = stats.max_mp
	b.max_cp = stats.max_cp
	b.hp = stats.current_hp if stats.current_hp >= 0 else stats.max_hp
	b.mp = stats.current_mp if stats.current_mp >= 0 else stats.max_mp
	b.cp = 0
	b.attack = stats.effective_attack()
	b.defense = stats.defense
	b.magic = stats.magic
	b.speed = stats.effective_speed()
	b.luck = stats.luck
	b.move_range = stats.move_range
	b.melee_range = stats.melee_range
	b.color = stats.color
	b.sprite = stats.sprite
	b.animations = stats.animations
	b.default_animation = stats.default_animation
	b.sprite_size = stats.sprite_size
	b.weaknesses_flags = stats.weaknesses_flags
	b.resistances_flags = stats.resistances_flags
	b.immunities_flags = stats.immunities_flags
	b.break_threshold = stats.break_threshold
	b.skills = stats.skills.duplicate()
	b.actor_stats = stats
	return b

static func from_enemy(data: EnemyData) -> Battler:
	var b := Battler.new()
	b.display_name = data.enemy_name
	b.is_player = false
	b.max_hp = data.max_hp
	b.max_mp = data.max_mp
	b.max_cp = data.max_cp
	b.hp = data.max_hp
	b.mp = data.max_mp
	b.cp = 0
	b.attack = data.attack
	b.defense = data.defense
	b.magic = data.magic
	b.speed = data.speed
	b.luck = data.luck
	b.move_range = data.move_range
	b.melee_range = data.melee_range
	b.color = data.color
	b.sprite = data.sprite
	b.animations = data.animations
	b.default_animation = data.default_animation
	b.sprite_size = data.sprite_size
	b.weaknesses_flags = data.weaknesses_flags
	b.resistances_flags = data.resistances_flags
	b.immunities_flags = data.immunities_flags
	b.break_threshold = data.break_threshold
	b.skills = data.skills.duplicate()
	b.enemy_data = data
	return b

func is_alive() -> bool:
	return hp > 0

func effective_attack() -> int:
	return attack + atk_buff

func effective_defense() -> int:
	return defense + def_buff

func take_damage(amount: int, was_crit: bool = false, was_weak: bool = false) -> int:
	var final_amount := amount
	if defending:
		final_amount = int(final_amount * 0.5)
	final_amount = max(1, final_amount)
	hp = max(0, hp - final_amount)
	hp_changed.emit(hp)
	damage_taken.emit(final_amount, was_crit, was_weak)
	gain_cp(5)
	if hp <= 0:
		died.emit()
	return final_amount

func heal(amount: int) -> int:
	var prev := hp
	hp = min(max_hp, hp + amount)
	hp_changed.emit(hp)
	var amt := hp - prev
	if amt > 0:
		healed.emit(amt)
	return amt

func restore_mp(amount: int) -> int:
	var prev := mp
	mp = min(max_mp, mp + amount)
	mp_changed.emit(mp)
	return mp - prev

func gain_cp(amount: int) -> void:
	cp = clamp(cp + amount, 0, max_cp)
	cp_changed.emit(cp)

func spend_mp(amount: int) -> bool:
	if mp < amount: return false
	mp -= amount
	mp_changed.emit(mp)
	return true

func spend_cp(amount: int) -> bool:
	if cp < amount: return false
	cp -= amount
	cp_changed.emit(cp)
	return true

func tick_buff_turns() -> void:
	if buff_turns > 0:
		buff_turns -= 1
		if buff_turns <= 0:
			atk_buff = 0
			def_buff = 0

func _elem_bit(elem: int) -> int:
	if elem == SkillData.Element.NONE: return 0
	return 1 << (elem - 1)

func is_weak_to(elem: int) -> bool:
	return (weaknesses_flags & _elem_bit(elem)) != 0

func resists(elem: int) -> bool:
	return (resistances_flags & _elem_bit(elem)) != 0

func is_immune_to(elem: int) -> bool:
	return (immunities_flags & _elem_bit(elem)) != 0

func gain_break(amount: int) -> bool:
	if broken or amount <= 0:
		return false
	break_gauge += amount
	if break_gauge >= break_threshold:
		broken = true
		broken_turns = 2
		break_gauge = break_threshold
		break_triggered.emit()
		return true
	return false

func consume_broken_turn() -> bool:
	if broken and broken_turns > 0:
		broken_turns -= 1
		if broken_turns <= 0:
			broken = false
			break_gauge = 0
		return true
	return false
