# CLAUDE.md

## Project

**Witch You Were Here**: a third-person PSX diorama adventure. Knowledge, prediction,
discrepancy, relationships and model revision *are* the gameplay. Godot **4.6.3**, **Compatibility**
renderer (mobile first), Jolt, 480x360 base viewport with stretch `viewport` + `expand` (360 rows on
every screen, wider as the aspect grows). The game is **Russian-only**.

Forked from YAKO (first-person walking game); YAKO is now infrastructure, not a template. See
`docs/PROVENANCE.md`. Start with `docs/ARCHITECTURE.md` and `docs/DESIGN_INVARIANTS.md`.

> YAKO owns presentation mechanics. **Mirror owns meaning.** Scenes, NPCs, dialogue and UI never
> hold game truth: they submit actions to the `Mirror` autoload and present committed results.

## Commands

```sh
GODOT=/path/to/godot ./tests/run_tests.sh        # the gate: import + suite + render regression
./tests/run_tests.sh <path-substring>            # one area
UPDATE_GOLDEN=1 ./tests/run_tests.sh golden      # accept intended behaviour change (review the diff)
godot --headless --path . -- --debug-sim [data/sim/x.json]   # deterministic transcript
python3 tools/text_tool.py check                 # text table consistency
godot --headless --path . --script res://tools/perf_probe.gd
# the art: scripted in Blender (pip install bpy), committed as GLB; rebuild only when the art changes
python tools/blender/build_hall.py --out assets/archive --samples 96   # ~40 s, then run the gate
GODOT=... tools/visual_gauntlet/capture.sh out_dir                      # the standard frames for a critic
# image/video/audio generation (Higgsfield): estimate first, every run is capped by --max-usd
python tools/higgsfield/hf.py run <model-path> --args-file job.json --max-usd 1   # see tools/higgsfield/README.md
python tools/higgsfield/hf.py catalog        # refresh tools/higgsfield/catalog/CATALOG.md (models, inputs, prices, docs)
```
`.env.local` (git-ignored) holds `HF_KEY=key-id:key-secret`. Never print it, commit it or copy it into another file.
Run the gate before committing. **Godot exits 0 even when GDScript fails to compile**: never trust an
exit code; the gate greps for `SCRIPT ERROR` / `Parse Error` / `ERROR:` and requires `TESTS PASSED`.
New `class_name`s need `--import` first (the gate does it). Real rendering (screenshots, shader
errors) needs `xvfb-run` with `--rendering-method gl_compatibility`; headless uses a dummy renderer
that does not compile shaders. See `docs/DEBUGGING.md`.

## Art rules (see `docs/ART_PIPELINE.md`)

- The first scene is the **archive hall** (`game/world/archive/`), built from the user's reference
  still: faceted, mottled, olive-and-purple, one shaft of light. **Do not invent a different scene.**
  Its Mirror room id is still `"clearing"` (ids are data; looks are not).
- The hall is **pre-rendered plates** (Cycles, `tools/blender/build_plates.py`, see `docs/art/plates.md` and
  `docs/art/PLATE_CONTRACT.md`) projected onto a low-poly proxy so actors are occluded correctly; Godot draws only
  what moves. There are no Godot lights. Shaders write display-referred colour (Compatibility does not sRGB-encode).
  Characters are real skinned models (`tools/characters/`, `assets/characters/`, loaded by `game/world/character_models.gd`).
- **No 2D UI.** Speech bubbles, option plaques and the pause menu are 3D slabs (`game/ui/`, `Diegetic`).
- The camera is **bolted** (never follows); shot changes are cuts; only the spell eases (fisheye + 45 degrees).
- Mobile budgets are tests: <= 60k static triangles, <= 28 surfaces, painted tiles <= 256 px.

## Rules that are enforced by tests

- **All player-visible text is in `data/text/ru.json`** and nowhere else. Catalog, code and
  `.dialogue` files reference keys (`tr("ui.paused")`, `label_key`, a dialogue line that *is* a
  key). No Cyrillic in any other file: `tests/mirror/test_text_single_source.gd`.
- **The Mirror catalog (`data/mirror/`) contains ids and keys, never prose**, so rewording never
  changes the fingerprint saves are bound to.
- The action ontology (LOOK/ASK/SHOW/WAIT/GO/CAST) is never shown to the player.
- Dialogue reads Mirror and never writes it; choices are recorded as `DIALOGUE_CHOICE` actions.
- Touch and mouse produce the same `PlayerIntent` (emulated-mouse duplicates of a touch are ignored).
- Every authored action/response must load with **zero errors and zero warnings**.

## Code conventions

- GDScript, static typing. **`var x := <Variant-returning call>` is a compile error here**
  (warning-as-error): write `var x: Dictionary = ...`. Don't pass an Array as the right operand of `%`.
- **Tabs** in `game/`, `autoload/`, `render/`, `tests/`. `addons/mirror_engine` uses 4 spaces (vendored).
- Comments only where the reason is non-obvious; code and docs in English.
- One responsibility per script; no cross-imports into scene internals. Decide in Mirror,
  present in `game/`.
- Don't use `get`, `get_path`, etc. as static method names on a GDScript class: they shadow
  built-ins and become uncallable from outside (this bit the engine twice).
- Evidence ids in repeatable actions must be omitted (auto-generated); fixed ids conflict on the
  second firing. The loader rejects them.
- Autoloads, in order: `Localization`, `SettingsState`, `SceneManager`, `DialogueManager`, `Mirror`.

## Layout

`addons/mirror_engine` (engine, locally patched: see PROVENANCE) . `addons/dialogue_manager`
(unmodified) . `autoload/` . `game/{mirror,interaction,npc,dialogue,world,player,camera,presentation,ui,save,debug,main}`
(`game/world/archive` is the hall, `game/ui` the diegetic UI) . `data/{mirror,text,conversations,sim}`
. `render/psx` (shaders, StageLight) . `assets/archive` (baked set, tiles, anchors) . `tools/blender`
(the art kit) . `tools/visual_gauntlet` . `tests/` (+ `tests/golden`) . `docs/` (+ `docs/visual-gauntlet`).

## Input

`pause` (Esc) and `debug_overlay` (F3: Mirror inspector; Tab changes page). Gameplay is pointer
only: tap/click the ground to walk, an object to get its options. No WASD.

## Known caveats

- `Scenes/` holds stale YAKO scripts, quarantined by `Scenes/.gdignore`. Delete with `git rm -r Scenes`.
- Dialogue Manager 3.10.4 leaks its resource at process exit; the gate allow-lists exactly those two messages.
- `.uid` files are git-ignored (repo convention); the addon's were force-tracked by PR #1.
- `pixel.ttf` provenance/licence isn't recorded: confirm before shipping.
- The witch, Tomas and the raccoon are real models; the primitives in `game/world/placeholders.gd` remain only as a
  fallback when a GLB is missing. The shadow, the second (antler) witch and the unhooded woman are built but not yet
  placed in a scene.
- The reference image the user supplied is NOT in the repo (it reached the session inline; I did not commit
  someone's artwork without being asked). Put it at `docs/visual-gauntlet/bar/reference_hall.png` and
  `blind_ab.py` + `metrics.py` compare against the real thing; `visual-gauntlet/BAR.md` holds the numbers
  measured from it (low key: median luma 0.16, 99th percentile 0.63, saturation 0.58). Judge frames against
  the image, never a description: three rounds were wasted on a description that was wrong.
- bmesh reuses freed slots and `recalc_face_normals` re-guesses winding on loose triangles: both bit
  the Blender kit (vertex creation order is stored on the vertices, not in a list of wrappers); read the
  notes in `tools/blender/kit/common.py` before changing it. The floor and the carpet inlay are drawn
  unsnapped (`snap_amount`) because coplanar surfaces snapped differently shear into shards.
- The export preset includes `data/*` (JSON and `.dialogue` are not Godot resources, so they would otherwise be missing from a build).

## Not built yet (by design)

Raccoon tele-somatic signal, Vera/Elian/Ilya, the town graph, LimboAI, a world compiler from
place resources, on-device mobile profiling, a main menu, the full ending, the shadow/antler witch in a scene.
