# Authoring content

Content is data. Nothing about what happens in the Clearing is in a script.

## Files

```
data/mirror/world.json        initial world + NPC state (before the catalog locks)
data/mirror/prologue.json     what the witch already believes; recorded as the first event
data/mirror/actions/*.json    arrays of action definitions
data/mirror/operators.json    learned abstractions
data/mirror/storylets.json    content selected by state (the arrival beat)
data/mirror/hypotheses.json   causal hypotheses (analysis, debug, reveal conditions)
data/mirror/minds/*.json      what the minds around the witch make of what happens (see docs/MINDS.md):
                              minds, interpretations, world_rules, conventions
data/text/ru.json             ALL player-visible text, by key
data/conversations/*.dialogue wording structure; every line is a key
data/sim/*.json               deterministic playthroughs + expectations
```

Keys starting with `_` in the two seed objects are comments. Enum fields may be written by name
(`"action_type": "LOOK"`, `"status": "SUPPORTED"`, `"type": "DIRECT"`); an unknown name is a load
error, never silently zero.

## An action

```jsonc
{
  "id": "ask_tomas_help",            // unique
  "action_type": "ASK",              // LOOK ASK SHOW WAIT GO CAST CUSTOM: hidden from the player
  "affordance_group": "social",      // ordering on screen: observe social wait act magic
  "label_key": "opt.ask_tomas_help", // the player-facing sentence, from ru.json
  "topic": "help",                   // optional: what MirrorDialogueContext.can_ask() matches
  "hidden": true,                    // system actions are never offered
  "valid_targets": ["tomas"],
  "preconditions": { "npc.tomas.invited": false },        // see "Conditions"
  "requires_claims":  [{ "id": "x", "min_status": "SUPPORTED" }],  // the WITCH must know it
  "excludes_claims":  [{ "id": "y" }],
  "requires_models":  [{ "id": "m.help_needs_authorship", "min_status": "SUPPORTED" }],
  "requires_operators": ["op.ask_before_acting"],
  "time_cost": 8, "once_key": "cast_flourish",
  "prediction_signature": ["ASK", "EXPECT_PERMISSION"],   // the EXPECT_* token is what this act "says"
  "prediction_candidates": [{ "id": "p.x", "when": {}, "expected": { "outcome": "help_accepted" } }],
  "response_contracts": [ ... ]
}
```

### Conditions

A small dictionary DSL evaluated against one context: every world key, every NPC as
`npc.<id>.<field>`, `time`, `action_id`, `actor_id`, `target_id`, plus the action's own
context. `{"machine.state": "jammed"}` is equality on a dotted path. Operators take a
dictionary of paths: `$eq $neq $in $nin $exists $contains $gt $gte $lt $lte`, and `$all $any $not`
combine. Malformed operators are reported by the catalog validator.

### A response contract

The first match by `priority` (then id) wins.

```jsonc
{
  "id": "cast_repair.override", "priority": 10,
  "when": { "npc.tomas.stance": "withdrawn" },    // context condition
  "npc_preconditions": {},                        // the TARGET NPC's own state
  "requires_claims": [{ "id": "c", "holder_id": "player" }],
  "observed": { "outcome": "repaired_by_magic", "motive": "unknown" },   // compared with the prediction
  "effects": { "world": { "machine": {"state": "running_by_magic", "in_tune": false} },   // replaces the KEY
               "npc_state": { "tomas": { "stance": "withdrawn" } } },                      // patches the fields
  "knowledge_effects": [{ "id": "machine_runs", "proposition": {...}, "status": "ESTABLISHED", "scope": "clearing" }],
  "model_effects": [{ "type": "revise", "old_rule_id": "m.a", "new_rule_id": "m.b", "proposition": {...}, "scope": "help", "subject_id": "tomas" }],
  "operator_effects": [{ "type": "acquire", "operator_id": "op.x" }],
  "evidence": [{ "type": "DIRECT", "payload": {...} }],
  "relationship_target": "tomas",                  // default: the action's target
  "relationship_tags": ["BOUNDARY"], "relationship_payload": { "domain": "...", "boundary": {...} },
  "presentation": [ ... ]
}
```

Things that have bitten before:

- **Claim and model requirements inside a response default to the NPC** (the responder), not the
  player. Write `"holder_id": "player"` / `"observer_id": "player"` to ask about the witch.
- **Never give evidence a fixed `id` in a repeatable action.** Evidence ids are immutable; the
  second firing is an `evidence_conflict`. Omit the id; the loader rejects a fixed one unless the
  action has a `once_key`.
- `effects.world` replaces the whole top-level key. Keep related fields in one object and always
  write the full object.
- Statuses: `UNRESOLVED_BY_DESIGN` is how "we will never be sure why" is recorded. `SUPPORTED`
  satisfies `POSSIBLE`; `DISCONFIRMED` satisfies nothing.

### Presentation entries

Opaque to the engine, played in order by `PresentationDirector`:

| `kind` | Fields | Effect |
|---|---|---|
| `line` | `speaker` (`narrator` = none), `key` | subtitle |
| `dialogue` | `title` | runs that title of `tomas.dialogue` |
| `camera` | `mode` (wide inspect conversation magic_reveal consequence stay), `focus` ids | composes the shot |
| `anim` | `actor`, `name` | `interact` / `cast` (witch), `pause` / `look_up` (Tomas) |
| `npc` | `actor`, `pose` | moves Tomas into a pose |
| `magic` | `effect` (repair flourish), `target` | the PSX break |
| `leave_frame` | `actor`, `via` | she walks off; pair with `camera: stay` |
| `wait` | `seconds` | pause |

An unhandled `kind` is recorded in `PresentationDirector.unhandled` and fails the flow tests.

## Text

Add the string to `data/text/ru.json` (keys are `group.name[.part]`, lowercase; groups `ui opt obj
speaker line dlg`) and reference the key. For a spoken line write the key as the line in the
`.dialogue` file: `tomas: dlg.tomas_thanks_tuned.1`. Give every *response* a static id so the
recorded choice is stable: `- dlg.x.yes [ID:dlg.x.yes]`. Run `python3 tools/text_tool.py check`.

## Workflow for a change

1. Edit the JSON / text.
2. `./tests/run_tests.sh`. Catalog and text tests catch typos, missing keys and unhandled kinds.
3. Add or adjust a script in `data/sim/` for the path you care about, with `expect`.
4. If behaviour changed on purpose: `UPDATE_GOLDEN=1 ./tests/run_tests.sh golden`, then read the
   diff of `tests/golden/*.json`: it is the most legible statement of what you just changed.

## Adding an NPC or room

An NPC is: an entry in `world.json` (`npc_state`), actions whose contracts read `npc.<id>.*`, an
`NPC` node with pose anchors in the room builder, and keys in `ru.json`. A room is a `Room`
subclass (see `Clearing`) that registers its `Interactable`s; `GameRoot` composes it.
