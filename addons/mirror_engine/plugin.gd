@tool
extends EditorPlugin

const VALIDATOR_SCRIPT := preload("res://addons/mirror_engine/mirror_validator.gd")
var _menu_name := "Validate Mirror Content"

func _enter_tree() -> void:
    add_tool_menu_item(_menu_name, Callable(self, "_validate_content"))

func _exit_tree() -> void:
    remove_tool_menu_item(_menu_name)

func _validate_content() -> void:
    var report := VALIDATOR_SCRIPT.new().validate_project("res://")
    var message := report.get("summary", "Validation completed.")
    print(message)
    if report.get("errors", []).size() > 0:
        push_error("Mirror validation found errors. See output for details.")
