@tool
extends Node3D

# Cámara isométrica estilo Trails con rotación interactiva (Q/E) y zoom (rueda).
# Se asigna como script del Node3D raíz de cualquier escena 3D.

@export var camera_path: NodePath = NodePath("Camera3D")
@export var follow_path: NodePath = NodePath("Player")
@export var target_offset: Vector3 = Vector3(0, 0.5, 0)
@export var distance: float = 11.0
@export_range(20.0, 80.0) var pitch_degrees: float = 35.0
@export_range(0.0, 360.0) var yaw_degrees: float = 225.0
@export_range(2.0, 30.0) var ortho_size: float = 7.5

@export_group("Interacción")
@export var enable_rotation: bool = true
@export_range(0.0, 1.0) var rotation_step_seconds: float = 0.28
@export var rotation_snap_degrees: float = 90.0
@export var enable_zoom: bool = true
@export var zoom_step: float = 1.2
@export var min_ortho_size: float = 3.0
@export var max_ortho_size: float = 16.0
@export_range(0.0, 1.0) var follow_smoothing: float = 0.18

var _yaw_tween: Tween
var _zoom_tween: Tween
var _target_world: Vector3

func _ready() -> void:
	var cam := _camera()
	if cam == null:
		return
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.1
	cam.far = 60.0
	cam.size = ortho_size
	_target_world = _compute_target()
	_apply_position_only()

func _compute_target() -> Vector3:
	if not Engine.is_editor_hint():
		var fn := get_node_or_null(follow_path)
		if fn and fn is Node3D:
			return (fn as Node3D).global_position + target_offset
	return target_offset

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var goal := _compute_target()
	var t: float = 1.0 - pow(follow_smoothing, max(0.001, delta * 60.0))
	_target_world = _target_world.lerp(goal, clamp(t, 0.0, 1.0))
	_apply_position_only()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if enable_rotation:
		if event.is_action_pressed("camera_rotate_left"):
			_rotate_yaw(-rotation_snap_degrees)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("camera_rotate_right"):
			_rotate_yaw(rotation_snap_degrees)
			get_viewport().set_input_as_handled()
	if enable_zoom and event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-zoom_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(zoom_step)

func _rotate_yaw(delta_deg: float) -> void:
	var target_yaw: float = yaw_degrees + delta_deg
	if _yaw_tween and _yaw_tween.is_valid():
		_yaw_tween.kill()
	_yaw_tween = create_tween()
	_yaw_tween.tween_method(_set_yaw, yaw_degrees, target_yaw, rotation_step_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _set_yaw(value: float) -> void:
	yaw_degrees = value
	_apply_position_only()

func _zoom(delta: float) -> void:
	var target_size: float = clamp(ortho_size + delta, min_ortho_size, max_ortho_size)
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_method(_set_zoom, ortho_size, target_size, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _set_zoom(value: float) -> void:
	ortho_size = value
	var cam := _camera()
	if cam:
		cam.size = ortho_size

func _camera() -> Camera3D:
	return get_node_or_null(camera_path) as Camera3D

func _apply_position_only() -> void:
	var cam := _camera()
	if cam == null:
		return
	var pitch := deg_to_rad(pitch_degrees)
	var yaw := deg_to_rad(yaw_degrees)
	var offset := Vector3(
		distance * cos(pitch) * sin(yaw),
		distance * sin(pitch),
		distance * cos(pitch) * cos(yaw)
	)
	cam.global_position = _target_world + offset
	cam.look_at(_target_world, Vector3.UP)
