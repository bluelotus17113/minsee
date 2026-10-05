# MinSee — Biblia de arte

Dirección declarada: **3D cel shading, chibi anime.**

Este documento no describe un ideal: recoge lo que ya es cierto en el proyecto,
medido de los ficheros, más las reglas que hay que respetar para que lo nuevo no
se separe de lo que ya existe. Cada valor dice dónde vive, para que no haya dos
fuentes de verdad.

Sustituye a la sección «18. Arte y Dirección Visual» del GDD, que describe el
enfoque de pixel art 32×32 ya abandonado.

---

## 1. La regla de una línea

Si algo se puede comprobar de un vistazo, que sea esto: **color plano separado
por un canto duro, con línea de tinta alrededor del personaje.** Nada de
degradados suaves, nada de reflejos brillantes, nada de texturas fotográficas.

---

## 2. Cel shading: el contrato

Vive en `shaders/toon.gdshader` y lo aplica `scripts/world/toon_skin.gd`.

| Parámetro | Valor | Por qué |
|---|---|---|
| `bands` | **2** | Cel clásico: luz y sombra. 3 ya se lee como degradado. |
| `band_softness` | **0.012** | Lo justo para que el canto no se sierre al girar la cámara. |
| `shadow_tint` | **`#758BB8`** (0.46, 0.50, 0.72) | La sombra se tiñe de frío, no se oscurece. En negro parece plástico. |
| `light_scale` | **1.0** | |
| `rim_color` / `rim_strength` / `rim_width` | `#FFF7E6` / 0.5 / 0.3 | Luz de borde, con canto duro como el resto. |
| `specular_threshold` / `strength` | 0.90 / 0.16 | Un brillo recortado y pequeño. Más alto salpica puntos blancos por la ropa. |
| `outline_width` | **0.011** | Casco invertido, compensado por distancia. |
| `outline_color` | **`#14101F`** (0.08, 0.06, 0.12) | Tinta oscura teñida de violeta, nunca negro puro. |

**Reglas duras del shader**

- El shader lleva `ambient_light_disabled` **a propósito**. La zona en sombra la
  define `shadow_tint`; si se activa la ambiental, cada mapa sobreexpone al
  personaje y se pierden las bandas.
- Una `light()` propia **no aplica `ALBEDO` sola ni divide entre `PI`**: las dos
  cosas van a mano. Las luces de los mapas van a `light_energy = 3` contando con
  esa división.
- **Los personajes llevan contorno; el escenario no.** El casco invertido
  necesita normales continuas, y la geometría de los mapas va con sombreado
  plano: se agrietaría en cada arista. El escenario lleva el mismo toon sin línea.
- Con cámara en perspectiva el contorno **se compensa por distancia**
  (`compensate_perspective = true`). Con ortogonal iría a `false`.

---

## 3. Paleta

### Mundo — medida de los `.glb` de `scenes/world/3d/`

Verdes apagados y tierras quebradas. El mundo es el fondo: no compite.

| Rol | Color |
|---|---|
| Hierba (pueblo) | `#4D7A2E` |
| Hierba oscura / clara (bosque) | `#335C29` / `#578038` |
| Hoja | `#2E6B2E` · oscura `#1F4D24` |
| Tronco | `#52331A` · bosque `#4D2E1A` |
| Camino | `#9E8052` · bosque `#8C6B47` |
| Piedra | `#998C7A` · roca `#736B61` |
| Agua / arroyo | `#4773A6` / `#4D8CB2` |
| Tejado | `#A6382E` |
| Madera / valla | `#8C522E` / `#80522E` |
| Acentos (flor, seta, oro) | `#D94D4D` `#C72E2E` `#D9C74D` `#F2C74D` |
| Cueva: tierra, piedra, cristal, llama | `#332921` `#4D4547` `#8CD9F2` `#FF8C26` |

### Personajes — `Tools/chars_spec.py`

Vivos y saturados: **destacan contra el fondo apagado**. Es deliberado, no un
descuido. Siete roles por personaje: `skin`, `hair`, `shirt`, `trim`, `pants`,
`boots`, `eyes`.

| Personaje | Camisa | Pelo | Ojos |
|---|---|---|---|
| Min | `#598CF2` | `#38426B` | `#2E61D9` |
| Lia | `#D959D9` | `#9E4299` | `#B84CB8` |
| Aldeano | `#B8AD8C` | `#573D29` | `#523D2E` |
| Mercader | `#8C619E` | `#4C4C52` | `#4C4238` |
| Goblin / Goblin Rey | piel `#85B261` / `#709E52` | — (calvo) | `#EBB82E` / `#FA6B33` |
| Esqueleto | hueso `#E6E3D1` | — (calvo) | cuenca `#14141A` |

**Regla:** un personaje nuevo se define en `chars_spec.py` y nada más. Si hace
falta un color que no encaja en los siete roles, primero se discute el rol.

### Lo que falta por fijar

No hay paleta cerrada tipo DB16. Los colores del mundo salen de los `.glb` de
junio y no están normalizados entre mapas. **Pendiente:** decidir si se
normalizan o se acepta que cada zona tenga su familia.

---

## 4. Proporciones del personaje

De `Tools/generar_personajes.py`. En metros, y **1 metro = 1 casilla de la
rejilla vieja**, que es lo que permite que los valores de `move_range`,
`skill_range` y `aoe_radius` de los `.tres` sigan valiendo.

| Medida | Valor |
|---|---|
| Altura total | **1.32 m** |
| Radio de la cabeza | 0.255 |
| Cabeza sobre el total | **~39%** — chibi: casi un tercio |
| Centro de la cabeza | z = 1.035 |
| Hombros / cadera | z = 0.735 / 0.455 |
| Cuerpo (radio de ocupación en combate) | 0.45 → dos unidades nunca a menos de 0.9 |

---

## 5. Convenios que no se pueden romper

- **El personaje se modela mirando a +Y en Blender.** El exportador glTF
  convierte `(x, y, z)` en `(x, z, -y)`, así que +Y acaba siendo −Z en Godot, su
  «adelante». Mirando a −Y sale de espaldas.
- **La cara va en textura, nunca en geometría.** El contorno infla cada
  superficie a lo largo de su normal; unos ojos modelados sobresalen menos que
  ese casco y el contorno de la cabeza se los come. Mapeo equirectangular fijo:
  `u = 0.5 + atan2(x, y)/2π` (el frente cae en u = 0.5),
  `v = 0.5 + asin(nz)/π` (la coronilla en v = 1).
- **Todas las mallas con sombreado suave.** El casco invertido se abre por cada
  arista dura.
- **La malla del personaje tiene que estar cerrada.** Una malla abierta hace
  fallar el cálculo automático de pesos y el `.glb` sale **sin esqueleto**, sin
  dar error: ni animación ni colocación correcta.
- **El origen del modelo está en los pies**, y las entidades de los mapas se
  colocan a `y = 0.95`, que es la cara pisable de los `.glb` de escenario.

---

## 6. Interfaz

- Resolución base **640×360** con `stretch/mode = canvas_items`: el 3D va a
  resolución nativa y la interfaz escala. No subir la base: la UI está maquetada
  a mano para 640×360.
- MSAA 4× activo, para que el contorno no se sierre.
- Revelado **Standard**, no AgX ni Filmic: lavan el color por diseño y el cel
  shading lo quiere tal cual.
- Nada de pixel art en la interfaz: viene del enfoque anterior.

**Pendiente:** el GDD pedía «marcos de cuero oscuro con runas doradas» y los
paneles actuales son lisos. Sin decidir.

---

## 7. Cómo se genera el arte

Todo por código, sin abrir el editor. Las caras primero, porque el `.glb`
empotra la textura.

```bash
python3 Tools/generar_caras.py              # PIL -> chars/faces/*.png
blender -b -P Tools/generar_personajes.py   # Blender -> chars/*.glb
godot --headless --path . --import          # Godot no reimporta solo
```

Para mirar el resultado sin abrir el editor:

```bash
godot --path . scenes/debug/capture.tscn -- chars  salida.png [ids]
godot --path . scenes/debug/capture.tscn -- scene  <escena> salida.png [frames] [walk]
godot --path . scenes/debug/capture.tscn -- battle salida.png [enemigos] [frames] [mover|andar]
```

---

## 8. Cómo se comprueba que algo cumple

Antes de dar por bueno un asset nuevo:

1. ¿Se ve el canto duro entre luz y sombra, o hay degradado?
2. ¿El personaje tiene línea de tinta y el escenario no?
3. ¿La sombra tira a frío o se ha ido a gris/negro?
4. ¿Los colores del personaje destacan contra el fondo, o se confunden?
5. Si es un personaje: ¿tiene esqueleto y animaciones? (`skins` ≠ 0 en el `.glb`)
6. **Mirarlo renderizado.** Comprobar el valor en el fichero no basta: con malla
   animada quien coloca los vértices es el hueso, no el campo del glTF.
