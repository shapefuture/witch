class_name WitnessSelector
extends RefCounted

# Who perceives an event? A pure function of the event, the people around, and the perception hints the
# scene passes in as data (distance, line of sight, attention). There is no randomness and no scene access:
# the same inputs always choose the same witnesses, in the same order, which is what lets a save, a sim and
# a replay agree.
#
# Channels (an event kind says which it emits and how far each carries):
#   sight  - needs the holder in the same place, a clear line, and eyes on the room (attention);
#   sound  - needs the same place, or an adjacent one if the sound `carries` (then it is "overheard").
# The actor of an event always perceives it ("direct"). Whoever is left is reported with a reason and learns
# nothing from this event.

const DEFAULT_ATTENTION := {
	"idle": {"sight": 100, "sound": 100},
	"attending": {"sight": 100, "sound": 100},
	"busy": {"sight": 55, "sound": 80},
	"away": {"sight": 0, "sound": 100},
	"asleep": {"sight": 0, "sound": 25},
}
const CHANNEL_ORDER := ["sight", "sound"]

# candidates: [{id, place, tags?, attention?}] (who is around, from Mirror's presence).
# config: {"attention": table, "overheard_clarity": int, "min_clarity": int, "adjacent": [places]}.
# Returns {"witnesses": [{holder, channel, clarity, attention}], "unaware": [{holder, why}]}, sorted by holder.
static func select(event: Dictionary, kind_def: Dictionary, candidates: Array, config: Dictionary = {}) -> Dictionary:
	var hints: Dictionary = event.get("hints", {})
	var table: Dictionary = config.get("attention", DEFAULT_ATTENTION)
	var min_clarity := int(config.get("min_clarity", 10))
	var overheard_clarity := int(config.get("overheard_clarity", 35))
	var adjacent: Array = config.get("adjacent", [])
	var channels: Dictionary = kind_def.get("channels", {})
	var loudness := float(hints.get("loudness", 100)) / 100.0
	var actor := str(event.get("actor", ""))
	var place := str(event.get("place", ""))
	var present: Array = hints.get("present", [])
	var absent: Array = hints.get("absent", [])
	var witnesses: Array = []
	var unaware: Array = []
	var sorted_candidates: Array = candidates.duplicate()
	sorted_candidates.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	for candidate in sorted_candidates:
		var holder := str(candidate.get("id", ""))
		var attention := str(_per_holder(hints, "attention", holder, candidate.get("attention", "idle")))
		if holder == actor:
			witnesses.append({"holder": holder, "channel": "direct", "clarity": 100, "attention": attention})
			continue
		# The scene says who is actually on stage: Mirror may know Tomas is "in the clearing" while the
		# painted hall does not show him yet. Off stage means absent from the event.
		if holder in absent or (not present.is_empty() and holder not in present):
			unaware.append({"holder": holder, "why": "off_stage"})
			continue
		var same_place := str(candidate.get("place", "")) == place
		var near_place := str(candidate.get("place", "")) in adjacent
		var distance := float(_per_holder(hints, "distance", holder, -1.0))
		var line_clear := bool(_per_holder(hints, "los", holder, true))
		var levels: Dictionary = table.get(attention, DEFAULT_ATTENTION["idle"])
		var best: Dictionary = {}
		var why := "absent"
		for channel in CHANNEL_ORDER:
			if not channels.has(channel):
				continue
			var spec: Dictionary = channels[channel]
			var reach := float(spec.get("range", 10.0)) * (loudness if channel == "sound" else 1.0)
			var carries := bool(spec.get("carries", false))
			var clarity := 0
			var channel_name: String = channel
			if same_place:
				if channel == "sight" and not line_clear:
					why = "no_line_of_sight"
					continue
				if distance >= 0.0 and distance > reach:
					why = "out_of_range"
					continue
				clarity = 100 - (0 if distance < 0.0 else int(round(60.0 * distance / maxf(reach, 0.001))))
			elif channel == "sound" and carries and near_place:
				channel_name = "overheard"
				clarity = overheard_clarity
			else:
				continue
			clarity = int(round(clarity * float(levels.get(channel, 100)) / 100.0))
			if clarity < min_clarity:
				why = "not_attending" if int(levels.get(channel, 100)) == 0 else "too_faint"
				continue
			if best.is_empty() or clarity > int(best["clarity"]):
				best = {"holder": holder, "channel": channel_name, "clarity": clarity, "attention": attention}
		if best.is_empty():
			unaware.append({"holder": holder, "why": why})
		else:
			witnesses.append(best)
	return {"witnesses": witnesses, "unaware": unaware}

# A hint may be a table keyed by holder ({"distance": {"raccoon": 2.5}}); anything missing falls back.
static func _per_holder(hints: Dictionary, key: String, holder: String, fallback: Variant) -> Variant:
	var table: Variant = hints.get(key, {})
	if table is Dictionary and table.has(holder):
		return table[holder]
	return fallback
