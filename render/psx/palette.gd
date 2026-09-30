class_name Palette
extends RefCounted

# A deliberately small set of colours for the mundane world, plus the wider set magic is
# allowed to use. Placeholders use only these, so swapping in real models later changes the
# silhouettes, not the colour identity.

const GRASS := Color(0.20, 0.29, 0.17)
const DIRT := Color(0.33, 0.26, 0.19)
const STONE := Color(0.46, 0.46, 0.52)
const WOOD := Color(0.40, 0.27, 0.16)
const WOOD_DARK := Color(0.26, 0.17, 0.11)
const CANOPY := Color(0.13, 0.30, 0.20)
const BRASS := Color(0.78, 0.60, 0.25)
const BRASS_DARK := Color(0.50, 0.37, 0.15)
const IRON := Color(0.22, 0.23, 0.27)

const CLOAK := Color(0.30, 0.17, 0.42)
const HAT := Color(0.20, 0.12, 0.30)
const SKIN := Color(0.86, 0.71, 0.60)
const COAT := Color(0.66, 0.36, 0.20)
const SCARF := Color(0.80, 0.74, 0.58)
const SILHOUETTE := Color(0.10, 0.10, 0.13)

const LAMP := Color(1.0, 0.62, 0.18)
const MOON := Color(0.70, 0.78, 1.0)

# Colours only magic may use.
const MAGIC_GOLD := Color(1.0, 0.85, 0.45)
const MAGIC_CYAN := Color(0.35, 0.95, 1.0)
const MAGIC_ROSE := Color(1.0, 0.45, 0.75)
