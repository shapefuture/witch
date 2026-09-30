# Debugging

Everything below is runnable on a machine with Godot 4.6.3. Set `GODOT` to the binary.

## The gate

```sh
GODOT=/path/to/godot ./tests/run_tests.sh            # import + suite + render regression
./tests/run_tests.sh sim                              # only suites whose path contains "sim"
SKIP_RENDER=1 ./tests/run_tests.sh                    # headless only
UPDATE_GOLDEN=1 ./tests/run_tests.sh golden           # accept an intentional behaviour change
```

The gate exists because **Godot exits 0 even when GDScript fails to compile**. It therefore
fails on any `SCRIPT ERROR` / `Parse Error` / `ERROR:` line and on a missing
`TESTS PASSED:` line, not on the exit code. It allow-lists exactly two Dialogue Manager shutdown
messages (see `PROVENANCE.md`). New `class_name`s need the import stage (the script runs it).

Two project rules worth knowing before you write code: `var x := something_returning_Variant`
is a **compile error** here (use an explicit type), and never give `%` an Array operand.

## Simulate without input

```sh
godot --headless --path . -- --debug-sim data/sim/patient_no_bell.json   # one script
godot --headless --path . -- --debug-sim                                  # all of them
```
Prints numbered `EVENT` lines (including each *prediction missed*), then the resulting Mirror
State: knowledge, models (with status and confidence), relationships, predictions, operators and
the chain head. Exits non-zero if a step is refused or an expectation fails. Two runs with the
same script print the same head hash; diff two transcripts to see where playthroughs diverge.

## Look at it

```sh
xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 -- \
    --capture out.png --capture-frames 90 [--sim-first impulsive_recovery] [--show-options tomas] [--magic 1.0]
```
Godot's headless mode uses a dummy renderer that **does not compile shaders**, so shader errors
only appear when really rendering. `tests/render/render_check.sh` does the above for three
scenarios and checks pixels (see `GAUNTLET.md`).

## In the game (F3)

The Mirror inspector (`debug_overlay` action). **Tab** cycles pages:

- **STATE**: Tomas's expectation and stance, every claim with its status, every model with
  status and confidence, hypothesis states, operators.
- **LOG**: the canonical event log, human-readable.
- **EXPLAIN** ("Explain Why"): tap something, then read, per action, `SOURCE`, `BECAUSE`,
  `PREDICTION`, `CONTRACT` for available ones and the failing reasons (with `LATENT` marking
  options hidden only by missing knowledge) for the rest.

## Text

```sh
python3 tools/text_tool.py check        # missing/unused keys, empty text, Russian outside the table
python3 tools/text_tool.py sort         # canonical order
python3 tools/text_tool.py export-csv out.csv ; python3 tools/text_tool.py import-csv out.csv
```

## Performance

`godot --headless --path . --script res://tools/perf_probe.gd`

## Mirror reasons you will meet

`action_unavailable` (see `details.reasons`), `evidence_conflict` (a fixed evidence id fired
twice: omit the id), `idempotency_key_conflict`, `catalog_fingerprint_mismatch` (a locked
catalog was edited, or a save was made with different content), `projection_mismatch` (a save
whose stored state disagrees with replaying its own log).
