class_name InteractionFlow
extends Node

# PlayerIntent -> what happens. The same code path serves touch and mouse:
#
#   MOVE_TO    walk there
#   INSPECT    walk to the thing, face it, open the contextual action surface
#   CHOOSE     hand the chosen option to Mirror (queued, committed, then presented)
#   CANCEL     close the surface
#
# Nothing here decides an outcome; it only routes intent to Mirror.

signal focus_changed(target_id: String)

var room: Room
var witch: Witch
# The witch as a target ("witch"): her own pick volume, a child of her.
var witch_hotspot: Interactable
var runtime: MirrorRuntime
var surface: InteractionPresenter
# The postgame has no avatar to walk: a tap opens the options at once (GAME_SPEC section 6, postgame).
var postgame := false
var focused_target := ""
var _token := 0

func handle(intent: PlayerIntent) -> void:
	if runtime.is_busy():
		return
	match intent.type:
		PlayerIntent.Type.MOVE_TO:
			_token += 1
			_focus("")
			surface.close()
			witch.move_to(intent.position)
		PlayerIntent.Type.INSPECT:
			await _inspect(intent.target_id)
		PlayerIntent.Type.CHOOSE:
			choose_option_id(intent.option_id)
		PlayerIntent.Type.CANCEL:
			_token += 1
			_focus("")
			surface.close()

func _inspect(target_id: String) -> void:
	_token += 1
	var mine := _token
	surface.close()
	var interactable := hotspot_for(target_id)
	if interactable == null:
		return
	_focus(target_id)
	if not postgame:
		# A room with no floor to walk on (the window's close shot) takes the tap where she stands.
		var arrived: bool = true
		if witch.navigator != null:
			arrived = await witch.walk_to(approach_for(target_id, interactable))
		if mine != _token or not arrived:
			return
		witch.face_toward(interactable.focus_point())
	var options := runtime.options_for(target_id)
	if options.is_empty():
		_focus("")
		return
	surface.show_options(interactable.display_name(), options, interactable.focus_point())

func hotspot_for(target_id: String) -> Interactable:
	if target_id == "witch":
		return witch_hotspot
	return room.get_interactable(target_id) if room != null else null

func approach_for(target_id: String, interactable: Interactable) -> Vector3:
	if target_id == "witch":
		return witch.global_position
	return interactable.approach_point

func choose_option_id(option_id: String) -> void:
	for option in surface.current_options():
		if option.option_id == option_id:
			choose_option(option)
			return

func choose_option(option: InteractionOption) -> void:
	_focus("")
	runtime.submit(option.to_action())

func _focus(target_id: String) -> void:
	if focused_target != target_id:
		focused_target = target_id
		focus_changed.emit(target_id)
