extends TestCase

func test_condition_operators() -> void:
	var ctx := {"a": {"b": 3}, "tags": ["x", "y"], "name": "tomas", "flag": true}
	ok(MirrorConditions.matches({"a.b": 3}, ctx), "dotted equality")
	ok(MirrorConditions.matches({"$gt": {"a.b": 2}}, ctx), "gt")
	ok(not MirrorConditions.matches({"$gt": {"a.b": 3}}, ctx), "gt strict")
	ok(MirrorConditions.matches({"$gte": {"a.b": 3}}, ctx), "gte")
	ok(MirrorConditions.matches({"$in": {"name": ["tomas", "vera"]}}, ctx), "in")
	ok(MirrorConditions.matches({"$nin": {"name": ["vera"]}}, ctx), "nin")
	ok(MirrorConditions.matches({"$contains": {"tags": "x"}}, ctx), "contains")
	ok(MirrorConditions.matches({"$exists": {"a.b": true, "nope": false}}, ctx), "exists")
	ok(MirrorConditions.matches({"$not": {"flag": false}}, ctx), "not")
	ok(MirrorConditions.matches({"$any": [{"flag": false}, {"name": "tomas"}]}, ctx), "any")
	ok(not MirrorConditions.matches({"$all": [{"flag": true}, {"name": "vera"}]}, ctx), "all")
	ok(MirrorConditions.matches({}, ctx), "empty requirement always matches")

func test_incomparable_types_are_unequal_not_errors() -> void:
	ok(not MirrorConditions.matches({"flag": {"x": 1}}, {"flag": true}), "bool vs dict")
	ok(not MirrorConditions.matches({"$gt": {"name": 3}}, {"name": "tomas"}), "string vs int ordering")

func test_validation_reports_malformed_conditions() -> void:
	ok(MirrorConditions.validate({"$bogus": {}}).size() > 0, "unknown operator")
	ok(MirrorConditions.validate({"$eq": true}).size() > 0, "operator needs dictionary")
	ok(MirrorConditions.validate({"$all": {}}).size() > 0, "all needs array")
	eq(MirrorConditions.validate({"$eq": {"a": 1}}).size(), 0, "well formed")

func test_explain_failures_never_truncates_on_malformed_operator() -> void:
	var failures := MirrorConditions.explain_failures({"$eq": true, "a": 1}, {"a": 2})
	ok(failures.size() >= 2, "both the malformed operator and the equality failure are reported")

func test_planner_finds_shortest_plan_respecting_gates() -> void:
	var p := MirrorPlanner.new()
	var actions := [
		{"id": "open", "preconditions": {"door": "closed"}, "effects": {"door": "open"}},
		{"id": "enter", "preconditions": {"door": "open"}, "effects": {"inside": true}},
	]
	var plan := p.find_plan({"door": "closed"}, actions, {"inside": true}, 3)
	ok(plan["found"], "found")
	eq(plan["plan"], ["open", "enter"], "order")
	ok(not p.find_plan({"door": "locked"}, actions, {"inside": true}, 3)["found"], "no plan when gated")
	ok(not p.find_plan({"door": "closed"}, actions, {"inside": true}, 1)["found"], "depth limit respected")

func test_planner_explains_unavailability() -> void:
	var p := MirrorPlanner.new()
	var report := p.explain_unavailable({"door": "locked"}, [{"id": "open", "preconditions": {"door": "closed"}, "requires_claims": ["key"]}], MirrorKnowledgeStore.new())
	eq(report[0]["available"], false, "unavailable")
	var kinds: Array = report[0]["reasons"].map(func(r): return r["kind"])
	in_array("state", kinds, "state reason")
	in_array("knowledge", kinds, "knowledge reason")

func test_read_path_is_callable_from_outside_the_class() -> void:
	# A static get_path() would have been shadowed by Resource.get_path() and uncallable here.
	eq(MirrorConditions.read_path({"a": {"b": 7}}, "a.b", null), 7, "nested read")
	eq(MirrorConditions.read_path({"a": 1}, "a.b", "fallback"), "fallback", "missing path returns the default")
	ok(MirrorConditions.has_path({"a": {"b": 0}}, "a.b"), "has_path sees falsy values")
