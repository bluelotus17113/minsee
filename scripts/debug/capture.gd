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
		"scene":
			await _shoot_scene(args)
		_:
			await _shoot_chars(args)
	get_tree().quit()

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
	if walk:
		Input.action_press("move_right")
	await _wait(frames)
	await _save(out)
	if walk:
		Input.action_release("move_right")

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
