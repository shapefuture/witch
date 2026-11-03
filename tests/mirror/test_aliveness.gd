extends TestCase

# The aliveness linter (docs/design/ALIVENESS.md section 4) over the authored catalog, and the section 5 metrics
# measured from the deterministic sims. Errors fail this file. Warnings are the known gaps in data/aliveness/rules.json
# (a ratchet: a gap that closes must be deleted from that list, so it cannot quietly reopen).

func _catalog() -> Dictionary:
	return AlivenessLint.load_catalog()

func _sidecar() -> Dictionary:
	return AlivenessLint.load_sidecar()

func _rules(findings: Array) -> Array:
	var out: Array = []
	for finding in findings:
		out.append(str(finding["rule"]))
	return out

func test_the_authored_catalog_meets_the_aliveness_rules() -> void:
	var errors := AlivenessLint.errors(AlivenessLint.lint(_catalog(), _sidecar()))
	eq(errors, [], "no aliveness errors:\n" + AlivenessLint.format(errors))

func test_the_linter_catches_a_tappable_that_answers_nothing() -> void:
	var catalog := _catalog()
	catalog["actions"] = []
	catalog["minds"]["interpretations"] = []   # a poke is answered by a reading too: take those away as well
	var findings := AlivenessLint.lint(catalog, _sidecar())
	ok("answers" in _rules(AlivenessLint.errors(findings)), "with no responses, the tappable objects break rule 1 (every tap answers)")

func test_the_linter_catches_a_class_the_sidecar_does_not_know() -> void:
	var sidecar := _sidecar()
	var entries: Dictionary = sidecar["classes"]["entries"]
	var some_id := str(entries.keys()[0])
	entries[some_id] = {"class": "not_a_class"}
	var findings := AlivenessLint.lint(_catalog(), sidecar)
	ok(not AlivenessLint.errors(findings).is_empty(), "an entry in an unknown discovery class is an error")

func test_the_sims_measure_attention_return_dead_taps_and_retroactive_links() -> void:
	var targets: Array = _sidecar()["rules"]["important"]
	var metrics := AlivenessLint.sim_metrics(SimulationRunner.list_scripts(), targets)
	ok(int(metrics["taps"]) > 0, "the sims tap something (%d taps)" % int(metrics["taps"]))
	var share := float(metrics["attention_return"])
	var limits: Dictionary = _sidecar()["rules"]["metrics"]
	ok(share >= float(limits["min_attention_return"]), "attention return %.2f holds the ratchet (at least %.2f)" % [share, float(limits["min_attention_return"])])
	ok(int(metrics["dead_taps"]) <= int(limits["max_dead_taps"]), "dead taps %d hold the ratchet (at most %d)" % [int(metrics["dead_taps"]), int(limits["max_dead_taps"])])
	print("ALIVENESS taps=%d returned=%d attention_return=%.3f dead=%d retroactive=%d" % [
		int(metrics["taps"]), int(metrics["returned"]), share, int(metrics["dead_taps"]), int(metrics["retroactive"])])

func test_the_catalog_metrics_report_possibility_density_and_link_density() -> void:
	var metrics := AlivenessLint.catalog_metrics(_catalog())
	ok(int(metrics["tappables"]) > 0, "the catalog has things to tap (%d)" % int(metrics["tappables"]))
	eq(int(metrics["possibility_density"]), (metrics["with_two_responses"] as Array).size(), "possibility density counts the tappables with two responses")
	ok(float(metrics["possibility_share"]) >= 0.0 and float(metrics["possibility_share"]) <= 1.0, "possibility share is a share")
	eq(int(metrics["links"]) > 0, true, "the catalog has authored edges between entities")
	eq(float(metrics["link_density"]), float(metrics["links"]) / maxf(1.0, float(metrics["entities"])), "link density is edges per entity")

func test_a_selection_interleaves_the_discovery_classes_round_robin() -> void:
	var classes := {"a1": "humour", "a2": "humour", "b1": "curiosity", "c1": "lore", "c2": "lore", "x": ""}
	var out := DiscoveryClasses.interleave(["a1", "a2", "b1", "c1", "c2", "x"], func(id: String) -> String: return classes[id])
	eq(out, ["a1", "b1", "c1", "x", "a2", "c2"], "one of each class in turn, the unclassed one last in each round, each class in its own order")
	eq(DiscoveryClasses.interleave([], func(id: String) -> String: return id), [], "an empty selection stays empty")
