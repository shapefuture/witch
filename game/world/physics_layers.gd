class_name PhysicsLayers
extends RefCounted

# Collision bit VALUES (layer n = 1 << (n - 1)).
const WORLD := 1          # layer 1: solid obstacles the witch cannot walk through
const INTERACTABLE := 2   # layer 2: pick volumes for things the player can point at
const ACTOR := 4          # layer 3: characters
const GROUND := 8         # layer 4: the walkable floor, used only for picking a destination
