extends TestCase

# Act VI's whole route (data/sim_pending/act6_main.json; the integrator moves it into data/sim). Its "after" chain needs the
# act V sim, so the test reads the file itself and plays the act's own steps from the act's starting state (ActFixtures).

func test_the_act_six_route_reaches_the_jars_and_its_expectations() -> void:
	var script: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim_pending/act6_main.json"))
	ok(not script.is_empty(), "the act's sim parses")
	var r := ActFixtures.runtime_at({"story": {"act": "act6"}, "witch": {"place": "shop", "from": ""}, "magic": {"state": "gone"}})
	var outcome := SimulationRunner.new().run(r, script)
	ok(outcome["ok"], "the route plays and its expectations hold (failed step %d, %s)" % [outcome["failed_step"], str(outcome["expect_failures"])])
	eq(r.engine.get_world("story", {}).get("act", ""), "act7", "the act ends at the jars")

func test_the_route_is_deterministic() -> void:
	var script: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim_pending/act6_main.json"))
	var first := ActFixtures.runtime_at({"story": {"act": "act6"}, "witch": {"place": "shop", "from": ""}, "magic": {"state": "gone"}})
	var second := ActFixtures.runtime_at({"story": {"act": "act6"}, "witch": {"place": "shop", "from": ""}, "magic": {"state": "gone"}})
	SimulationRunner.new().run(first, script)
	SimulationRunner.new().run(second, script)
	eq(first.engine.event_store.head_hash(), second.engine.event_store.head_hash(), "the same steps make the same event chain")
