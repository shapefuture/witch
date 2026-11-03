class_name NotebookPresenter
extends Node

# The `notebook` presentation step (GAME_SPEC section 4): opens the witch's notebook at the page that shows the claim
# the step names (or the first page), and holds the presentation until she closes it. What she holds comes from Mirror;
# the kinds and note keys come from the sidecars (data/notebook); the discovery classes from the aliveness sidecar.

signal finished

# Where the sidecars are read from (a test may point it at a fixture).
var sidecar_dir := NotebookView.DIR
# The runtime whose player holds the claims, read when the step plays.
var runtime_provider: Callable

var _slab: NotebookSlab
var _claims: Dictionary = {}
var _classes: Dictionary = {}
var _loaded := false

func play_entry(entry: Dictionary) -> void:
	var runtime: MirrorRuntime = runtime_provider.call() if runtime_provider.is_valid() else null
	if runtime == null or runtime.engine == null:
		push_warning("NotebookPresenter: no Mirror runtime to read the notebook from")
		return
	_load_sidecars()
	var page_list := NotebookView.pages(NotebookView.entries(runtime.engine, _classes, _claims))
	var box := _slab_node()
	box.camera = get_viewport().get_camera_3d()
	box.open(page_list, NotebookView.page_of(page_list, str(entry.get("claim", ""))))
	await box.closed
	finished.emit()

func _slab_node() -> NotebookSlab:
	if _slab == null:
		_slab = NotebookSlab.new()
		_slab.name = "Notebook"
		add_child(_slab)
	return _slab

func _load_sidecars() -> void:
	if _loaded:
		return
	_loaded = true
	var loaded: Dictionary = NotebookView.load_claims(sidecar_dir)
	_claims = loaded["claims"]
	for error in loaded["errors"]:
		push_warning("notebook sidecar: %s" % str(error))
	_classes = NotebookView.discovery_classes()
