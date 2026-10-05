class_name ThirdPersonCamera
extends Node3D

## Cámara en tercera persona.
##
## Vive DENTRO de la escena del jugador, no en el mapa: el brazo necesita
## lanzar su rayo desde el cuerpo del personaje para apartarse de las paredes,
## y eso no se puede hacer desde la raíz del mapa.
##
## Reparto de giros: este nodo lleva el guiñado (yaw), el SpringArm3D lleva el
## cabeceo (pitch). El cuerpo del jugador no gira nunca; quien gira es el
## modelo, hacia donde anda.

@export_group("Encuadre")
@export_range(1.5, 12.0) var distance: float = 3.8:
	set(v):
		distance = v
		if is_node_ready():
			arm.spring_length = distance
@export_range(-80.0, 20.0) var min_pitch: float = -30.0
@export_range(0.0, 85.0) var max_pitch: float = 62.0
@export_range(0.0, 30.0) var follow_lag: float = 14.0
## Orientación de partida. En el mundo da igual (el rig gira con el jugador),
## pero en combate hace falta mirar desde el bando aliado hacia el enemigo y
## con bastante más ángulo, o no se ve el campo.
@export_range(-180.0, 180.0) var start_yaw_degrees: float = 0.0
@export_range(0.0, 85.0) var start_pitch_degrees: float = 21.0

@export_group("Control")
## Cómo se gira la cámara.
##   CAPTURAR  - el puntero se esconde y el ratón gira siempre (mundo abierto).
##   ARRASTRAR - el puntero se ve y solo gira con el botón derecho pulsado.
## En combate hace falta ARRASTRAR: el click izquierdo señala en el campo, así
## que el ratón no puede estar capturado girando la cámara.
enum Orbit { CAPTURAR, ARRASTRAR }
@export var orbit_mode: Orbit = Orbit.CAPTURAR
@export_range(0.01, 1.0) var mouse_sensitivity: float = 0.16
@export_range(10.0, 400.0) var stick_speed: float = 160.0
@export_range(1.0, 10.0) var min_distance: float = 2.0
@export_range(2.0, 20.0) var max_distance: float = 8.0
@export var zoom_step: float = 0.5

@onready var arm: SpringArm3D = $SpringArm3D
@onready var cam: Camera3D = $SpringArm3D/Camera3D

var _yaw: float = 0.0
var _pitch: float = 21.0
var _captured: bool = false
var _look_enabled: bool = true
var _dragging: bool = false

func _ready() -> void:
	arm.spring_length = distance
	# El brazo solo debe apartarse por el escenario (capa 1), no por el propio
	# jugador ni por las áreas de interacción.
	arm.collision_mask = 1
	arm.margin = 0.25
	_yaw = deg_to_rad(start_yaw_degrees)
	_pitch = clampf(start_pitch_degrees, min_pitch, max_pitch)
	_apply()
	if not Engine.is_editor_hint() and orbit_mode == Orbit.CAPTURAR:
		_set_captured(true)

func _exit_tree() -> void:
	if _captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _set_captured(on: bool) -> void:
	if _captured == on:
		return
	_captured = on
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)

## El jugador avisa al abrir o cerrar el menú de pausa.
func set_look_enabled(on: bool) -> void:
	_look_enabled = on
	if not on:
		_set_captured(false)

## Mientras hay diálogo o menú se suelta el ratón: si no, no se puede pulsar
## nada y la cámara se va girando sola con cada movimiento.
func _busy() -> bool:
	return not _look_enabled or DialogueManager.is_active()

func _unhandled_input(event: InputEvent) -> void:
	if _busy():
		return
	if event is InputEventMouseMotion:
		var activo: bool = _captured if orbit_mode == Orbit.CAPTURAR else _dragging
		if activo:
			var mm := event as InputEventMouseMotion
			_yaw -= mm.relative.x * mouse_sensitivity * 0.01
			_pitch += mm.relative.y * mouse_sensitivity * 0.01 * 57.2958
			_clamp_pitch()
			_apply()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-zoom_step)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(zoom_step)
		elif orbit_mode == Orbit.ARRASTRAR and mb.button_index == MOUSE_BUTTON_RIGHT:
			# Solo gira mientras se mantiene el derecho: el izquierdo queda
			# libre para señalar en el campo.
			_dragging = mb.pressed
		elif orbit_mode == Orbit.CAPTURAR and mb.pressed and not _captured:
			_set_captured(true)

func _zoom(delta: float) -> void:
	distance = clampf(distance + delta, min_distance, max_distance)

func _process(delta: float) -> void:
	var busy := _busy()
	if orbit_mode == Orbit.CAPTURAR:
		_set_captured(not busy)
	if busy:
		_dragging = false
		return
	# Mando: los mismos botones que giraban la isométrica, ahora continuos.
	var turn := Input.get_action_strength("camera_rotate_right") - Input.get_action_strength("camera_rotate_left")
	if absf(turn) > 0.01:
		_yaw -= turn * deg_to_rad(stick_speed) * delta
		_apply()

func _clamp_pitch() -> void:
	_pitch = clampf(_pitch, min_pitch, max_pitch)

func _apply() -> void:
	rotation.y = _yaw
	# El brazo apunta hacia atrás por +Z, así que el cabeceo va en negativo
	# para que la cámara suba por encima del personaje.
	arm.rotation.x = -deg_to_rad(_pitch)

## Dirección "adelante" plana de la cámara. La usa el jugador para moverse.
func forward_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)
