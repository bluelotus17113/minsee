extends Node

## Captura PNG sin abrir el editor, para juzgar el estilo mirándolo.
##
##   godot --path . scenes/debug/capture.tscn -- scene <res://escena.tscn> <salida.png> [frames] [walk]
##   godot --path . scenes/debug/capture.tscn -- chars <salida.png> [id,id,...]
##
## El modo "chars" se monta su propio escenario: no depende de que ningún
## mapa esté bien iluminado para ver si un personaje está bien.

const CHARS_DIR := "res://scenes/world/3d/chars/"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "chars"
	match mode:
		"battle":
			await _shoot_battle(args)
		"scene":
			await _shoot_scene(args)
		_:
			await _shoot_chars(args)
	get_tree().quit()

## Monta un combate de prueba: sin grupo ni enemigos la escena se arranca con
## un slime por defecto y no se ve nada de lo que importa.
func _shoot_battle(args: PackedStringArray) -> void:
	var out: String = args[1] if args.size() > 1 else "user://battle.png"
	var ids := PackedStringArray(["goblin", "skeleton", "goblin_boss"])
	if args.size() > 2:
		ids = args[2].split(",")
	var frames: int = int(args[3]) if args.size() > 3 else 60

	GameState.party.clear()
	GameState.reserve.clear()
	GameState.gold = 100
	GameState._init_default_party()

	var lista: Array[EnemyData] = []
	for id in ids:
		var data := load("res://data/enemies/%s.tres" % id) as EnemyData
		if data == null:
			push_error("No existe data/enemies/%s.tres" % id)
			continue
		lista.append(data)
	GameState.pending_battle_enemies = lista

	var packed: PackedScene = load("res://scenes/battle/battle_3d.tscn")
	if packed == null:
		push_error("No se pudo cargar battle_3d.tscn")
		return
	var escena := packed.instantiate()
	add_child(escena)
	await _wait(frames)
	# Con "mover" se pulsa el botón para ver el círculo de movimiento.
	if args.size() > 4 and args[4] == "mover":
		escena.call("_on_move_pressed")
		await _wait(20)
	elif args.size() > 4 and args[4] == "andar":
		# Se ordena un movimiento y se fotografía a mitad de camino, que es lo
		# único que demuestra que camina en vez de teletransportarse.
		var mgr = escena.get_node("BattleManager")
		var destino: Vector2 = mgr.current.field_pos + Vector2(2.2, 1.4)
		mgr.submit_move(destino)
		await _wait(14)
		print("[andar] caminando=%s  pos=%s" % [escena.call("is_walking"), mgr.current.field_pos])
	await _save(out)

func _shoot_scene(args: PackedStringArray) -> void:
	var target: String = args[1] if args.size() > 1 else "res://scenes/world/3d/patio_pueblo_3d.tscn"
	var out: String = args[2] if args.size() > 2 else "user://scene.png"
	var frames: int = int(args[3]) if args.size() > 3 else 40
	var walk: bool = args.size() > 4 and args[4] == "walk"
	var packed: PackedScene = load(target)
	if packed == null:
		push_error("No se pudo cargar %s" % target)
		return
	add_child(packed.instantiate())
	# La cámara del mundo captura el puntero, y al capturar sin nadie delante
	# el sistema genera movimiento de ratón: la cámara giraba sola y la foto
	# no representaba el juego. Se le quita el control de la mirada.
	await get_tree().process_frame
	for rig in _find_rigs(self):
		rig.set_look_enabled(false)
	if walk:
		Input.action_press("move_right")
	await _wait(frames)
	await _save(out)
	if walk:
		Input.action_release("move_right")
	# Dónde acabó cada cosa: para saber si la cámara sigue al jugador o no.
	var cam := get_viewport().get_camera_3d()
	var jugador := get_tree().get_first_node_in_group("player") as Node3D
	if cam and jugador:
		print("[diag] cámara=%s  jugador=%s  distancia=%.2f" % [
			cam.global_position, jugador.global_position,
			cam.global_position.distance_to(jugador.global_position)])
		var skel := jugador.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel == null:
			print("[diag] el jugador NO tiene Skeleton3D")
		else:
			var hueso := skel.find_bone("foot.L")
			var pie: Vector3 = skel.global_transform * skel.get_bone_global_pose(hueso).origin
			print("[diag] pie_mundo_y=%+.3f  jugador_y=%+.3f  skel_y=%+.3f" % [
				pie.y, jugador.global_position.y, skel.global_position.y])
		print("[diag] brazo=%.2f  camara_local=%s" % [
			(cam.get_parent() as SpringArm3D).get_hit_length() if cam.get_parent() is SpringArm3D else -1.0,
			cam.position])

func _shoot_chars(args: PackedStringArray) -> void:
	var out: String = args[1] if args.size() > 1 else "user://chars.png"
	var ids := PackedStringArray(["min", "lia", "aldeano", "mercader", "posadero"])
	if args.size() > 2:
		ids = args[2].split(",")

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.17, 0.19, 0.26)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.85)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 205, 0)
	sun.light_energy = 3.0
	sun.light_color = Color(1.0, 0.96, 0.9)
	add_child(sun)

	var suelo := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(20, 20)
	suelo.mesh = plano
	var mat_suelo := StandardMaterial3D.new()
	mat_suelo.albedo_color = Color(0.34, 0.36, 0.44)
	suelo.material_override = mat_suelo
	add_child(suelo)

	var spacing := 0.85
	var total := (ids.size() - 1) * spacing
	for i in ids.size():
		var path := CHARS_DIR + ids[i] + ".glb"
		var packed: PackedScene = load(path)
		if packed == null:
			push_error("Falta %s" % path)
			continue
		var inst := packed.instantiate()
		var holder := Node3D.new()
		holder.position = Vector3(-total * 0.5 + i * spacing, 0, 0)
		# Un poco girado: de frente no se ve el volumen ni el contorno lateral.
		holder.rotation_degrees = Vector3(0, 22, 0)
		holder.add_child(inst)
		add_child(holder)
		ToonSkin.skin(inst)
		# Dónde cae el pie DE VERDAD. Mirar el campo del glTF no sirve: en una
		# malla con esqueleto quien coloca los vértices es el hueso.
		var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel == null:
			print("[pie] %-12s SIN Skeleton3D" % ids[i])
		else:
			var nombres := []
			for n in skel.get_bone_count():
				nombres.append(skel.get_bone_name(n))
			var hueso := skel.find_bone("foot.L")
			if hueso < 0:
				print("[pie] %-12s sin hueso foot.L. huesos=%s" % [ids[i], nombres.slice(0, 6)])
			else:
				var mundo: Vector3 = skel.global_transform * skel.get_bone_global_pose(hueso).origin
				var malla := inst.find_child("Body", true, false)
				print("[pie] %-12s y=%+.3f  skel_y=%+.3f  malla_y=%+.3f" % [
					ids[i], mundo.y, skel.global_position.y,
					(malla as Node3D).global_position.y if malla is Node3D else -99.0])
		var ap := _find_anim(inst)
		if ap:
			for n in ap.get_animation_list():
				var a := ap.get_animation(n)
				if a:
					a.loop_mode = Animation.LOOP_LINEAR
			if ap.has_animation("idle"):
				ap.play("idle")

	# El personaje mira a -Z, que es el "adelante" de Godot. Una cámara en +Z
	# le saca la nuca: hay que ponerla delante y darle la vuelta.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = max(1.7, 0.62 * ids.size() + 0.9)
	cam.position = Vector3(0, 0.72, -4.0)
	cam.rotation_degrees = Vector3(0, 180, 0)
	add_child(cam)
	cam.make_current()

	await _wait(30)
	await _save(out)

func _find_rigs(root: Node) -> Array:
	var out: Array = []
	if root is ThirdPersonCamera:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_rigs(c))
	return out

func _find_anim(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var f := _find_anim(c)
		if f:
			return f
	return null

func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame

func _save(out: String) -> void:
	# Sin esperar al post-draw la textura del viewport puede venir del frame
	# anterior, o vacía.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	if err != OK:
		push_error("No se pudo guardar %s (error %d)" % [out, err])
	else:
		print("[capture] %s  %dx%d" % [out, img.get_width(), img.get_height()])
