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
var runtime: MirrorRuntime
var surface: InteractionPresenter
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
	var interactable := room.get_interactable(target_id)
	if interactable == null:
		return
	_focus(target_id)
	var arrived := await witch.walk_to(interactable.approach_point)
	if mine != _token or not arrived:
		return
	witch.face_toward(interactable.focus_point())
	var options := runtime.options_for(target_id)
	if options.is_empty():
		_focus("")
		return
	surface.show_options(interactable.display_name(), options)

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
