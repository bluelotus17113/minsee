extends CharacterBody3D

const SPEED := 3.5
const PAUSE_MENU := "res://scenes/menu/pause_menu.tscn"
## Velocidad de giro del modelo hacia la dirección de avance.
const TURN_SPEED := 12.0

@export var camera_path: NodePath

@onready var model: Node3D = $Model
@onready var rig: ThirdPersonCamera = get_node_or_null("CamRig") as ThirdPersonCamera

var _anim: AnimationPlayer
var _menu_open: bool = false

func _ready() -> void:
	_anim = _find_anim(model)
	# Las animaciones de un .glb entran sin bucle salvo que el nombre acabe en
	# "-loop". Sin esto idle y walk suenan una vez y el personaje se congela.
	if _anim:
		for name in _anim.get_animation_list():
			var a := _anim.get_animation(name)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
	_play("idle")

func _find_anim(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_anim(child)
		if found:
			return found
	return null

func _play(anim: String) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	if _anim.current_animation == anim:
		return
	_anim.play(anim)

func _physics_process(delta: float) -> void:
	if DialogueManager.is_active() or _menu_open:
		velocity = Vector3.ZERO
		_play("idle")
		return
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 1.0:
		input = input.normalized()
	var rx := 0.0
	var rz := 0.0
	if rig:
		# Solo el guiñado: la base de la cámara lleva también el cabeceo, y
		# mirando al suelo el "adelante" plano degenera.
		var b := rig.forward_basis()
		# input.y es "abajo" (move_down - move_up), así que adelante lleva el
		# signo cambiado: con W el personaje se aleja de la cámara.
		var move_vec := (-b.z) * (-input.y) + b.x * input.x
		rx = move_vec.x
		rz = move_vec.z
	elif _get_camera():
		var cam := _get_camera()
		var forward := -cam.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var move_vec := right * input.x + forward * (-input.y)
		rx = move_vec.x
		rz = move_vec.z
	else:
		var rot := PI / 4.0
		rx = input.x * cos(rot) - input.y * sin(rot)
		rz = input.x * sin(rot) + input.y * cos(rot)
	velocity.x = rx * SPEED
	velocity.z = rz * SPEED
	velocity.y = 0
	move_and_slide()

	# El modelo gira hacia donde anda. Antes esto era un flip_h del sprite:
	# con malla 3D hay que rotar, y el "adelante" de un Node3D es -Z, de ahí
	# el atan2(-x, -z).
	if Vector2(rx, rz).length() > 0.05:
		var target := atan2(-rx, -rz)
		model.rotation.y = lerp_angle(model.rotation.y, target, 1.0 - exp(-TURN_SPEED * delta))
		_play("walk")
	else:
		_play("idle")

func _get_camera() -> Camera3D:
	if camera_path != NodePath():
		var n := get_node_or_null(camera_path) as Camera3D
		if n: return n
	return get_viewport().get_camera_3d()

func _unhandled_input(event: InputEvent) -> void:
	if _menu_open or DialogueManager.is_active(): return
	if event.is_action_pressed("open_menu"):
		_open_menu()
		get_viewport().set_input_as_handled()

func _open_menu() -> void:
	var packed: PackedScene = load(PAUSE_MENU)
	if packed == null: return
	var ui := packed.instantiate()
	get_tree().current_scene.add_child(ui)
	_menu_open = true
	# Soltar el ratón antes de abrir: con el puntero capturado no se puede
	# pulsar nada del menú y la cámara gira sola con cada movimiento.
	if rig:
		rig.set_look_enabled(false)
	ui.closed.connect(func():
		_menu_open = false
		if rig:
			rig.set_look_enabled(true))
