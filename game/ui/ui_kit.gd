class_name UIKit
extends RefCounted

# Shared look for code-built UI at the 320x240 render size: the pixel font, white text with a
# black outline, dark translucent panels, and an amber hover. All text passed in is ALREADY
# translated; callers fetch it from data/text/ru.json with the tr function.

const FONT_PATH := "res://game/ui/fonts/pixel.ttf"
const FONT_SIZE := 8
const TITLE_SIZE := 16
const ACCENT := Color(1.0, 0.62, 0.18)
const PANEL_BG := Color(0.03, 0.03, 0.07, 0.86)
const PANEL_BORDER := Color(0.55, 0.55, 0.65, 1.0)

static var _font: Font

static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
	return _font

static func style_label(label: Label, size: int = FONT_SIZE, color: Color = Color.WHITE) -> void:
	label.add_theme_font_override("font", font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 1)

static func label(text: String, size: int = FONT_SIZE, color: Color = Color.WHITE) -> Label:
	var node := Label.new()
	node.text = text
	style_label(node, size, color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	return style

static func button(text: String, size: int = FONT_SIZE) -> Button:
	var node := Button.new()
	node.text = text
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", Color.WHITE)
	node.add_theme_color_override("font_hover_color", ACCENT)
	node.add_theme_color_override("font_pressed_color", ACCENT)
	node.add_theme_color_override("font_outline_color", Color.BLACK)
	node.add_theme_constant_override("outline_size", 1)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.14, 0.92)
	normal.border_color = Color(0.35, 0.35, 0.45)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(3)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = ACCENT
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", hover)
	return node
