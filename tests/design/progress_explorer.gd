class_name ProgressExplorer
extends RefCounted

# A bounded breadth-first search over the real engine, for the no-softlock invariant (C18). From a state, every action
# and storylet whose preconditions hold is committed in turn. The engine's own transactional snapshot (the one a failed
# commit rolls back to) returns the search to the state between branches, and a state is rebuilt by replaying the steps
# that reached it.
#
# States are deduplicated by what can gate a transition: the world and NPC paths that some condition reads (the exit's
# own paths included), the gating claims, operators and models of the holders that gate, and the clock when a condition
# reads it. Anything nothing reads is left out, so two states that differ only in it behave alike. The once-only memory is
# left out too (INCLUDE_ONCE, below): an action consumed once still counts as available.
#
# explore() classifies the states it reaches:
#   exit       the exit condition holds, and the search does not go on from there;
#   expanded   every successor was computed;
#   frontier   discovered but not expanded (cut by the depth bound or the expansion bound): nothing is known about it;
#   violation  an expanded state that is not an exit, from which no exit is reachable through the explored edges and
#              that reaches no frontier state: every state it can reach was expanded and none is an exit (a soft-lock).
# Because the successors are over-approximated (once-only actions stay available), a violation is real, while a pass
# does not rule out a soft-lock caused by a consumed once-only action.

const PLAYER := "player"
const INCLUDE_ONCE := false
const BOOKKEEPING := ["transaction:", "request:", "request_fingerprint:", "__event_count"]

# Returns {"error", "states", "expanded", "exits", "frontier", "edges", "violations", "exit_path", "exit_steps"}:
# `violations` lists the paths (names) to soft-locked states, `exit_path` the names on the path to the first exit found,
# and `exit_steps` the same path as steps that replay() can run. The engine is left in the state it started from.
static func explore(runtime: MirrorRuntime, exit_condition: Dictionary, max_depth: int = 12, max_expansions: int = 400) -> Dictionary:
	var engine: MirrorEngine = runtime.engine
	var gating := gating_of(engine, exit_condition)
	var root: Dictionary = engine._snapshot()
	var nodes: Array = []
	var index: Dictionary = {}
	var edges: Array = []
	var queue: Array = []
	var error := ""
	nodes.append({"path": [], "depth": 0, "exit": _exit(runtime, exit_condition), "expanded": false})
	index[_key(runtime, gating)] = 0
	if not bool(nodes[0]["exit"]):
		queue.append(0)
	var cursor := 0
	while cursor < queue.size() and cursor < max_expansions and error.is_empty():
		var id: int = queue[cursor]
		cursor += 1
		var node: Dictionary = nodes[id]
		engine._restore_snapshot(root)
		error = replay(runtime, node["path"])
		if not error.is_empty():
			break
		var before: Dictionary = engine._snapshot()
		var context: Dictionary = runtime.context_snapshot()
		for step: Dictionary in _candidates(runtime, context):
			var result: Dictionary = _apply(runtime, step, context)
			if bool(result.get("ok", false)):
				var key := _key(runtime, gating)
				if not index.has(key):
					var depth := int(node["depth"]) + 1
					var exit_here := _exit(runtime, exit_condition)
					var path: Array = node["path"].duplicate()
					path.append(step)
					index[key] = nodes.size()
					nodes.append({"path": path, "depth": depth, "exit": exit_here, "expanded": false})
					if not exit_here and depth < max_depth:
						queue.append(index[key])
				edges.append([id, index[key]])
			engine._restore_snapshot(before)
		node["expanded"] = true
	engine._restore_snapshot(root)
	return _analyse(nodes, edges, cursor, error)

# Runs steps from the engine's current state. Returns "" when every step commits, else the step that was refused.
static func replay(runtime: MirrorRuntime, path: Array) -> String:
	for step: Dictionary in path:
		var result: Dictionary = _apply(runtime, step, runtime.context_snapshot())
		if not bool(result.get("ok", false)):
			return "refused at %s" % _name(step)
	return ""

# A depth-first search for one path to an exit: a witness that the exit is reachable at all. It uses the same successors
# and dedupe as explore(), but goes deep before it goes wide, so it reaches a far exit that a bounded breadth-first search
# does not. Returns the steps of the path (replayable from the engine's starting state), or [] when none is found. The
# soft-lock analysis does not use it: it proves no violation, only that the exit can be reached.
static func find_exit(runtime: MirrorRuntime, exit_condition: Dictionary, max_depth: int = 60, max_expansions: int = 3000) -> Array:
	var engine: MirrorEngine = runtime.engine
	var gating := gating_of(engine, exit_condition)
	var root: Dictionary = engine._snapshot()
	var seen: Dictionary = {_key(runtime, gating): true}
	var budget: Array = [max_expansions]
	var found := _dive(runtime, gating, exit_condition, [], max_depth, seen, budget)
	engine._restore_snapshot(root)
	return found

static func _dive(runtime: MirrorRuntime, gating: Dictionary, exit_condition: Dictionary, path: Array, depth_left: int, seen: Dictionary, budget: Array) -> Array:
	if depth_left <= 0 or int(budget[0]) <= 0:
		return []
	budget[0] = int(budget[0]) - 1
	var engine: MirrorEngine = runtime.engine
	var before: Dictionary = engine._snapshot()
	var context: Dictionary = runtime.context_snapshot()
	for step: Dictionary in _candidates(runtime, context):
		var result: Dictionary = _apply(runtime, step, context)
		if bool(result.get("ok", false)):
			var extended: Array = path.duplicate()
			extended.append(step)
			if _exit(runtime, exit_condition):
				return extended
			var key := _key(runtime, gating)
			if not seen.has(key):
				seen[key] = true
				var deeper := _dive(runtime, gating, exit_condition, extended, depth_left - 1, seen, budget)
				if not deeper.is_empty():
					return deeper
		engine._restore_snapshot(before)
	return []

static func _analyse(nodes: Array, edges: Array, expansions: int, error: String) -> Dictionary:
	var count := nodes.size()
	var incoming: Array = []
	incoming.resize(count)
	for i in count:
		incoming[i] = []
	for edge: Array in edges:
		incoming[int(edge[1])].append(int(edge[0]))
	var exit_seeds: Array = []
	var frontier_seeds: Array = []
	var exits := 0
	var frontier := 0
	for i in count:
		var node: Dictionary = nodes[i]
		if bool(node["exit"]):
			exit_seeds.append(i)
			exits += 1
		elif not bool(node["expanded"]):
			frontier_seeds.append(i)
			frontier += 1
	var reaches_exit := _reaching(incoming, exit_seeds)
	var unknown := _reaching(incoming, frontier_seeds)
	var violations: Array = []
	for i in count:
		var node: Dictionary = nodes[i]
		if bool(node["expanded"]) and not bool(node["exit"]) and not reaches_exit.has(i) and not unknown.has(i):
			violations.append(_describe(node["path"]))
	var exit_path: Array = []
	var exit_steps: Array = []
	for node: Dictionary in nodes:
		if bool(node["exit"]):
			exit_path = _describe(node["path"])
			exit_steps = node["path"]
			break
	return {"error": error, "states": count, "expanded": expansions, "exits": exits, "frontier": frontier, "edges": edges.size(), "violations": violations, "exit_path": exit_path, "exit_steps": exit_steps}

# Every state that reaches one of the seeds, by a backward search over the explored edges.
static func _reaching(incoming: Array, seeds: Array) -> Dictionary:
	var seen: Dictionary = {}
	var stack: Array = []
	for seed in seeds:
		seen[seed] = true
		stack.append(seed)
	while not stack.is_empty():
		var at: int = stack.pop_back()
		for previous in incoming[at]:
			if not seen.has(previous):
				seen[previous] = true
				stack.append(previous)
	return seen

# The steps whose preconditions hold here, in a fixed order: actions by id (one per valid target), then the storylets
# the game would select now. The engine still decides whether each one commits.
static func _candidates(runtime: MirrorRuntime, context: Dictionary) -> Array:
	var engine: MirrorEngine = runtime.engine
	var out: Array = []
	var action_ids: Array = engine.action_definitions.keys()
	action_ids.sort()
	for action_id in action_ids:
		var definition: Dictionary = engine.action_definitions[action_id]
		if not MirrorConditions.matches(definition.get("preconditions", {}), context):
			continue
		var targets: Array = definition.get("valid_targets", [])
		if targets.is_empty():
			targets = [""]
		for target in targets:
			out.append({"kind": "action", "id": str(action_id), "target": str(target)})
	for storylet in engine.select_storylets(context, PLAYER):
		out.append({"kind": "storylet", "id": str(storylet.get("id", "")), "target": ""})
	return out

static func _apply(runtime: MirrorRuntime, step: Dictionary, context: Dictionary) -> Dictionary:
	if str(step["kind"]) == "storylet":
		return runtime.engine.consume_storylet(str(step["id"]), PLAYER, context)
	return runtime.resolve_now(runtime.make_action(str(step["id"]), str(step["target"])))

static func _exit(runtime: MirrorRuntime, condition: Dictionary) -> bool:
	return MirrorConditions.matches(condition, runtime.context_snapshot())

# What can gate a transition: the paths the conditions read, the (holder, claim) pairs, the (holder, operator) pairs and
# the observers whose models are read. Action-level requirements are held by the actor (the player); response
# requirements by the action's target, unless a requirement names its holder (docs/design/GAME_SPEC.md section 5).
static func gating_of(engine: MirrorEngine, exit_condition: Dictionary) -> Dictionary:
	var paths: Dictionary = {}
	var claims: Dictionary = {}
	var operators: Dictionary = {}
	var observers: Dictionary = {PLAYER: true}
	_paths_in(exit_condition, paths)
	for action_id in engine.action_definitions.keys():
		var definition: Dictionary = engine.action_definitions[action_id]
		_paths_in(definition.get("preconditions", {}), paths)
		_collect(definition, PLAYER, claims, operators, observers)
		var targets: Array = definition.get("valid_targets", [])
		if targets.is_empty():
			targets = [""]
		for target in targets:
			var holder := str(target) if not str(target).is_empty() else PLAYER
			for response: Dictionary in definition.get("response_contracts", []):
				_paths_in(response.get("when", {}), paths)
				_collect(response, holder, claims, operators, observers)
	for storylet_id in engine.storylet_definitions.keys():
		var storylet: Dictionary = engine.storylet_definitions[storylet_id]
		_paths_in(storylet.get("preconditions", {}), paths)
		_collect(storylet, PLAYER, claims, operators, observers)
	var sorted_paths: Array = paths.keys()
	sorted_paths.sort()
	return {"paths": sorted_paths, "claims": claims.values(), "operators": operators.values(), "observers": observers.keys()}

# The dotted paths a condition reads (its keys, at any depth; the operators such as $in are not paths).
static func _paths_in(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		for key in node.keys():
			var text := str(key)
			if text.contains(".") and not text.begins_with("$"):
				out[text] = true
			_paths_in(node[key], out)
	elif node is Array:
		for item in node:
			_paths_in(item, out)

static func _collect(source: Dictionary, default_holder: String, claims: Dictionary, operators: Dictionary, observers: Dictionary) -> void:
	for field in ["requires_claims", "excludes_claims"]:
		for requirement in source.get(field, []):
			var holder := default_holder
			var claim_id := str(requirement)
			if requirement is Dictionary:
				holder = str(requirement.get("holder_id", default_holder))
				claim_id = str(requirement.get("id", ""))
			if not claim_id.is_empty():
				claims["%s|%s" % [holder, claim_id]] = [holder, claim_id]
	for requirement in source.get("requires_operators", []):
		var holder := default_holder
		var operator_id := str(requirement)
		if requirement is Dictionary:
			holder = str(requirement.get("observer_id", default_holder))
			operator_id = str(requirement.get("id", ""))
		if not operator_id.is_empty():
			operators["%s|%s" % [holder, operator_id]] = [holder, operator_id]
	for requirement in source.get("requires_models", []):
		var observer := default_holder
		if requirement is Dictionary:
			observer = str(requirement.get("observer_id", default_holder))
		observers[observer] = true

# The state the search deduplicates on: the gating part of the state, as text, hashed.
static func _key(runtime: MirrorRuntime, gating: Dictionary) -> String:
	var engine: MirrorEngine = runtime.engine
	var context: Dictionary = runtime.context_snapshot()
	var parts: Array = []
	for path in gating["paths"]:
		parts.append("%s=%s" % [path, JSON.stringify(MirrorConditions.read_path(context, str(path)))])
	for pair: Array in gating["claims"]:
		var claim: Dictionary = engine.knowledge.get_claim(str(pair[1]), str(pair[0]))
		var status := str(int(claim["status"])) if not claim.is_empty() else "-"
		parts.append("claim %s|%s=%s" % [pair[0], pair[1], status])
	for pair: Array in gating["operators"]:
		parts.append("operator %s|%s=%s" % [pair[0], pair[1], engine.operators.has(str(pair[1]), str(pair[0]))])
	for observer in gating["observers"]:
		for rule: Dictionary in engine.models.query_rules("", "", str(observer)):
			parts.append("model %s|%s=%s" % [observer, rule.get("id", ""), rule.get("status", "")])
	if INCLUDE_ONCE:
		var once: Array = []
		for memory_key in engine.action_memory.keys():
			if not _bookkeeping(str(memory_key)):
				once.append(str(memory_key))
		once.sort()
		parts.append("once " + ",".join(PackedStringArray(once)))
	return "\n".join(PackedStringArray(parts)).sha256_text()

static func _bookkeeping(memory_key: String) -> bool:
	for prefix in BOOKKEEPING:
		if memory_key.begins_with(str(prefix)):
			return true
	return false

static func _name(step: Dictionary) -> String:
	if str(step["kind"]) == "storylet":
		return "storylet %s" % str(step["id"])
	return "action %s/%s" % [str(step["id"]), str(step["target"])]

static func _describe(path: Array) -> Array:
	var out: Array = []
	for step: Dictionary in path:
		out.append(_name(step))
	return out
