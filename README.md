# MinSee

JRPG por turnos en pixel art (64×64) inspirado en la saga Trails. Hecho en **Godot 4**.

Resolución base de 640×360 con `stretch/mode = viewport`, ventana de 1280×720.

## Cómo abrirlo

```bash
godot --path .          # abre el editor
godot --path . --import # reimporta assets editados desde fuera del editor
```

La escena principal es `scenes/menu/main_menu.tscn`.

## Estructura

| Carpeta | Qué hay |
|---|---|
| `scripts/autoload/` | Los 8 singletons: `GameState`, `BattleLoader`, `DialogueManager`, `SaveManager`, `MapManager`, `MusicManager`, `Story`, `CutsceneRunner` |
| `scripts/data/` | Los `Resource` del juego (actores, armas, objetos, habilidades, enemigos, diálogos, misiones, tiendas, cofres, encuentros, cutscenes, árboles de habilidad) |
| `data/` | Las instancias `.tres` de todo lo anterior: el contenido del juego |
| `scenes/battle/` | Combate por turnos |
| `scenes/world/` | Mundo explorable: jugador, NPCs, portales, cofres, zonas de encuentro aleatorio |
| `scenes/menu/`, `scenes/dialogue/`, `scenes/shop/` | Interfaz: menú, pausa, guardado, diálogos, tienda, posada, reclutamiento |
| `sprites/` | Pixel art: personajes, retratos y tiles |
| `addons/` | Dos plugins propios del editor (ver abajo) |
| `docs/` | GDD y grimorio (diseño) |

## Plugins del editor

Dos herramientas propias que se activan solas con el proyecto:

- **`minsee_database`** — dock para editar los `.tres` de `data/` sin pelearse con el inspector.
- **`minsee_map`** — dock del grafo de mapas; las posiciones viven en `data/map_graph_positions.cfg`.

## Controles

`WASD`/flechas mover · `E` interactuar · `Espacio`/`Enter` confirmar · `Esc` cancelar · `Enter`/`Tab` menú · `Z`/`X` girar cámara

## Notas

- `.godot/` no se versiona: es caché del editor y se regenera.
- Los ficheros `.uid` **sí** se versionan. Un `uid://` caducado resuelve al recurso equivocado en silencio, sin error.
- El proyecto declara `config/features = "4.6"`; aquí corre sobre Godot 4.7.2.
