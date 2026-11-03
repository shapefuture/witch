extends TestCase

# Act II's whole route (data/sim_pending/act2_main.json; the integrator moves it into data/sim). Its "after" chain needs
# the act I sim, which is not in this worktree, so the test reads the file itself and plays the act's own steps from the
# act's starting state (ActFixtures). Chained sims are verified whole at integration.

func test_the_act_two_route_reaches_the_trapdoor_and_its_expectations() -> void:
	var script: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim_pending/act2_main.json"))
	ok(not script.is_empty(), "the act's sim parses")
	var r := ActFixtures.runtime_at({"story": {"act": "act2"}, "witch": {"place": "shop", "from": ""}, "magic": {"state": "failing"}})
	var outcome := SimulationRunner.new().run(r, script)
	ok(outcome["ok"], "the route plays and its expectations hold (failed step %d, %s)" % [outcome["failed_step"], str(outcome["expect_failures"])])
	eq(r.engine.get_world("story", {}).get("act", ""), "act3", "the act ends at the trapdoor")

func test_the_route_is_deterministic() -> void:
	var script: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim_pending/act2_main.json"))
	var first := ActFixtures.runtime_at({"story": {"act": "act2"}, "witch": {"place": "shop", "from": ""}, "magic": {"state": "failing"}})
	var second := ActFixtures.runtime_at({"story": {"act": "act2"}, "witch": {"place": "shop", "from": ""}, "magic": {"state": "failing"}})
	SimulationRunner.new().run(first, script)
	SimulationRunner.new().run(second, script)
	eq(first.engine.event_store.head_hash(), second.engine.event_store.head_hash(), "the same steps make the same event chain")
