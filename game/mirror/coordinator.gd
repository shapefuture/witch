class_name LiveHallCoordinator
extends Node

# Connects a live room to Mirror's Minds layer. It attaches PropEvents to any room that implements the room slot
# (game/world/room_slot.gd), under the room's own Mirror id. It decides nothing: a poke is committed by PropEvents
# through Mirror.minds.perceive, and what Mirror answers comes back as reactions and lines.
#
#   var live := LiveHallCoordinator.new()
#   live.runtime = Mirror
#   add_child(live)               # the Mirror clock runs while it is in the tree
#   live.attach(hall)             # null for a room that does not implement the slot
#   live.bridge.presentation_ready.connect(presenter)  # the lines Mirror answers with

var runtime: MirrorRuntime
# Mirror's clock (PropEvents.run_clock and seconds_per_tick). Tests turn it off to stay deterministic.
var run_clock := true
var seconds_per_tick := 1.0
var bridge: PropEvents

# Returns the bridge, or null when there is no runtime or the room does not implement the slot (a refusal leaves
# whatever was attached before in place).
func attach(room: Object) -> PropEvents:
	if runtime == null or not RoomSlot.conforms(room):
		return null
	detach()
	bridge = PropEvents.attach(room, runtime, {
		"place": str(room.call("mirror_room_id")), "run_clock": run_clock, "seconds_per_tick": seconds_per_tick,
	})
	add_child(bridge)
	return bridge

func detach() -> void:
	if bridge == null:
		return
	bridge.detach()
	if bridge.get_parent() == self:
		remove_child(bridge)
	bridge.free()
	bridge = null
