@tool
class_name WorldRoot
extends Node3D

## Raíz de un mapa 3D. Sustituye a iso_camera_setup.gd: desde el giro a
## tercera persona la cámara vive dentro del jugador, así que aquí solo queda
## unificar el estilo del escenario con el de los personajes.

@export_group("Estilo")
## Aplica el sombreado toon a todo el mapa al arrancar, para que el escenario
## y los personajes no parezcan de dos juegos distintos.
@export var toon_world: bool = true
## Contorno del escenario. A 0 se desactiva: la geometría de los mapas va con
## sombreado plano y el casco invertido se agrieta en cada arista dura.
@export_range(0.0, 0.1) var world_outline: float = 0.0

func _ready() -> void:
	# Solo en juego: en el editor ensuciaría la escena con materiales override.
	if toon_world and not Engine.is_editor_hint():
		ToonSkin.skin(self, world_outline)
