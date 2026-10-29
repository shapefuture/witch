# Content packages (contract, version 2, 2026-10-29)

Authored content is split into **area packages** so that parallel authors (people or agents) never edit the same
file. Version 1 was "one file per kind" (`world.json`, `storylets.json`, `ru.json`, ...). Version 2 keeps every
version-1 file working and adds one directory per area. `tests/mirror/test_content_packages.gd` holds the contract.

## Layout

```text
data/mirror/areas/<area>/        catalog fragments (all optional)
    world.json                   {"world": {entity: {...}}, "npc_state": {npc: {...}}}
    actions.json                 [action, ...]
    storylets.json               [storylet, ...]
    hypotheses.json              [hypothesis, ...]
    operators.json               [operator, ...]
  and Minds fragments (outside the catalog fingerprint, like data/mirror/minds/)
    minds.json                   {"places", "holders", "communities", "event_kinds", "clocks": {"cadences"},
                                  "initial_beliefs", "routines"}
    interpretations.json         [interpretation, ...]
    world_rules.json             [rule, ...]
    conventions.json             [convention, ...]
data/text/ru/<area>.json         the area's Russian lines (a flat object of key -> text)
data/conversations/<area>*.dialogue   the area's conversations (Dialogue Manager)
```

An area id is lowercase `[a-z0-9_]`. The loaders read the root files first (`data/mirror/world.json`,
`data/mirror/actions/*.json`, ..., `data/text/ru.json`), then each area in name order.

## Merge rules

| file | rule |
|---|---|
| `world.json` | entity ids in `world` and npc ids in `npc_state` are defined once across the root and all areas; a second definition is an error. Only the sections `world` and `npc_state` exist. |
| `actions.json`, `storylets.json`, `hypotheses.json`, `operators.json` | appended; the engine refuses a second registration of an id, and the loader names the file. |
| `minds.json` | `places`, `holders`, `communities`, `event_kinds` and `clocks.cadences` are keyed: each key once. `initial_beliefs` and `routines` are appended. `limits`, `attention`, `perception`, `reaction_ops` and `default_place` belong to the root `data/mirror/minds/minds.json` only. |
| `interpretations.json`, `world_rules.json`, `conventions.json` | appended; ids are unique (checked by `MindsCatalog.build`). |
| `data/text/ru/<area>.json` | a key is defined in one table file only. `Localization.load_tables()` returns duplicates; the boot reports them as errors and `tests/mirror/test_text_single_source.gd` fails on them. Keys starting with `_` are notes. |
| `*.dialogue` | a title (`~ name`) is defined in one file only (`DialogueBridge.title_index()`); a presentation step `{"kind": "dialogue", "title": ...}` finds its file by title, and may name the answering NPC with `"npc"` (default `tomas`). |

Merging never overrides. An area that needs to change something another area defined does it through the engine
(an action's `effects`), never by redefining it.

## Naming, so areas cannot collide

- Text keys: `<group>.<area>.<name>`, with the groups of `tools/text_tool.py` (`ui`, `menu`, `opt`, `obj`, `speaker`,
  `line`, `dlg`, `toy`, and `note` for notebook entries). Example: `line.act1.boots_wet`.
- Action, storylet, hypothesis, operator, rule and convention ids start with the area id: `act1_look_boots`.
- Dialogue titles start with the area id: `act1_first_love_evening`.
- World entities and npc ids that more than one area uses are defined once, in the `core` area, and listed in
  `docs/design/GAME_SPEC.md`. An area defines only the entities it alone introduces, prefixed with its id when the
  name could be generic (`act3_stairs`).

## What still holds from version 1

The catalog holds ids and text keys, never prose (`tests/mirror/test_text_single_source.gd` scans everything).
Evidence ids in repeatable actions are omitted. Every authored action and response loads with zero errors and zero
warnings. Minds data passes the four-laws linter. The catalog fingerprint covers what the engine registers, not
where a file sits, so moving content between files does not change it; changing content does.
