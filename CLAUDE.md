# CLAUDE.md

## Project

**Witch You Were Here**: a third-person PSX diorama adventure. Knowledge, prediction,
discrepancy, relationships and model revision *are* the gameplay. Godot **4.6.3**, Forward+,
Jolt, 320x240 viewport (stretch `viewport`). The game is **Russian-only**.

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
```
Run the gate before committing. **Godot exits 0 even when GDScript fails to compile**: never trust an
exit code; the gate greps for `SCRIPT ERROR` / `Parse Error` / `ERROR:` and requires `TESTS PASSED`.
New `class_name`s need `--import` first (the gate does it). Real rendering (screenshots, shader
errors) needs `xvfb-run` with `--rendering-method gl_compatibility`; headless uses a dummy renderer
that does not compile shaders. See `docs/DEBUGGING.md`.

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
. `data/{mirror,text,conversations,sim}` . `render/psx` . `tests/` (+ `tests/golden`) . `tools/` . `docs/`.

## Input

`pause` (Esc) and `debug_overlay` (F3: Mirror inspector; Tab changes page). Gameplay is pointer
only: tap/click the ground to walk, an object to get its options. No WASD.

## Known caveats

- `Scenes/` holds stale YAKO scripts, quarantined by `Scenes/.gdignore`. Delete with `git rm -r Scenes`.
- Dialogue Manager 3.10.4 leaks its resource at process exit; the gate allow-lists exactly those two messages.
- `.uid` files are git-ignored (repo convention); the addon's were force-tracked by PR #1.
- `pixel.ttf` provenance/licence isn't recorded: confirm before shipping.
- All 3D is placeholder primitives (`game/world/placeholders.gd`); real character models are to be supplied.
- The export preset includes `data/*` (JSON and `.dialogue` are not Godot resources, so they would otherwise be missing from a build).

## Not built yet (by design)

Raccoon tele-somatic signal, Vera/Elian/Ilya, the town graph, LimboAI, a world compiler from
place resources, mobile profile tuning, a main menu, the full ending.
