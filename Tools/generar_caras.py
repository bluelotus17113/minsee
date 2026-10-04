"""Pinta las caras de MinSee como textura equirectangular de la cabeza.

    python3 Tools/generar_caras.py [id ...]

Por qué textura y no geometría: el contorno del shader toon es por casco
invertido, infla cada superficie a lo largo de su normal. Unos ojos modelados
aparte sobresalen de la cabeza menos de lo que mide ese casco, así que el
contorno de la propia cabeza se los come. Pintados no hay nada que tapar.

El mapeo lo impone generar_personajes.py y es fijo:
    u = 0.5 + atan2(x, y) / 2pi   ->  el frente (+Y) cae en u = 0.5
    v = 0.5 + asin(nz) / pi       ->  la coronilla en v = 1
En píxeles, con el origen arriba a la izquierda: x = u*W, y = (1-v)*H.
Así el centro de la cara es (W/2, H/2).
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from chars_spec import CHARS, rgb255, shade  # noqa: E402

OUT_DIR = Path(__file__).resolve().parent.parent / "scenes" / "world" / "3d" / "chars" / "faces"

W, H = 1024, 512
SS = 4  # supermuestreo: las curvas de un ojo a pelo salen con escalera

# En esta proyección, 1 px horizontal y 1 px vertical cubren casi el mismo arco
# sobre la esfera (0.92 : 1), así que un círculo en la textura sale redondo en
# la cabeza. Por eso las medidas de abajo se pueden pensar en píxeles sin más.
CX, CY = W // 2, H // 2
EYE_DX = 78
EYE_Y = CY + 4
EYE_W, EYE_H = 94, 108
BROW_Y = CY - 86
MOUTH_Y = CY + 96
BLUSH_DX, BLUSH_Y = 152, CY + 54


def _ellipse(cx, cy, w, h):
    return [cx - w / 2.0, cy - h / 2.0, cx + w / 2.0, cy + h / 2.0]


def _clip_over(base, overlay, mask):
    """Compone `overlay` sobre `base` solo dentro de `mask`.

    Con Image.composite se escribiría el overlay ENTERO dentro de la máscara,
    transparencias incluidas, y eso borra lo que hubiera debajo.
    """
    a = ImageChops.multiply(overlay.getchannel("A"), mask)
    clipped = overlay.copy()
    clipped.putalpha(a)
    base.alpha_composite(clipped)


def _mask(size, box):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return m


def draw_eye(layer, cx, cy, eye_rgb, lash_rgb, outward):
    """Un ojo anime: blanco a los lados, iris alto, pestaña en media luna.

    `outward` es +1 o -1 y dice hacia dónde cae el rabillo del ojo.
    """
    d = ImageDraw.Draw(layer)
    w, h = EYE_W, EYE_H
    size = layer.size

    # Esclerótica. El iris será más estrecho que ella: ese blanco a los lados
    # es lo que distingue un ojo de un botón.
    d.ellipse(_ellipse(cx, cy, w, h), fill=(252, 250, 255, 255))

    # Iris alto y estrecho, apoyado en el párpado de abajo.
    iris_w, iris_h = w * 0.66, h * 0.88
    iris_cy = cy + h * 0.04
    iris_box = _ellipse(cx, iris_cy, iris_w, iris_h)
    d.ellipse(iris_box, fill=(*rgb255(eye_rgb), 255))

    # Degradado del iris, recortado contra el propio iris.
    grad = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    gd.ellipse(_ellipse(cx, iris_cy - iris_h * 0.26, iris_w * 1.1, iris_h * 0.70),
               fill=(*rgb255(shade(eye_rgb, 0.38)), 255))
    gd.ellipse(_ellipse(cx, iris_cy + iris_h * 0.34, iris_w * 0.86, iris_h * 0.30),
               fill=(*rgb255(shade(eye_rgb, 1.35)), 255))
    grad = grad.filter(ImageFilter.GaussianBlur(radius=iris_w * 0.13))
    _clip_over(layer, grad, _mask(size, iris_box))
    d = ImageDraw.Draw(layer)

    # Pupila
    d.ellipse(_ellipse(cx, iris_cy + iris_h * 0.04, iris_w * 0.46, iris_h * 0.52),
              fill=(*rgb255(shade(eye_rgb, 0.18)), 255))

    # Brillos: el grande arriba, al lado contrario del rabillo.
    d.ellipse(_ellipse(cx - outward * iris_w * 0.26, iris_cy - iris_h * 0.24,
                       iris_w * 0.40, iris_h * 0.30), fill=(255, 255, 255, 255))
    d.ellipse(_ellipse(cx + outward * iris_w * 0.24, iris_cy + iris_h * 0.26,
                       iris_w * 0.19, iris_h * 0.15), fill=(255, 255, 255, 225))

    # Sombra del párpado sobre la parte alta del ojo.
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(_ellipse(cx, cy - h * 0.42, w * 1.02, h * 0.46),
                                   fill=(*rgb255(shade(lash_rgb, 1.1)), 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=h * 0.05))
    _clip_over(layer, shadow, _mask(size, _ellipse(cx, cy, w, h)))

    # Pestaña: media luna = el ojo menos el mismo ojo bajado. Así sigue la
    # curva del párpado y se afila sola en las dos esquinas, que es justo lo
    # que un trazo de arco no sabe hacer.
    outer_box = _ellipse(cx + outward * w * 0.05, cy - h * 0.02, w * 1.16, h * 1.08)
    drop_box = _ellipse(cx + outward * w * 0.05, cy + h * 0.24, w * 1.16, h * 1.08)
    lash_mask = ImageChops.subtract(_mask(size, outer_box), _mask(size, drop_box))
    flat = Image.new("RGBA", size, (*rgb255(lash_rgb), 255))
    layer.paste(flat, (0, 0), lash_mask)
    d = ImageDraw.Draw(layer)

    # Párpado inferior, apenas insinuado.
    d.arc(_ellipse(cx, cy + h * 0.02, w * 0.80, h * 0.88), start=52, end=128,
          fill=(*rgb255(shade(lash_rgb, 1.6)), 95), width=max(2, int(h * 0.030)))


def draw_brow(layer, cx, cy, hair_rgb, outward, mood):
    """Ceja de grosor variable: círculos a lo largo de una curva."""
    col = (*rgb255(shade(hair_rgb, 0.8)), 255)
    d = ImageDraw.Draw(layer)
    tilt = {"decidido": 14, "pillo": 10, "dulce": -8, "amable": -2}.get(mood, 0)
    half = EYE_W * 0.50
    inner = (cx - outward * half, cy + tilt)
    outer = (cx + outward * half, cy - tilt * 0.5)
    peak = (cx + outward * half * 0.15, cy - EYE_H * 0.14)
    steps = 28
    for i in range(steps + 1):
        t = i / steps
        # Bézier cuadrática entre el extremo interior y el exterior.
        x = (1 - t) ** 2 * inner[0] + 2 * (1 - t) * t * peak[0] + t ** 2 * outer[0]
        y = (1 - t) ** 2 * inner[1] + 2 * (1 - t) * t * peak[1] + t ** 2 * outer[1]
        r = EYE_H * (0.085 - 0.055 * t)  # gruesa por dentro, afilada por fuera
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)


def draw_mouth(layer, mood, lash_rgb):
    d = ImageDraw.Draw(layer)
    col = (*rgb255(shade(lash_rgb, 1.15)), 245)
    w = EYE_W * 1.20
    t = max(4, int(EYE_H * 0.090))
    if mood == "dulce":
        d.arc([CX - w / 2, MOUTH_Y - 30, CX + w / 2, MOUTH_Y + 26], 25, 155, fill=col, width=t)
    elif mood == "decidido":
        d.arc([CX - w * 0.46, MOUTH_Y - 34, CX + w * 0.46, MOUTH_Y + 14], 35, 145, fill=col, width=t)
    elif mood == "pillo":
        d.arc([CX - w * 0.52, MOUTH_Y - 34, CX + w * 0.52, MOUTH_Y + 20], 18, 128, fill=col, width=t)
    else:  # amable
        d.arc([CX - w * 0.48, MOUTH_Y - 28, CX + w * 0.48, MOUTH_Y + 22], 28, 152, fill=col, width=t)


def draw_blush(layer, skin_rgb):
    blush = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(blush)
    col = (*rgb255(shade((skin_rgb[0], skin_rgb[1] * 0.72, skin_rgb[2] * 0.72), 1.0)), 150)
    for sx in (-1, 1):
        bd.ellipse(_ellipse(CX + sx * BLUSH_DX, BLUSH_Y, 118, 62), fill=col)
    blush = blush.filter(ImageFilter.GaussianBlur(radius=26))
    layer.alpha_composite(blush)


def build(char_id, spec):
    skin = spec["skin"]
    # La pestaña tira del color del pelo, no del negro: un pelo castaño con
    # pestañas negras canta.
    lash = shade(spec["hair"], 0.55)

    big = Image.new("RGBA", (W * SS, H * SS), (*rgb255(skin), 255))
    # Todo se dibuja a escala SS y luego se reduce.
    globals_backup = (CX, CY, EYE_DX, EYE_Y, EYE_W, EYE_H, BROW_Y, MOUTH_Y, BLUSH_DX, BLUSH_Y)
    _scale_globals(SS)
    try:
        draw_blush(big, skin)
        for sx in (-1, 1):
            draw_eye(big, CX + sx * EYE_DX, EYE_Y, spec["eyes"], lash, outward=sx)
            draw_brow(big, CX + sx * EYE_DX, BROW_Y, spec["hair"], outward=sx, mood=spec["face"])
        draw_mouth(big, spec["face"], lash)
    finally:
        _restore_globals(globals_backup)

    img = big.resize((W, H), Image.LANCZOS).convert("RGB")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{char_id}.png"
    img.save(out)
    print(f"[ok] cara {char_id} -> {out.relative_to(OUT_DIR.parent.parent.parent.parent)}")
    return out


def _scale_globals(k):
    g = globals()
    for name in ("CX", "CY", "EYE_DX", "EYE_Y", "EYE_W", "EYE_H", "BROW_Y", "MOUTH_Y", "BLUSH_DX", "BLUSH_Y"):
        g[name] = g[name] * k


def _restore_globals(vals):
    g = globals()
    for name, v in zip(("CX", "CY", "EYE_DX", "EYE_Y", "EYE_W", "EYE_H", "BROW_Y", "MOUTH_Y", "BLUSH_DX", "BLUSH_Y"), vals):
        g[name] = v


def main():
    ids = sys.argv[1:] or list(CHARS)
    for char_id in ids:
        if char_id not in CHARS:
            print(f"[skip] {char_id}: no está en CHARS")
            continue
        build(char_id, CHARS[char_id])


if __name__ == "__main__":
    main()
