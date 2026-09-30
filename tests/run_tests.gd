extends SceneTree

# Headless suite runner.
#   godot --headless --path . --script res://tests/run_tests.gd [-- filter]
# Discovers tests/**/test_*.gd, runs every `test_*` method, and prints a final
# machine-checkable summary line. tests/run_tests.sh additionally greps stderr
# for engine error markers, because Godot exits 0 even when GDScript fails to
# compile or raises a runtime SCRIPT ERROR.

const ROOT := "res://tests"

func _initialize() -> void:
	_run()

func _run() -> void:
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		filter = arg
	var files: Array[String] = []
	_collect(ROOT, files)
	files.sort()
	var total_assertions := 0
	var total_tests := 0
	var failures: Array[String] = []
	var suites := 0
	for path in files:
		if not filter.is_empty() and filter not in path:
			continue
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failures.append("[%s] failed to load/compile" % path)
			continue
		var suite = script.new()
		if not suite is TestCase:
			failures.append("[%s] does not extend TestCase" % path)
			continue
		suites += 1
		for method in suite.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total_tests += 1
			suite.begin("%s::%s" % [path.get_file(), method_name])
			var before: int = suite.assertions
			# Coroutine tests (anything that awaits Dialogue Manager, the queue, ...) must be
			# awaited, otherwise they would run only up to their first await and "pass".
			await suite.call(method_name)
			if suite.assertions == before:
				suite.failures.append("[%s::%s] made no assertions (did it finish?)" % [path.get_file(), method_name])
		total_assertions += suite.assertions
		failures.append_array(suite.failures)
	TestCase.free_tracked()
	# Dialogue Manager's autoload keeps parsed dialogue resources alive until the process ends,
	# which Godot reports as leaked resources at exit. Release it explicitly so a clean run
	# is a silent run (the release gate treats any engine ERROR line as a failure).
	var dialogue_manager := root.get_node_or_null("DialogueManager")
	if dialogue_manager != null:
		dialogue_manager.free()
	# Our own leaked Nodes must still fail the run. (Dialogue Manager 3.10.4 separately leaks
	# its parsed resource at process exit; that is the addon's, and run_tests.sh allow-lists
	# exactly that one exit-time message.)
	# In --script mode Godot counts the autoload singletons themselves as stray, so compare with
	# a baseline taken before any test ran rather than with zero.
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphan_baseline
	if orphans > 0:
		failures.append("[runner] %d Node(s) created by tests were never freed" % orphans)
	for failure in failures:
		printerr("FAIL " + failure)
	if failures.is_empty() and total_tests > 0:
		print("TESTS PASSED: %d suites, %d tests, %d assertions" % [suites, total_tests, total_assertions])
		quit(0)
	else:
		print("TESTS FAILED: %d failures (%d suites, %d tests, %d assertions)" % [failures.size(), suites, total_tests, total_assertions])
		quit(1)

func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
