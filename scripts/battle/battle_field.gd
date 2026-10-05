class_name BattleField
extends RefCounted

## Campo de batalla continuo, al estilo del remake de Trails in the Sky.
##
## Sustituye a BattleGrid: no hay casillas. Cada combatiente está en un punto
## (metros) y ocupa un disco de radio BODY. Las distancias son euclídeas y el
## alcance de movimiento es un círculo, no un BFS.
##
## La escala se mantiene: 1 casilla de la rejilla vieja = 1 metro. Así los
## valores que ya están en los .tres (move_range, skill_range, aoe_radius)
## siguen valiendo sin tocar nada del contenido.

## Semiejes de la arena. Es una elipse, más ancha que profunda, para que los
## dos bandos se vean enfrentados.
const RADIUS_X := 5.2
const RADIUS_Z := 3.6
## Radio del cuerpo de un combatiente. Dos no pueden acercarse más del doble.
const BODY := 0.45
## Margen al elegir a quién señala el ratón: pedir precisión de píxel molesta.
const PICK := BODY * 1.25

var units: Array[Battler] = []

# ---------- Consultas ----------

func in_bounds(p: Vector2) -> bool:
	# El cuerpo entero tiene que caber: por eso se encoge la elipse en BODY.
	var ax: float = maxf(0.001, RADIUS_X - BODY)
	var az: float = maxf(0.001, RADIUS_Z - BODY)
	return (p.x * p.x) / (ax * ax) + (p.y * p.y) / (az * az) <= 1.0

func is_free(p: Vector2, ignore: Battler = null) -> bool:
	if not in_bounds(p):
		return false
	for u in units:
		if u == ignore or not u.is_alive():
			continue
		if p.distance_to(u.field_pos) < BODY * 2.0:
			return false
	return true

## Quién está bajo un punto. Devuelve el más cercano dentro del margen de
## selección, no el primero que encuentre.
func get_at(p: Vector2) -> Battler:
	var best: Battler = null
	var best_d := PICK
	for u in units:
		if not u.is_alive():
			continue
		var d: float = p.distance_to(u.field_pos)
		if d <= PICK and d < best_d:
			best_d = d
			best = u
	return best

static func distance(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)

# ---------- Colocación ----------

func place(b: Battler, p: Vector2) -> void:
	if not units.has(b):
		units.append(b)
	b.field_pos = free_spot_near(p, b)

func move_to(b: Battler, p: Vector2) -> bool:
	if not is_free(p, b):
		return false
	b.field_pos = p
	return true

func remove(b: Battler) -> void:
	units.erase(b)

## Punto libre más cercano a `p`, buscando en espiral. Sirve para colocar al
## inicio y para no dejar a nadie encima de otro tras un empujón.
func free_spot_near(p: Vector2, ignore: Battler = null) -> Vector2:
	if is_free(p, ignore):
		return p
	var step := BODY * 0.8
	for anillo in range(1, 14):
		var radio: float = step * float(anillo)
		var n: int = 6 * anillo
		for i in n:
			var ang: float = TAU * float(i) / float(n)
			var cand := p + Vector2(cos(ang), sin(ang)) * radio
			if is_free(cand, ignore):
				return cand
	return p

## El punto alcanzable más cercano a `wanted` sin pasarse del radio ni salirse.
## Es lo que convierte un click en cualquier sitio en un movimiento legal.
func clamp_reachable(b: Battler, wanted: Vector2, radius: float) -> Vector2:
	var delta := wanted - b.field_pos
	if delta.length() > radius:
		delta = delta.normalized() * radius
	var goal := b.field_pos + delta
	if not in_bounds(goal):
		# Acercarlo al centro hasta que entre.
		for i in range(1, 25):
			var t: float = 1.0 - float(i) / 25.0
			var cand := b.field_pos + delta * t
			if in_bounds(cand):
				goal = cand
				break
	return free_spot_near(goal, b)

## Avanza hacia `goal` todo lo que permita `radius`, parando a `stop_at` del
## objetivo para no quedar encima.
func step_towards(b: Battler, goal: Vector2, radius: float, stop_at: float) -> Vector2:
	var delta := goal - b.field_pos
	var d := delta.length()
	if d <= 0.001:
		return b.field_pos
	var avance: float = minf(radius, maxf(0.0, d - stop_at))
	if avance <= 0.01:
		return b.field_pos
	return clamp_reachable(b, b.field_pos + delta.normalized() * avance, radius)

## Hasta dónde se puede llegar en una dirección: el menor entre el radio y el
## borde de la arena. Es lo que permite dibujar el área alcanzable de verdad
## en vez de un círculo que se sale del campo.
func reach_in_direction(center: Vector2, dir: Vector2, radius: float) -> float:
	var ax: float = maxf(0.001, RADIUS_X - BODY)
	var az: float = maxf(0.001, RADIUS_Z - BODY)
	var d := dir.normalized()
	var A: float = (d.x * d.x) / (ax * ax) + (d.y * d.y) / (az * az)
	if A <= 0.0:
		return radius
	var B: float = 2.0 * (center.x * d.x / (ax * ax) + center.y * d.y / (az * az))
	var C: float = (center.x * center.x) / (ax * ax) + (center.y * center.y) / (az * az) - 1.0
	var disc: float = B * B - 4.0 * A * C
	if disc <= 0.0:
		return 0.0
	var t: float = (-B + sqrt(disc)) / (2.0 * A)
	return clampf(t, 0.0, radius)


# ---------- Áreas de efecto ----------

## A quién alcanza una habilidad. Las formas de la rejilla vieja se traducen:
## SINGLE sigue siendo un solo objetivo, CROSS y SQUARE pasan a ser un círculo
## y LINE una franja desde quien lanza hasta el punto.
func units_in_aoe(center: Vector2, shape: int, radius: float, caster_pos: Vector2) -> Array[Battler]:
	var out: Array[Battler] = []
	match shape:
		SkillData.AoEShape.SINGLE:
			var one: Battler = get_at(center)
			if one != null and one.is_alive():
				out.append(one)
		SkillData.AoEShape.LINE:
			var dir := center - caster_pos
			if dir.length() < 0.001:
				dir = Vector2(1, 0)
			dir = dir.normalized()
			var largo: float = maxf(radius, 1.0)
			var ancho := BODY * 1.6
			for u in units:
				if not u.is_alive():
					continue
				var rel := u.field_pos - caster_pos
				var a: float = rel.dot(dir)
				if a < 0.0 or a > largo:
					continue
				if absf(rel.cross(dir)) <= ancho:
					out.append(u)
		_:
			# CROSS y SQUARE: círculo.
			var r: float = maxf(radius, BODY)
			for u in units:
				if u.is_alive() and u.field_pos.distance_to(center) <= r + BODY:
					out.append(u)
	return out

# ---------- Empujón ----------

func push(b: Battler, from: Vector2, dist: float) -> Vector2:
	var dir := b.field_pos - from
	if dir.length() < 0.001:
		dir = Vector2(1, 0) if b.is_player else Vector2(-1, 0)
	dir = dir.normalized()
	var paso := BODY * 0.5
	var actual := b.field_pos
	var recorrido := 0.0
	while recorrido < dist:
		var siguiente := actual + dir * paso
		if not is_free(siguiente, b):
			break
		actual = siguiente
		recorrido += paso
	if actual != b.field_pos:
		move_to(b, actual)
	return actual

# ---------- Colocación inicial ----------

## Los dos bandos enfrentados por el eje largo: aliados a la izquierda,
## enemigos a la derecha, repartidos en abanico.
static func spawn_pos(index: int, total: int, is_player: bool) -> Vector2:
	var x: float = -3.2 if is_player else 3.2
	var span: float = 2.1
	var z := 0.0
	if total > 1:
		z = -span + 2.0 * span * (float(index) / float(total - 1))
	# Ligera curva: los de los extremos algo retrasados, como en un abanico.
	x += (0.5 if is_player else -0.5) * (absf(z) / maxf(span, 0.001)) * -0.6
	return Vector2(x, z)
