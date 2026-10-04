"""Ficha de los personajes de MinSee, compartida por los dos generadores.

Los tonos de Min y Lia salen de data/actors/*.tres para que el modelo y la
ficha de combate no se contradigan.
"""

CHARS = {
    "min": {
        "skin": (0.98, 0.84, 0.72),
        "hair": (0.22, 0.26, 0.42),
        "shirt": (0.35, 0.55, 0.95),
        "trim": (0.92, 0.93, 0.98),
        "pants": (0.24, 0.27, 0.38),
        "boots": (0.42, 0.30, 0.22),
        "eyes": (0.18, 0.38, 0.85),
        "hair_style": "short",
        "face": "decidido",
    },
    "lia": {
        "skin": (0.99, 0.87, 0.78),
        "hair": (0.62, 0.26, 0.60),
        "shirt": (0.85, 0.35, 0.85),
        "trim": (0.98, 0.90, 0.96),
        "pants": (0.40, 0.20, 0.42),
        "boots": (0.34, 0.22, 0.34),
        "eyes": (0.72, 0.30, 0.72),
        "hair_style": "long",
        "face": "dulce",
    },
    "aldeano": {
        "skin": (0.95, 0.80, 0.66),
        "hair": (0.34, 0.24, 0.16),
        "shirt": (0.72, 0.68, 0.55),
        "trim": (0.85, 0.82, 0.72),
        "pants": (0.46, 0.38, 0.30),
        "boots": (0.32, 0.25, 0.20),
        "eyes": (0.32, 0.24, 0.18),
        "hair_style": "short",
        "face": "amable",
    },
    "mercader": {
        "skin": (0.92, 0.76, 0.62),
        "hair": (0.30, 0.30, 0.32),
        "shirt": (0.55, 0.38, 0.62),
        "trim": (0.92, 0.80, 0.42),
        "pants": (0.32, 0.26, 0.34),
        "boots": (0.28, 0.22, 0.26),
        "eyes": (0.30, 0.26, 0.22),
        "hair_style": "short",
        "face": "pillo",
    },
    "maestre": {
        "skin": (0.90, 0.76, 0.64),
        "hair": (0.72, 0.72, 0.74),
        "shirt": (0.30, 0.34, 0.48),
        "trim": (0.82, 0.72, 0.36),
        "pants": (0.24, 0.26, 0.36),
        "boots": (0.26, 0.24, 0.28),
        "eyes": (0.40, 0.46, 0.58),
        "hair_style": "short",
        "face": "decidido",
    },
    "posadero": {
        "skin": (0.94, 0.78, 0.64),
        "hair": (0.52, 0.42, 0.28),
        "shirt": (0.78, 0.52, 0.34),
        "trim": (0.95, 0.90, 0.80),
        "pants": (0.40, 0.32, 0.24),
        "boots": (0.30, 0.24, 0.18),
        "eyes": (0.36, 0.28, 0.18),
        "hair_style": "short",
        "face": "amable",
    },
}


def rgb255(c):
    return tuple(int(round(max(0.0, min(1.0, v)) * 255)) for v in c)


def shade(c, f):
    """Oscurece (f<1) o aclara (f>1) un color sin salirse de 0..1."""
    if f <= 1.0:
        return tuple(v * f for v in c)
    return tuple(v + (1.0 - v) * (f - 1.0) for v in c)
