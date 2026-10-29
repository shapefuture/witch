class_name ActFixtures
extends RefCounted

# Puts a game-scope runtime at any point of the story, for unit tests of one act while the acts before it are written
# in parallel (docs/design/GAME_SPEC.md section 7). Whole-act sims (data/sim) start from a new game instead and chain
# earlier sims with "after".
#
#   var r := ActFixtures.runtime_at({"story": {"act": "act3"}, "witch": {"place": "basement", "from": "shop"}},
#       {"raccoon": {"place": "with_witch"}}, ["prologue_bench_crooked"], ["op.ask_before_acting"])
#
# `world` replaces whole top-level keys, as an effect would; `npc_state` patches fields; `knows` lists claim ids the
# witch already holds (SUPPORTED, or a full knowledge effect dictionary); `operators` lists operator ids she has.
static func runtime_at(world: Dictionary = {}, npc_state: Dictionary = {}, knows: Array = [], operators: Array = []) -> MirrorRuntime:
	GameFixtures.ensure_localization()
	var r: MirrorRuntime = TestCase.track(MirrorRuntime.new())
	r.include_areas = true
	r.setup()
	for key in world.keys():
		assert(r.engine.set_world(str(key), world[key]), "could not set world %s" % key)
	for npc_id in npc_state.keys():
		var merged: Dictionary = r.engine.get_npc_state(str(npc_id)).duplicate(true)
		merged.merge(npc_state[npc_id], true)
		assert(r.engine.set_npc_state(str(npc_id), merged), "could not set npc %s" % npc_id)
	var prologue := MirrorCatalog.load_prologue(r.catalog_dir)
	var holder := {"knowledge_effects": (prologue.get("knowledge_effects", []) as Array).duplicate(true)}
	for item in knows:
		if item is Dictionary:
			holder["knowledge_effects"].append((item as Dictionary).duplicate(true))
		else:
			holder["knowledge_effects"].append({"id": str(item), "proposition": {str(item): true}, "status": "SUPPORTED", "scope": "fixture"})
	var errors: Array = []
	MirrorCatalog._normalize_effects(holder, errors, "ActFixtures")
	assert(errors.is_empty(), "ActFixtures: %s" % JSON.stringify(errors))
	var acquired: Array = (prologue.get("operator_effects", []) as Array).duplicate(true)
	for operator_id in operators:
		acquired.append({"type": "acquire", "operator_id": str(operator_id)})
	var result := r.engine.record_observation(
		str(prologue.get("observer_id", "player")), str(prologue.get("subject_id", "")),
		prologue.get("observation", {}), prologue.get("context", {}), prologue.get("evidence", []),
		holder["knowledge_effects"], prologue.get("model_effects", []), acquired)
	assert(result.get("ok", false), "ActFixtures: the starting observation failed: %s" % JSON.stringify(result))
	return r
