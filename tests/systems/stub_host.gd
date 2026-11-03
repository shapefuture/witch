extends Node

# A stand-in for the game root in the systems tests: the members the systems seam reads (the Mirror runtime, the room and
# the witch). Not a test: the runner only loads test_*.gd files.

var runtime: MirrorRuntime
var room: Object
var witch: Node3D
