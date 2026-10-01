# Witch You Were Here

A third-person PSX diorama adventure about knowledge, expectation and what it means to help.
You are a witch. Magic works, spectacularly, and that is the problem: it can make you certain of
*what* happened while leaving you less sure of *why* anyone responded the way they did.

The game is in Russian. It is built on [YAKO](https://github.com/MournfulOx/YAKO_Demo_Godot3D)'s
PSX renderer and on the deterministic **Mirror Engine** (`addons/mirror_engine`), where
predictions, evidence, discrepancies, relationships and revisions of the player's own model are
the gameplay.

## First room: the archive hall

A gothic hall of tall shelves, an eye on the wall, a hooded statue and a single shaft of late
light on a spiral floor. A man named Tomas is arguing quietly with a brass machine. Look, ask,
show, wait, step in, or try the strange thing. Every route is valid and every wrong one is
recoverable; what changes is what you understand about helping. The hall is hand-built and
light-baked (`docs/ART_PIPELINE.md`); the characters are placeholders for now.

## Run

Godot **4.6.3**. Open the project and play `game/main/main.tscn` (the configured main scene).
Pointer only: click or tap the ground to walk, an object for its options. `Esc` pauses, `F3`
opens the developer inspector.

## Test

```sh
GODOT=/path/to/godot ./tests/run_tests.sh
```

Headless suite, golden behaviour transcripts, and (with `xvfb-run`) a render regression. See
`docs/GAUNTLET.md`. Deterministic transcripts without input:

```sh
godot --headless --path . -- --debug-sim data/sim/patient_no_bell.json
```

## Docs

`docs/ARCHITECTURE.md` . `docs/DESIGN_INVARIANTS.md` . `docs/AUTHORING.md` . `docs/GAUNTLET.md` .
`docs/DEBUGGING.md` . `docs/PERFORMANCE.md` . `docs/ART_PIPELINE.md` . `docs/PROVENANCE.md`

## Licence notes

Third-party components and their provenance are listed in `docs/PROVENANCE.md` (Dialogue Manager
is MIT; confirm `pixel.ttf` before shipping).
