# MinSee

JRPG por turnos en **3D estilo anime** y **tercera persona**, inspirado en la saga
Trails. Hecho en **Godot 4**.

La cámara va dentro de la escena del jugador (`CamRig` → `SpringArm3D` → `Camera3D`),
no en el mapa: el brazo necesita lanzar su rayo desde el cuerpo del personaje para
apartarse de las paredes.

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
| `scenes/world/3d/chars/` | Los personajes, generados por código: `.glb` con rig y las acciones `idle`/`walk`, y en `faces/` la textura de cada cara |
| `shaders/` | `toon.gdshader` (bandas de luz, sombra teñida, luz de borde) y `toon_outline.gdshader` (contorno por casco invertido) |
| `Tools/` | Los generadores: `generar_personajes.py` (Blender headless) y `generar_caras.py` (PIL) |
| `scenes/world/` | Versiones 2D de los mismos nodos. Heredadas del enfoque anterior, ya no se cargan |
| `scenes/battle/` | Combate por turnos. **Todavía en 2D** |
| `scenes/menu/`, `scenes/dialogue/`, `scenes/shop/` | Interfaz: menú, pausa, guardado, diálogos, tienda, posada, reclutamiento |
| `sprites/` | Sprites del enfoque 2D anterior (personajes, retratos, tiles) |
| `scripts/debug/` | `capture.gd`: saca PNG de una escena o de la fila de personajes sin abrir el editor |
| `addons/` | Dos plugins propios del editor (ver abajo) |
| `docs/` | GDD y grimorio (diseño) |

## Plugins del editor

Dos herramientas propias que se activan solas con el proyecto:

- **`minsee_database`** — dock para editar los `.tres` de `data/` sin pelearse con el inspector.
- **`minsee_map`** — dock del grafo de mapas; las posiciones viven en `data/map_graph_positions.cfg`.

## Generar el arte

Los personajes no se modelan a mano: salen de dos scripts. Las caras primero,
porque el `.glb` empotra la textura.

```bash
python3 Tools/generar_caras.py              # PIL -> chars/faces/*.png
blender -b -P Tools/generar_personajes.py   # Blender -> chars/*.glb
godot --headless --path . --import          # Godot no reimporta solo
```

La ficha de cada personaje (colores, peinado, gesto) está en `Tools/chars_spec.py`.

## Controles

`WASD`/flechas mover · ratón girar cámara · rueda zoom · `E` interactuar ·
`Espacio`/`Enter` confirmar · `Esc` cancelar · `Enter`/`Tab` menú ·
`Z`/`X` girar cámara con mando

## Estado del giro a 3D

Hecho: el mundo explorable en tercera persona, el shader toon aplicado a personajes
y escenario, y seis personajes con rig y animaciones de reposo y paso.

Pendiente:

- **El combate sigue en 2D** (`scenes/battle/battle.tscn` es `Control`/`Node2D`).
- `scenes/world/*.tscn` y `sprites/` son legado; nada del arranque los carga.
- `GameState.last_world_scene` arranca apuntando al `world.tscn` 2D. No llega a usarse
  (todas las llamadas a `BattleLoader.start_battle` pasan la escena actual), pero engaña.
- `ActorStats` todavía tiene `sprite`/`sprite_size` y no un campo de modelo, como sí
  tiene ya `NPCData`.

## Cosas que no son evidentes

- **El personaje se modela mirando a +Y en Blender.** El exportador glTF convierte
  `(x, y, z)` en `(x, z, -y)`, así que +Y acaba siendo −Z en Godot, su "adelante".
- **La cara va en textura, no en geometría.** El contorno infla cada superficie a lo
  largo de su normal; unos ojos modelados sobresalen menos que ese casco y el contorno
  de la cabeza se los come.
- **El `light()` propio no aplica `ALBEDO` solo, ni divide entre PI.** Hay que hacer las
  dos cosas a mano o la luz entra como blanco puro (las luces de los mapas van a
  `light_energy = 3` contando con esa división).
- **El shader ignora la luz ambiental** (`ambient_light_disabled`): en un toon la sombra
  la define `shadow_tint`, y si no cada mapa sobreexpone al personaje.
- **El escenario va con toon pero sin contorno.** El casco invertido necesita normales
  continuas y la geometría de los mapas tiene sombreado plano: se agrietaría en cada arista.
- **Las animaciones de un `.glb` entran sin bucle** salvo que el nombre acabe en `-loop`.
  `player_3d.gd` les pone `LOOP_LINEAR` al arrancar.

## Notas

- `.godot/` no se versiona: es caché del editor y se regenera.
- Los ficheros `.uid` **sí** se versionan. Un `uid://` caducado resuelve al recurso
  equivocado en silencio, sin error.
- El proyecto declara `config/features = "4.6"`; aquí corre sobre Godot 4.7.2.
