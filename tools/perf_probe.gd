extends SceneTree

# Measures the costs that matter for a mobile-first target, against the AUTHORED catalog:
#   godot --headless --path . --script res://tools/perf_probe.gd
# Numbers are wall-clock on the machine running it; compare runs on the same machine.
# (Rendering costs need a real GPU: see docs/PERFORMANCE.md for what to capture there.)

func _initialize() -> void:
	_run()

func _ms(start_usec: int) -> String:
	return "%.2f ms" % ((Time.get_ticks_usec() - start_usec) / 1000.0)

func _run() -> void:
	var loc: Node = load("res://autoload/Localization.gd").new()
	loc.register()
	var r := MirrorRuntime.new()
	var t := Time.get_ticks_usec()
	r.setup()
	print("catalog load + register (15 actions)   %s" % _ms(t))
	t = Time.get_ticks_usec()
	r.new_game()
	print("new_game (lock + fingerprint + prologue) %s" % _ms(t))
	t = Time.get_ticks_usec()
	var fingerprint := r.engine.compute_catalog_fingerprint()
	print("catalog fingerprint                     %s" % _ms(t))
	print("catalog size (canonical json)           %d KB" % (MirrorHash.canonical_json(r.engine._catalog()).length() / 1024))

	for step in [["ask_tomas_what", "tomas"], ["wait_watch", "tomas"], ["wait_watch", "tomas"], ["go_assist", "machine"]]:
		r.resolve_now(r.make_action(step[0], step[1]))
	var marks := [0, 100, 300, 600]
	var done := 0
	for mark in marks:
		while done < mark:
			r.resolve_now(r.make_action("wait_watch", "tomas"))
			done += 1
		t = Time.get_ticks_usec()
		r.resolve_now(r.make_action("wait_watch", "tomas"))
		done += 1
		print("resolve_action at %4d events            %s" % [r.engine.event_store.size(), _ms(t)])
	t = Time.get_ticks_usec()
	for target in ["tomas", "machine", "bell", "path_out"]:
		r.options_for(target)
	print("options_for x4 targets (%4d events)     %s" % [r.engine.event_store.size(), _ms(t)])
	t = Time.get_ticks_usec()
	r.explain_for("tomas")
	print("explain_for tomas (debug panel)         %s" % _ms(t))
	t = Time.get_ticks_usec()
	var preview := r.engine.preview_action(r.make_action("wait_watch", "tomas"))
	print("preview_action (%4d events)             %s (ok=%s)" % [r.engine.event_store.size(), _ms(t), preview.get("ok")])
	t = Time.get_ticks_usec()
	var text := SaveCodec.encode(r.engine)
	print("save encode (%4d events)                %s, %d KB" % [r.engine.event_store.size(), _ms(t), text.length() / 1024])
	var fresh := MirrorRuntime.new()
	fresh.setup()
	t = Time.get_ticks_usec()
	var loaded := SaveGame.load_text(fresh.engine, text)
	print("load (verify + replay)                  %s (ok=%s)" % [_ms(t), loaded.get("ok")])
	t = Time.get_ticks_usec()
	r.engine.audit_integrity()
	print("audit_integrity (full re-hash)          %s" % _ms(t))

	var room := ArchiveHall.new()
	root.add_child(room)
	await process_frame
	var meshes := 0
	var surfaces := 0
	var vertices := 0
	var lights := 0
	var nodes := 0
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		nodes += 1
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			meshes += 1
			var mesh := (node as MeshInstance3D).mesh
			for s in range(mesh.get_surface_count()):
				surfaces += 1
				vertices += mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
		if node is Light3D:
			lights += 1
	print("clearing: %d nodes, %d meshes, %d surfaces (~draw calls), %d vertices, %d lights" % [nodes, meshes, surfaces, vertices, lights])
	room.free()
	r.free()
	fresh.free()
	loc.free()
	quit()
