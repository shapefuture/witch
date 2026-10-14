# Mirror Engine hardening (branch wc/H)

Scope: `addons/mirror_engine` (1.3.1, vendored), `game/save`, the engine tests, and this note.
The save and content work below was checked against the authored catalog in `data/mirror/`, which
was not changed.

## 1. Saves

Engine save format **7** (was 6). The body carries a `checksum` field: SHA-256 over the body's
JSON, normalised by one native parse and stringify cycle so that an int and its float round trip
seal the same. It is native work, not a GDScript walk (a 13.5 MB save at 5,000 events walks in
seconds; the native path is a fraction of that).

Envelope `witch_save` version **2** (was 1). It seals its own fields and `mirror_checksum` (the
engine checksum), so the mirror body is hashed once, by the engine.

Load order: size, parse, future version, checksum, then migration, then restore. No state changes
before the checksum passes. A rejected load restores the pre-load snapshot as before.

Limits:
- `MirrorPersistence.max_save_bytes` = 64 MiB. Checked on the file length before the file is read,
  and on the text before it is parsed. A save over the limit is refused at write time too
  (`ERR_INVALID_DATA`), so no unloadable file is written. At ~2.7 KB per event this is about 20,000
  events; the event store itself caps at 100,000. Question for the coordinator: is 64 MiB the
  right ceiling for the game?

Atomic write: write `slot_N.json.tmp`, read it back and compare, copy the current slot to
`slot_N.json.bak`, rename the temp over the slot. A failed step leaves the slot as it was.
The `.bak` is not used automatically on load (no silent rollback); restoring it is a manual copy.

What the checksum does not do: it is unkeyed. A forger can recompute it. A re-sealed forgery is
refused by the event chain and the projection replay (pinned by a test). A save declared as legacy
(engine format 6, envelope version 1) carries no checksum, so a forger can strip it by downgrading
the version. Those saves still face the chain and replay. Keyed signing was rejected: any key would
ship in the client.

Format-4 bodies whose event log already holds evidence cannot be migrated: the evidence store they
would need is not in the save (refused cleanly, pinned by a test). Format 5 and 6 migrate.

## 2. Content validators

`MirrorProgressValidator` (new) is called through `MirrorValidator.validate_progress` and
`validate_player_text`. It is not part of `validate_engine`, because it explores the content and
would run on every new game. The gate runs it through `tests/mirror/test_engine_validators.gd`.

The checks explore the catalog as an abstract state machine: world state, NPC state and the
player's knowledge statuses. Every action is taken only when its preconditions and claim
requirements hold; every matching response is applied. Model and operator requirements and
once-only actions are over-approximated (treated as satisfiable), so every reported problem is real.

Mapping of the draft's rules onto this schema:

| Draft rule | Here | Status |
| --- | --- | --- |
| Reachability fixpoint | Gates are `requires_claims` (actions, responses, storylets) and `requires_evidence` (hypotheses). Each must be achieved by some explored state. | Implemented |
| Route redundancy (`critical`, `min_routes`) | The draft's `critical` flag does not exist here. Critical claims are declared by the caller (`critical_claims`). Routes are distinct actions with a knowledge effect for the claim. A single-route gate is an advisory warning. | Implemented; no claim is declared critical yet |
| Progress-safe responses (`preserves_progress`, `end_state`) | Goals (`goals`) must stay reachable: no response may make one unreachable for good. Endings are the `terminal` conditions (replacing `end_state`). An intended loss is marked by an `UNRESOLVED_BY_DESIGN` knowledge effect, the closest authored marker here; it turns the error into a warning. | Implemented |
| Progress over every gate | Not used. Success legitimately closes side branches (`go_assist` closes `machine_needs_second_component`); checking every gate flags correct design. | Deliberately narrowed to goals |
| Anti-diagnosis lint | Player-facing text (`data/text/ru.json`, values only, `_` keys skipped) must not contain engine identifiers (any token with an underscore), engine enum or ontology names, or engine vocabulary words. | Implemented, English identifiers only |
| Psychological diagnostic terms | Not ported. The draft's list is English clinical vocabulary; the game's text is Russian and a list of Russian terms needs a native-speaker review. Russian text cannot be written outside `ru.json` (the Cyrillic guard). | Not done |
| `claim_defs` (critical, discoverability modes) | No equivalent in the schema. | Skipped |

Findings on the authored catalog (reported, not changed; `data/mirror/**` is out of this branch's
write set):
- Three knowledge gates have a single evidence route: `bell_tilted_into_wind` (look_bell),
  `tomas_explained_alignment` (ask_tomas_what, which also needs Tomas not withdrawn),
  `tomas_paused_at_wand` (show_tomas_wand). Advisory warnings.
- The hall's goal `help_respected_authorship` is produced by one action (`go_assist`). If it were
  declared critical, the redundancy rule would fail. Declaring it is a design decision for the
  coordinator.
- `cast_repair.override` closes `machine_needs_second_component`, and `go_assist.component` closes
  it by succeeding. Neither closes the goal: `help_respected_authorship` stays reachable from every
  reachable state. No response destroys progress.
- Player text: zero engine identifiers or vocabulary words in `ru.json`.

Measured: 6,976 reachable abstract states, 23,760 transitions, about 3 s in headless Godot. The
analysis is capped at 20,000 states; past the cap it reports an error, never a pass.

Limits, stated plainly:
- Response-level `requires_claims` are not enforced during exploration (over-approximation).
- Minds happenings are event-driven and are not explored as transitions.
- A requirement on another holder is treated as satisfiable (or as not excluding).
- Route counting is structural (the response need not be reachable), so it can overstate redundancy.

## 3. StringName keys (spike)

No change needed. Godot 4.6.3 treats `&"a"` and `"a"` as one Dictionary key, and
`MirrorHash.canonical_json`, `sha256` and the builtin `Dictionary.hash()` give the same result for
both forms (`tests/mirror/test_engine_stringname.gd`). Every StringName in the engine is an
`@export` id that `to_definition()` converts with `str()` before the engine stores it. No golden is
affected.

## 4. Note for docs/PROVENANCE.md (not edited here)

> Hardening (branch wc/H): saves carry a checksum (engine format 7, envelope version 2) and a
> 64 MiB limit, and are written atomically with a `.bak`. Content checks for reachability, goals,
> route redundancy and player-text vocabulary live in `addons/mirror_engine/mirror_progress_validator.gd`.
> Local patch notes: `mirror_persistence.gd` (checksum, size limit, `seal`/`verify`), and
> `mirror_validator.gd` (two wrappers). See docs/engine/HARDENING.md.
