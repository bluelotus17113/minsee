class_name BattleManager
extends Node

signal log_message(text: String)
signal turn_started(battler: Battler, bonus: int)
signal need_player_action(battler: Battler)
signal battle_ended(victory: bool)
signal stats_changed
signal field_changed
signal preview_changed

enum ActionKind { ATTACK, ART, CRAFT, DEFEND, ITEM, RUN }

var allies: Array[Battler] = []
var enemies: Array[Battler] = []
var queue: TurnQueue
var field: BattleField
var current: Battler
var current_bonus: int = TurnQueue.TurnBonus.NONE
var finished: bool = false

func setup(party: Array[ActorStats], enemy_list: Array[EnemyData]) -> void:
	queue = TurnQueue.new()
	field = BattleField.new()
	for i in party.size():
		var b := Battler.from_actor(party[i])
		allies.append(b)
		queue.add(b)
		# place() ya busca hueco libre si el sitio está ocupado.
		field.place(b, BattleField.spawn_pos(i, party.size(), true))
	for i in enemy_list.size():
		var b := Battler.from_enemy(enemy_list[i])
		enemies.append(b)
		queue.add(b)
		field.place(b, BattleField.spawn_pos(i, enemy_list.size(), false))
		GameState.register_enemy_seen(enemy_list[i])
		b.died.connect(GameState.register_enemy_killed.bind(enemy_list[i]))
	queue.plan()

func start() -> void:
	log_message.emit("¡Comienza la batalla!")
	preview_changed.emit()
	_advance()

func _advance() -> void:
	if finished:
		return
	if _all_dead(enemies):
		_finish(true)
		return
	if _all_dead(allies):
		_finish(false)
		return
	var slot := queue.consume_next()
	if slot.is_empty():
		_finish(false)
		return
	current = slot["battler"]
	current_bonus = slot.get("bonus", TurnQueue.TurnBonus.NONE)
	if not current.is_alive():
		_advance()
		return
	current.defending = false
	current.tick_buff_turns()

	_apply_pre_turn_bonus(current, current_bonus)
	preview_changed.emit()
	turn_started.emit(current, current_bonus)

	if current.consume_broken_turn():
		log_message.emit("[color=#5cc8ff][BREAK][/color] %s está conmocionado y pierde el turno." % current.display_name)
		stats_changed.emit()
		await get_tree().create_timer(0.6).timeout
		_advance()
		return

	if current.stun_remaining > 0:
		current.stun_remaining -= 1
		log_message.emit("%s está aturdido y pierde el turno." % current.display_name)
		await get_tree().create_timer(0.4).timeout
		_advance()
		return

	if current.is_casting:
		_resolve_cast(current)
		await get_tree().create_timer(0.5).timeout
		_advance()
		return

	if current.is_player:
		need_player_action.emit(current)
	else:
		await get_tree().create_timer(0.4).timeout
		_enemy_ai(current)

func _apply_pre_turn_bonus(b: Battler, bonus: int) -> void:
	match bonus:
		TurnQueue.TurnBonus.HEAL_HP:
			var amount := int(b.max_hp * 0.20)
			var healed := b.heal(amount)
			if healed > 0:
				log_message.emit("Bono HP+: %s recupera %d HP." % [b.display_name, healed])
		TurnQueue.TurnBonus.HEAL_MP:
			var amount := int(b.max_mp * 0.30)
			var restored := b.restore_mp(amount)
			if restored > 0:
				log_message.emit("Bono MP+: %s recupera %d MP." % [b.display_name, restored])
		TurnQueue.TurnBonus.CP_BOOST:
			b.gain_cp(50)
			log_message.emit("Bono CP+: %s gana 50 CP." % b.display_name)
	stats_changed.emit()

# ---------- Acciones jugador ----------

func submit_attack(target_pos: Vector2) -> void:
	if current == null or not current.is_player: return
	var target: Battler = field.get_at(target_pos)
	if target == null or target.is_player:
		log_message.emit("Ahí no hay ningún enemigo.")
		return
	if BattleField.distance(current.field_pos, target.field_pos) > current.melee_range:
		log_message.emit("Fuera de alcance.")
		return
	_do_attack(current, target)
	stats_changed.emit()
	await get_tree().create_timer(0.4).timeout
	_advance()

func submit_art(skill: SkillData, target_pos: Vector2) -> void:
	if current == null or not current.is_player: return
	if not current.spend_mp(skill.mp_cost):
		log_message.emit("Sin MP suficiente.")
		need_player_action.emit(current)
		return
	var cast_time := skill.cast_time
	if current_bonus == TurnQueue.TurnBonus.ZERO_ARTS:
		cast_time = 0
		log_message.emit("¡0-CAST! El Art se lanza al instante.")
	if cast_time <= 0:
		_resolve_art_now(current, skill, target_pos)
	else:
		current.is_casting = true
		current.pending_skill = skill
		current.pending_target_pos = target_pos
		current.cast_remaining = cast_time
		log_message.emit("%s canaliza %s..." % [current.display_name, skill.skill_name])
		queue.insert_cast_resolution(current, float(cast_time))
	preview_changed.emit()
	stats_changed.emit()
	await get_tree().create_timer(0.4).timeout
	_advance()

func submit_craft(skill: SkillData, target_pos: Vector2) -> void:
	if current == null or not current.is_player: return
	if skill.is_limit_break:
		if current.cp < skill.limit_min_cp:
			log_message.emit("Necesitas %d CP para %s." % [skill.limit_min_cp, skill.skill_name])
			need_player_action.emit(current)
			return
		current.cp = 0
		current.cp_changed.emit(current.cp)
		log_message.emit("[color=#ff66cc][S-CRAFT][/color] ¡%s desata %s!" % [current.display_name, skill.skill_name])
	elif not current.spend_cp(skill.cp_cost):
		log_message.emit("Sin CP suficiente.")
		need_player_action.emit(current)
		return
	_resolve_craft_now(current, skill, target_pos)
	stats_changed.emit()
	await get_tree().create_timer(0.4).timeout
	_advance()

func submit_defend() -> void:
	if current == null or not current.is_player: return
	current.defending = true
	current.gain_cp(15)
	log_message.emit("%s se defiende. +15 CP." % current.display_name)
	stats_changed.emit()
	await get_tree().create_timer(0.3).timeout
	_advance()

func submit_wait() -> void:
	if current == null or not current.is_player: return
	log_message.emit("%s espera." % current.display_name)
	stats_changed.emit()
	await get_tree().create_timer(0.2).timeout
	_advance()

func submit_item(item: ItemData, target: Battler) -> void:
	if current == null or not current.is_player: return
	if item == null: return
	# Verificar que esté en el inventario del actor activo y consumirlo
	var consumed := false
	if current.actor_stats and current.actor_stats.inventory.has(item):
		current.actor_stats.inventory.erase(item)
		consumed = true
	if not consumed:
		log_message.emit("No tienes ese ítem.")
		need_player_action.emit(current)
		return
	_apply_item_effect(current, item, target)
	stats_changed.emit()
	await get_tree().create_timer(0.4).timeout
	_advance()

func _apply_item_effect(user: Battler, item: ItemData, target: Battler) -> void:
	var t: Battler = target if target != null else user
	match item.effect:
		ItemData.Effect.HEAL_HP:
			var amt := t.heal(item.power)
			log_message.emit("%s usa %s. +%d HP a %s." % [user.display_name, item.item_name, amt, t.display_name])
		ItemData.Effect.HEAL_MP:
			var amt := t.restore_mp(item.power)
			log_message.emit("%s usa %s. +%d MP a %s." % [user.display_name, item.item_name, amt, t.display_name])
		ItemData.Effect.REVIVE:
			if t.hp <= 0:
				t.hp = max(1, int(t.max_hp * 0.5))
				t.hp_changed.emit(t.hp)
				log_message.emit("¡%s revive a %s!" % [user.display_name, t.display_name])
		ItemData.Effect.BUFF_ATK:
			t.atk_buff += item.power
			t.buff_turns = max(t.buff_turns, 3)
			log_message.emit("%s ataque +%d." % [t.display_name, item.power])
		ItemData.Effect.BUFF_DEF:
			t.def_buff += item.power
			t.buff_turns = max(t.buff_turns, 3)
			log_message.emit("%s defensa +%d." % [t.display_name, item.power])

func submit_move(pos: Vector2) -> bool:
	if current == null or not current.is_player: return false
	# El click se recorta al círculo en vez de rechazarse: así moverse nunca
	# falla, como en el remake. Lo que no cabe se queda en el borde.
	var goal := field.clamp_reachable(current, pos, float(current.move_range))
	if goal.distance_to(current.field_pos) < 0.05:
		return false
	current.field_pos = goal
	field_changed.emit()
	return true

func submit_run() -> void:
	log_message.emit("Huiste de la batalla.")
	_finish(false)

func auto_play_player(b: Battler) -> void:
	if b == null or not b.is_player: return
	var alive_enemies: Array[Battler] = []
	for e in enemies:
		if e.is_alive():
			alive_enemies.append(e)
	if alive_enemies.is_empty():
		await get_tree().create_timer(0.2).timeout
		_advance()
		return
	var target: Battler = alive_enemies[0]
	var best_d := BattleField.distance(b.field_pos, target.field_pos)
	for e in alive_enemies:
		var d := BattleField.distance(b.field_pos, e.field_pos)
		if d < best_d:
			best_d = d
			target = e
	# Si tiene S-Craft listo, usarlo si está en rango
	var s_craft: SkillData = null
	for s in b.skills:
		if s.kind == SkillData.Kind.CRAFT and s.is_limit_break and b.cp >= s.limit_min_cp:
			s_craft = s; break
	var dist := BattleField.distance(b.field_pos, target.field_pos)
	if dist > b.melee_range:
		_ai_step_towards(b, target.field_pos)
		field_changed.emit()
		await get_tree().create_timer(0.25).timeout
	if s_craft and BattleField.distance(b.field_pos, target.field_pos) <= s_craft.skill_range:
		b.cp = 0
		b.cp_changed.emit(0)
		log_message.emit("[color=#ff66cc][S-CRAFT][/color] ¡%s desata %s!" % [b.display_name, s_craft.skill_name])
		_resolve_craft_now(b, s_craft, target.field_pos)
	elif BattleField.distance(b.field_pos, target.field_pos) <= b.melee_range:
		_do_attack(b, target)
	else:
		log_message.emit("%s avanza." % b.display_name)
	preview_changed.emit()
	stats_changed.emit()
	await get_tree().create_timer(0.4).timeout
	_advance()

# ---------- Resoluciones ----------

func _resolve_cast(b: Battler) -> void:
	var skill: SkillData = b.pending_skill
	var target_pos: Vector2 = b.pending_target_pos
	b.is_casting = false
	b.pending_skill = null
	b.cast_remaining = 0
	if skill == null: return
	_resolve_art_now(b, skill, target_pos)

func _resolve_art_now(caster: Battler, skill: SkillData, target_pos: Vector2) -> void:
	var hits: Array[Battler] = []
	for u in field.units_in_aoe(target_pos, skill.aoe_shape, float(skill.aoe_radius), caster.field_pos):
		if u.is_alive():
			hits.append(u)
	if hits.is_empty():
		log_message.emit("%s usa %s pero falla." % [caster.display_name, skill.skill_name])
		return
	for t in hits:
		_apply_skill_damage(caster, skill, t)
	caster.gain_cp(10)

func _resolve_craft_now(user: Battler, skill: SkillData, target_pos: Vector2) -> void:
	var targets: Array[Battler] = []
	for u in field.units_in_aoe(target_pos, skill.aoe_shape, float(skill.aoe_radius), user.field_pos):
		if u.is_alive():
			targets.append(u)
	if targets.is_empty() and skill.target != SkillData.Target.SELF:
		log_message.emit("%s usa %s pero no impacta." % [user.display_name, skill.skill_name])
		return
	if skill.target == SkillData.Target.SELF:
		targets = [user]
	for t in targets:
		_apply_skill_damage(user, skill, t)
		_apply_craft_effect(user, skill, t)

func _apply_skill_damage(caster: Battler, skill: SkillData, target: Battler) -> void:
	if skill.damage_type == SkillData.DamageType.HEAL:
		var healed := target.heal(skill.power + int(caster.magic * 0.5))
		log_message.emit("%s usa %s. +%d HP a %s" % [caster.display_name, skill.skill_name, healed, target.display_name])
		return
	var elem: int = skill.element
	if target.is_immune_to(elem):
		log_message.emit("%s es inmune a %s." % [target.display_name, SkillData.ELEMENT_NAMES[elem]])
		return
	var mult := 1.0
	var break_amt: int = skill.break_power
	if target.is_weak_to(elem):
		mult = 1.6
		break_amt = int(break_amt * 1.8) + 10
		log_message.emit("[color=#ff9a4a]¡Debilidad %s![/color]" % SkillData.ELEMENT_NAMES[elem])
	elif target.resists(elem):
		mult = 0.5
		break_amt = 0
		log_message.emit("%s resiste %s." % [target.display_name, SkillData.ELEMENT_NAMES[elem]])
	var was_broken := target.broken
	target.gain_break(break_amt)
	if not was_broken and target.broken:
		log_message.emit("[color=#5cc8ff][BREAK][/color] %s queda conmocionado." % target.display_name)
	if target.broken:
		mult *= 1.5
	var raw: int = 0
	match skill.damage_type:
		SkillData.DamageType.PHYSICAL:
			raw = skill.power + caster.effective_attack() - int(target.effective_defense() * 0.5)
		SkillData.DamageType.MAGICAL:
			raw = skill.power + caster.magic
	var limit_mult: float = skill.limit_damage_mult if skill.is_limit_break else 1.0
	var dmg: int = target.take_damage(max(1, int(raw * mult * limit_mult)), skill.is_limit_break, target.is_weak_to(elem))
	log_message.emit("%s usa %s a %s. -%d HP" % [caster.display_name, skill.skill_name, target.display_name, dmg])

func _apply_craft_effect(user: Battler, skill: SkillData, target: Battler) -> void:
	match skill.craft_effect:
		SkillData.CraftEffect.PUSH:
			if skill.push_distance > 0 and target != user:
				var landed := field.push(target, user.field_pos, float(skill.push_distance))
				if landed != target.field_pos:
					pass
				log_message.emit("%s es empujado." % target.display_name)
				field_changed.emit()
		SkillData.CraftEffect.STUN:
			target.stun_remaining = skill.stun_turns
			log_message.emit("%s queda aturdido %d turno(s)." % [target.display_name, skill.stun_turns])
		SkillData.CraftEffect.DRAIN_MP:
			var stolen: int = min(target.mp, skill.power)
			target.mp -= stolen
			target.mp_changed.emit(target.mp)
			user.restore_mp(stolen)
			log_message.emit("%s roba %d MP." % [user.display_name, stolen])
		SkillData.CraftEffect.BUFF_ATK:
			target.atk_buff = skill.buff_amount
			target.buff_turns = max(target.buff_turns, skill.buff_turns)
			log_message.emit("%s ataque +%d" % [target.display_name, skill.buff_amount])
		SkillData.CraftEffect.BUFF_DEF:
			target.def_buff = skill.buff_amount
			target.buff_turns = max(target.buff_turns, skill.buff_turns)
			log_message.emit("%s defensa +%d" % [target.display_name, skill.buff_amount])
		SkillData.CraftEffect.NONE:
			pass

func _do_attack(attacker: Battler, target: Battler) -> void:
	if target.is_immune_to(SkillData.Element.FISICO):
		log_message.emit("%s es inmune al daño físico." % target.display_name)
		return
	var raw: int = attacker.effective_attack() - int(target.effective_defense() * 0.5)
	var dmg: int = max(1, raw)
	var was_crit := current_bonus == TurnQueue.TurnBonus.CRITICAL
	if was_crit:
		dmg = int(dmg * 1.8)
		log_message.emit("¡CRÍTICO!")
	var mult := 1.0
	var break_amt := 8
	var was_weak := target.is_weak_to(SkillData.Element.FISICO)
	if was_weak:
		mult = 1.6
		break_amt = 22
		log_message.emit("[color=#ff9a4a]¡Debilidad Físico![/color]")
	elif target.resists(SkillData.Element.FISICO):
		mult = 0.5
		break_amt = 0
		log_message.emit("%s resiste Físico." % target.display_name)
	var was_broken := target.broken
	target.gain_break(break_amt)
	if not was_broken and target.broken:
		log_message.emit("[color=#5cc8ff][BREAK][/color] %s queda conmocionado." % target.display_name)
	if target.broken:
		mult *= 1.5
	dmg = max(1, int(dmg * mult))
	var applied: int = target.take_damage(dmg, was_crit, was_weak)
	attacker.gain_cp(10)
	log_message.emit("%s ataca a %s. -%d HP" % [attacker.display_name, target.display_name, applied])

# ---------- IA enemiga ----------

func _enemy_ai(b: Battler) -> void:
	var alive_allies: Array[Battler] = []
	for a in allies:
		if a.is_alive():
			alive_allies.append(a)
	if alive_allies.is_empty():
		_finish(false); return
	var target: Battler = alive_allies[0]
	var best_d := BattleField.distance(b.field_pos, target.field_pos)
	for a in alive_allies:
		var d := BattleField.distance(b.field_pos, a.field_pos)
		if d < best_d:
			best_d = d
			target = a

	# Considerar usar habilidad si tiene MP/CP
	var use_skill: SkillData = null
	if b.enemy_data and b.skills.size() > 0 and randf() < b.enemy_data.skill_use_chance:
		for s in b.skills:
			if s.kind == SkillData.Kind.ART and b.mp >= s.mp_cost:
				use_skill = s; break
			if s.kind == SkillData.Kind.CRAFT and b.cp >= s.cp_cost:
				use_skill = s; break

	# Acercarse si está fuera de rango melee
	if use_skill == null:
		var dist := BattleField.distance(b.field_pos, target.field_pos)
		if dist > b.melee_range:
			_ai_step_towards(b, target.field_pos)
			field_changed.emit()
			await get_tree().create_timer(0.3).timeout
		# Re-evaluar tras moverse
		if BattleField.distance(b.field_pos, target.field_pos) <= b.melee_range:
			_do_attack(b, target)
		else:
			log_message.emit("%s avanza." % b.display_name)
	else:
		var dist := BattleField.distance(b.field_pos, target.field_pos)
		if dist > use_skill.skill_range:
			_ai_step_towards(b, target.field_pos)
			field_changed.emit()
			await get_tree().create_timer(0.3).timeout
		if BattleField.distance(b.field_pos, target.field_pos) <= use_skill.skill_range:
			if use_skill.kind == SkillData.Kind.ART:
				b.spend_mp(use_skill.mp_cost)
				var cast_time := use_skill.cast_time
				if current_bonus == TurnQueue.TurnBonus.ZERO_ARTS:
					cast_time = 0
				if cast_time <= 0:
					_resolve_art_now(b, use_skill, target.field_pos)
				else:
					b.is_casting = true
					b.pending_skill = use_skill
					b.pending_target_pos = target.field_pos
					b.cast_remaining = cast_time
					log_message.emit("%s canaliza %s..." % [b.display_name, use_skill.skill_name])
					queue.insert_cast_resolution(b, float(cast_time))
			else:
				b.spend_cp(use_skill.cp_cost)
				_resolve_craft_now(b, use_skill, target.field_pos)
		else:
			_do_attack(b, target)
	preview_changed.emit()
	stats_changed.emit()
	await get_tree().create_timer(0.5).timeout
	_advance()

func _ai_step_towards(b: Battler, goal: Vector2) -> void:
	# Se para justo dentro de su alcance, no encima del objetivo.
	var parada: float = maxf(float(b.melee_range) * 0.9, BattleField.BODY * 2.0)
	var destino := field.step_towards(b, goal, float(b.move_range), parada)
	if destino.distance_to(b.field_pos) > 0.01:
		b.field_pos = destino

# ---------- Helpers ----------

func _all_dead(group: Array[Battler]) -> bool:
	for b in group:
		if b.is_alive():
			return false
	return true

func _finish(victory: bool) -> void:
	if finished:
		return
	finished = true
	# Persistir HP/MP de los aliados al ActorStats para que se mantenga entre batallas
	for ally in allies:
		if ally.actor_stats:
			ally.actor_stats.current_hp = max(1, ally.hp) if not victory else ally.hp
			ally.actor_stats.current_mp = ally.mp
	if victory:
		var total_exp := 0
		var total_gold := 0
		for e in enemies:
			if e.enemy_data:
				total_exp += e.enemy_data.exp_reward
				total_gold += e.enemy_data.gold_reward
		log_message.emit("¡Victoria! +%d EXP, +%d oro" % [total_exp, total_gold])
		GameState.add_exp_and_gold(total_exp, total_gold)
		var survivors := 0
		for ally in allies:
			if ally.is_alive():
				survivors += 1
		if survivors >= 2:
			GameState.gain_party_affinity(3)
			log_message.emit("Los lazos del grupo se fortalecen. +3 afinidad")
		# Escuchar level ups y mostrar en log
		var conn := GameState.level_up.connect(func(actor_name: String, new_level: int):
			log_message.emit("[color=#ffd84a]¡%s subió a nivel %d![/color]" % [actor_name, new_level])
		, CONNECT_ONE_SHOT)
	else:
		log_message.emit("Tu grupo cayó...")
	battle_ended.emit(victory)
