class_name DiscoveryClasses
extends RefCounted

# Round-robin over the discovery classes (ROOM_OF_US_REVIEW item 3, room_engine): a selection takes one entry from
# each class in turn, so a room never shows five jokes in a row. Within a class the order is kept. Entries with no
# class form a class of their own, placed last in each round. The classes themselves are named in
# data/aliveness/classes.json (outside the Mirror catalog).

const UNCLASSED := "_unclassed"

static func interleave(items: Array, class_of: Callable) -> Array:
	var buckets: Dictionary = {}
	var order: Array = []
	for item in items:
		var cls := str(class_of.call(item))
		if cls.is_empty():
			cls = UNCLASSED
		if not buckets.has(cls):
			buckets[cls] = []
			order.append(cls)
		(buckets[cls] as Array).append(item)
	if order.has(UNCLASSED):
		order.erase(UNCLASSED)
		order.append(UNCLASSED)
	var out: Array = []
	var depth := 0
	while out.size() < items.size():
		for cls in order:
			var bucket: Array = buckets[cls]
			if depth < bucket.size():
				out.append(bucket[depth])
		depth += 1
	return out
