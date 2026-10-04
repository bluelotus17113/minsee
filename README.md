# MinSee

JRPG por turnos en **3D estilo anime**, inspirado en la saga Trails. Hecho en **Godot 4**.

Cámara isométrica ortogonal con giro por pasos de 90° y zoom, al estilo de Trails
(`scripts/world/iso_camera_setup.gd`, se pone como script del `Node3D` raíz de cada mapa).

## Cómo abrirlo

```bash
godot --path .          # abre el editor
godot --path . --import # reimporta assets editados desde fuera del editor
```

La escena principal es `scenes/menu/main_menu.tscn`, y «Nueva partida» entra a
`scenes/world/3d/patio_pueblo_3d.tscn`.

## Estructura

| Carpeta | Qué hay |
|---|---|
| `scripts/autoload/` | Los 8 singletons: `GameState`, `BattleLoader`, `DialogueManager`, `SaveManager`, `MapManager`, `MusicManager`, `Story`, `CutsceneRunner` |
| `scripts/data/` | Los `Resource` del juego (actores, armas, objetos, habilidades, enemigos, diálogos, misiones, tiendas, cofres, encuentros, cutscenes, árboles de habilidad) |
| `data/` | Las instancias `.tres` de todo lo anterior: el contenido del juego |
| `scenes/world/3d/` | **El mundo.** Mapas `.glb` (patio del pueblo, interior de casa, sendero del bosque, cueva del jefe) y los nodos `*_3d`: jugador, NPC, cofre, portal, enemigo de overworld, evento, zona de encuentro |
| `scenes/world/` | Versiones 2D de los mismos nodos. Heredadas del enfoque anterior, ya no se cargan |
| `scenes/battle/` | Combate por turnos. **Todavía en 2D** |
| `scenes/menu/`, `scenes/dialogue/`, `scenes/shop/` | Interfaz: menú, pausa, guardado, diálogos, tienda, posada, reclutamiento |
| `sprites/` | Sprites del enfoque 2D anterior (personajes, retratos, tiles) |
| `addons/` | Dos plugins propios del editor (ver abajo) |
| `docs/` | GDD y grimorio (diseño) |

## Plugins del editor

Dos herramientas propias que se activan solas con el proyecto:

- **`minsee_database`** — dock para editar los `.tres` de `data/` sin pelearse con el inspector.
- **`minsee_map`** — dock del grafo de mapas; las posiciones viven en `data/map_graph_positions.cfg`.

## Controles

`WASD`/flechas mover · `E` interactuar · `Espacio`/`Enter` confirmar · `Esc` cancelar ·
`Enter`/`Tab` menú · `Z`/`X` girar cámara · rueda zoom

## Estado del giro a 3D

El mundo explorable ya corre en 3D y el guardado distingue mapa 2D de 3D (campo `is_3d`).
Lo que queda del enfoque anterior:

- **Sin shaders.** No hay ni un `.gdshader` en el proyecto: el aspecto anime (toon, contorno,
  luz de borde) está entero por hacer.
- **El combate sigue en 2D** (`scenes/battle/battle.tscn` es `Control`/`Node2D`).
- **El viewport es de pixel art**: 640×360 con `stretch/mode = viewport`.
- `scenes/world/*.tscn` y `sprites/` son legado; nada del arranque los carga.
- `GameState.last_world_scene` arranca apuntando al `world.tscn` 2D. No llega a usarse
  (todas las llamadas a `BattleLoader.start_battle` pasan la escena actual), pero engaña.

## Notas

- `.godot/` no se versiona: es caché del editor y se regenera.
- Los ficheros `.uid` **sí** se versionan. Un `uid://` caducado resuelve al recurso
  equivocado en silencio, sin error.
- El proyecto declara `config/features = "4.6"`; aquí corre sobre Godot 4.7.2.
