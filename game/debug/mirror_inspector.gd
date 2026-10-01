class_name MirrorInspector
extends CanvasLayer

# Developer overlay (F3). Never shown to players. Three pages:
#   STATE    what the witch knows / believes, what Tomas expects, the hypothesis status
#   LOG      the canonical event log in human-readable form
#   EXPLAIN  "Explain Why": for the focused target, why each option is (not) available

const PAGES := ["STATE", "LOG", "EXPLAIN"]

var runtime: MirrorRuntime
var focus_target := ""
var page := 0
var _label: Label
var _panel: ColorRect

func _ready() -> void:
	layer = 30
	visible = false
	_panel = ColorRect.new()
	_panel.color = Color(0, 0, 0, 0.82)
	_panel.size = Vector2(320, 240)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = UIKit.label("", 6)
	_label.position = Vector2(4, 2)
	_label.size = Vector2(312, 236)
	_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_label.clip_text = true
	add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		visible = not visible
		refresh()
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		page = (page + 1) % PAGES.size()
		refresh()
		get_viewport().set_input_as_handled()

func refresh() -> void:
	if visible and runtime != null:
		_label.text = build_text(runtime, page, focus_target)

static func build_text(rt: MirrorRuntime, page_index: int, target_id: String) -> String:
	match page_index:
		0:
			return _state_page(rt)
		1:
			return _log_page(rt)
	return _explain_page(rt, target_id)

static func _state_page(rt: MirrorRuntime) -> String:
	var e := rt.engine
	var lines: Array[String] = ["[STATE]  t=%d  events=%d  catalog %s" % [e.get_time(), e.event_store.size(), e.catalog_fingerprint.left(8)]]
	lines.append("Tomas expects: %s   stance: %s" % [Expectation.of(e, "tomas"), e.get_npc_state("tomas").get("stance", "")])
	lines.append("machine: %s" % JSON.stringify(e.get_world("machine", {})))
	lines.append("-- knowledge (player)")
	for claim in e.knowledge.all("player"):
		lines.append("  %s [%s]" % [claim["id"], _name(MirrorDomain.EpistemicStatus, int(claim["status"]))])
	lines.append("-- models (player)")
	for rule in e.models.query_rules("", "", "player"):
		lines.append("  %s [%s] %.2f" % [rule["id"], _name(MirrorDomain.ModelStatus, int(rule["status"])), float(rule["confidence"])])
	lines.append("-- hypotheses")
	for report in rt.evaluate_hypotheses():
		lines.append("  %s: %s" % [report.get("id", "?"), report.get("state", "?")])
	lines.append("-- operators: %s" % str(e.operators.all("player").map(func(o): return o["id"])))
	return "\n".join(lines)

static func _log_page(rt: MirrorRuntime) -> String:
	var lines: Array[String] = ["[LOG] last events"]
	lines.append_array(rt.describe_log(14))
	return "\n".join(lines)

static func _explain_page(rt: MirrorRuntime, target_id: String) -> String:
	if target_id.is_empty():
		return "[EXPLAIN]\nTap something to see why each option is, or is not, available."
	var lines: Array[String] = ["[EXPLAIN] target=%s" % target_id]
	for row in rt.explain_for(target_id):
		if row["available"]:
			lines.append("+ %s" % row["action_id"])
			lines.append("    SOURCE: %s -> %s" % [row["source"]["ontology"], row["source"]["target"]])
			lines.append("    BECAUSE: %s" % ", ".join(row["available_because"]))
			lines.append("    PREDICTION: %s" % (row["prediction"] if not str(row["prediction"]).is_empty() else "-"))
			lines.append("    CONTRACT: %s" % ", ".join(row["effect_contract"]))
		else:
			var why: Array[String] = []
			for reason in row["reasons"]:
				why.append("%s:%s" % [reason.get("kind", "?"), reason.get("path", reason.get("requirement", {}).get("id", reason.get("reason", "")))])
			lines.append("- %s  [%s%s]  %s" % [row["action_id"], row["state"], " LATENT" if row["latent"] else "", ", ".join(why)])
	return "\n".join(lines)

static func _name(table: Dictionary, value: int) -> String:
	for key in table.keys():
		if int(table[key]) == value:
			return str(key)
	return str(value)
