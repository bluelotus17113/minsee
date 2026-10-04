class_name BattleGrid
extends RefCounted

const WIDTH := 10
const HEIGHT := 6

var occupants: Dictionary = {}  # Vector2i -> Battler

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT

func is_free(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	return not occupants.has(cell)

func get_at(cell: Vector2i):
	return occupants.get(cell, null)

func place(battler, cell: Vector2i) -> void:
	if battler.grid_pos != Vector2i(-999, -999):
		occupants.erase(battler.grid_pos)
	occupants[cell] = battler
	battler.grid_pos = cell

func move_to(battler, cell: Vector2i) -> bool:
	if not is_free(cell):
		return false
	occupants.erase(battler.grid_pos)
	occupants[cell] = battler
	battler.grid_pos = cell
	return true

func remove(battler) -> void:
	if occupants.get(battler.grid_pos) == battler:
		occupants.erase(battler.grid_pos)

func manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

func bfs_reachable(start: Vector2i, max_steps: int) -> Array:
	var result: Array = []
	var visited := {start: 0}
	var frontier: Array = [start]
	while frontier.size() > 0:
		var current: Vector2i = frontier.pop_front()
		var dist: int = visited[current]
		if dist > 0:
			result.append(current)
		if dist >= max_steps:
			continue
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb: Vector2i = current + dir
			if not in_bounds(nb): continue
			if visited.has(nb): continue
			if not is_free(nb) and nb != start: continue
			visited[nb] = dist + 1
			frontier.append(nb)
	return result

func cells_in_aoe(center: Vector2i, shape: int, radius: int) -> Array:
	var out: Array = []
	match shape:
		SkillData.AoEShape.SINGLE:
			out.append(center)
		SkillData.AoEShape.CROSS:
			out.append(center)
			for r in range(1, radius + 1):
				out.append(center + Vector2i(r, 0))
				out.append(center + Vector2i(-r, 0))
				out.append(center + Vector2i(0, r))
				out.append(center + Vector2i(0, -r))
		SkillData.AoEShape.SQUARE:
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					out.append(center + Vector2i(dx, dy))
		SkillData.AoEShape.LINE:
			for r in range(0, radius + 1):
				out.append(center + Vector2i(r, 0))
	var filtered: Array = []
	for c in out:
		if in_bounds(c):
			filtered.append(c)
	return filtered

func direction_from(a: Vector2i, b: Vector2i) -> Vector2i:
	var d := b - a
	if abs(d.x) >= abs(d.y):
		return Vector2i(sign(d.x), 0)
	return Vector2i(0, sign(d.y))

func push(battler, from: Vector2i, distance: int) -> Vector2i:
	var dir := direction_from(from, battler.grid_pos)
	if dir == Vector2i.ZERO:
		dir = Vector2i(1, 0) if battler.is_player else Vector2i(-1, 0)
	var current: Vector2i = battler.grid_pos
	for _i in distance:
		var next: Vector2i = current + dir
		if not is_free(next):
			break
		current = next
	if current != battler.grid_pos:
		move_to(battler, current)
	return current
