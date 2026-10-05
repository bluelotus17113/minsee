@tool
class_name ToonSkin
extends Node3D

## Cambia los materiales de un .glb importado por el shader toon, conservando
## el color base de cada superficie.
##
## Blender exporta StandardMaterial3D y el toon no se puede hornear ahí: vive
## en Godot. Este nodo lee el albedo de cada superficie y le pone un
## ShaderMaterial equivalente, con el contorno como next_pass.
##
## Se usa de dos formas: como padre del modelo en una escena, o llamando a
## ToonSkin.skin(nodo) desde código cuando el modelo se instancia en caliente.

const TOON_SHADER: Shader = preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/toon_outline.gdshader")

@export_group("Sombreado")
@export_range(2, 5) var bands: int = 2:
	set(v):
		bands = v
		_refresh()
@export_range(0.0, 0.5) var band_softness: float = 0.012:
	set(v):
		band_softness = v
		_refresh()
## La sombra teñida de frío es lo que más vende el estilo anime. En negro
## parece plástico.
@export var shadow_tint: Color = Color(0.46, 0.5, 0.72):
	set(v):
		shadow_tint = v
		_refresh()

@export_group("Borde")
@export var rim_color: Color = Color(1.0, 0.97, 0.9):
	set(v):
		rim_color = v
		_refresh()
@export_range(0.0, 2.0) var rim_strength: float = 0.5:
	set(v):
		rim_strength = v
		_refresh()
@export_range(0.0, 1.0) var rim_width: float = 0.3:
	set(v):
		rim_width = v
		_refresh()

@export_group("Contorno")
@export var outline_color: Color = Color(0.08, 0.06, 0.12):
	set(v):
		outline_color = v
		_refresh()
@export_range(0.0, 0.02) var outline_width: float = 0.011:
	set(v):
		outline_width = v
		_refresh()

# Compartido por todo el proceso: cinco NPCs con la misma ropa reutilizan
# material en vez de compilar uno por instancia.
static var _cache: Dictionary = {}

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	apply_to(self)

## Recorre el subárbol y toonifica cada superficie. Devuelve cuántas tocó.
func apply_to(root: Node) -> int:
	var cfg := _config()
	var touched := 0
	for mi in _meshes(root):
		touched += _skin_instance(mi, cfg)
	return touched

## Versión estática con los valores por defecto, para modelos instanciados
## desde código.
static func skin(root: Node, width: float = 0.011) -> int:
	var cfg := {
		"bands": 2,
		"band_softness": 0.012,
		"shadow_tint": Color(0.46, 0.5, 0.72),
		"rim_color": Color(1.0, 0.97, 0.9),
		"rim_strength": 0.5,
		"rim_width": 0.3,
		"outline_color": Color(0.08, 0.06, 0.12),
		"outline_width": width,
	}
	var touched := 0
	for mi in _meshes_static(root):
		touched += _skin_static(mi, cfg)
	return touched

func _config() -> Dictionary:
	return {
		"bands": bands,
		"band_softness": band_softness,
		"shadow_tint": shadow_tint,
		"rim_color": rim_color,
		"rim_strength": rim_strength,
		"rim_width": rim_width,
		"outline_color": outline_color,
		"outline_width": outline_width,
	}

func _skin_instance(mi: MeshInstance3D, cfg: Dictionary) -> int:
	return _skin_static(mi, cfg)

static func _skin_static(mi: MeshInstance3D, cfg: Dictionary) -> int:
	if mi.mesh == null:
		return 0
	var count := mi.mesh.get_surface_count()
	for i in count:
		var src := _surface_source(mi, i)
		mi.set_surface_override_material(i, _material_for(src, cfg))
	return count

## Color base y textura de una superficie. La cara del personaje viene como
## textura del .glb, así que no basta con el color.
static func _surface_source(mi: MeshInstance3D, surface: int) -> Dictionary:
	# El material puede venir del MeshInstance o de la malla.
	var src: Material = mi.get_surface_override_material(surface)
	if src == null:
		src = mi.mesh.surface_get_material(surface)
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		return {"color": bm.albedo_color, "texture": bm.albedo_texture}
	if src is ShaderMaterial:
		# Ya estaba toonificado: se respeta, así reaplicar no pierde nada.
		var sm := src as ShaderMaterial
		var prev = sm.get_shader_parameter("albedo")
		return {
			"color": prev if prev is Color else Color.WHITE,
			"texture": sm.get_shader_parameter("albedo_texture"),
		}
	return {"color": Color.WHITE, "texture": null}

static func _material_for(src: Dictionary, cfg: Dictionary) -> ShaderMaterial:
	var base: Color = src["color"]
	var tex: Texture2D = src["texture"]
	var key := "%s|%s|%d|%.3f|%s|%s|%.3f|%.3f|%s|%.4f" % [
		base.to_html(true), str(tex.get_rid()) if tex else "-",
		cfg["bands"], cfg["band_softness"],
		(cfg["shadow_tint"] as Color).to_html(true), (cfg["rim_color"] as Color).to_html(true),
		cfg["rim_strength"], cfg["rim_width"],
		(cfg["outline_color"] as Color).to_html(true), cfg["outline_width"],
	]
	if _cache.has(key):
		return _cache[key]

	# Grosor 0 = sin contorno. El casco invertido necesita normales continuas;
	# sobre geometría de sombreado plano se abre por cada arista, así que los
	# mapas van con toon pero sin contorno.
	var outline: ShaderMaterial = null
	if float(cfg["outline_width"]) > 0.0:
		outline = ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.set_shader_parameter("outline_color", cfg["outline_color"])
		outline.set_shader_parameter("outline_width", cfg["outline_width"])
		# El juego pasó a tercera persona con cámara en perspectiva: sin
		# compensar, el contorno engorda al acercarse y se pierde de lejos.
		outline.set_shader_parameter("compensate_perspective", true)

	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("albedo", base)
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("use_texture", tex != null)
	mat.set_shader_parameter("bands", cfg["bands"])
	mat.set_shader_parameter("band_softness", cfg["band_softness"])
	mat.set_shader_parameter("shadow_tint", cfg["shadow_tint"])
	mat.set_shader_parameter("light_scale", 1.0)
	mat.set_shader_parameter("rim_color", cfg["rim_color"])
	mat.set_shader_parameter("rim_strength", cfg["rim_strength"])
	mat.set_shader_parameter("rim_width", cfg["rim_width"])
	mat.set_shader_parameter("specular_threshold", 0.90)
	mat.set_shader_parameter("specular_strength", 0.16)
	mat.set_shader_parameter("specular_sharpness", 32.0)
	mat.next_pass = outline

	_cache[key] = mat
	return mat

func _meshes(root: Node) -> Array[MeshInstance3D]:
	return _meshes_static(root)

static func _meshes_static(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_meshes_static(child))
	return out
