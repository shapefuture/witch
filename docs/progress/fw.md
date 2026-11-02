# FW workcell: places, rooms, moving, the full-game boot

Branch `worktree-agent-a4276250ea5896e14` (base 75de726). Brief: the FW section of the orchestrator's brief (write set
in that brief; GAME_SPEC section 7 row FW). Resume from this file.

## Done (committed)

- Places: `data/world/places/*.json`, the thirteen of GAME_SPEC section 2, each with a stage palette, spots and arrivals.
- Hotspots: `data/world/hotspots/core.json` (the eleven core exits; positions provisional, see Decisions).
- Loader: `game/world/places/place_data.gd`, `place_catalog.gd` (places and merged hotspots, with errors reported).
- Rooms: `place_room.gd` (the base every room extends: the room slot defaults, hotspots, people, arrival),
  `stage_room.gd` (stand-in set), `room_factory.gd` (kind from the place file; painted needs a room.json, else stand-in).
  ArchiveHall and PaintedRoom now extend PlaceRoom. PaintedRoom takes `own_input` and `skip_actors`.
- People: `game/npc/npc_presence.gd` (pure presence rule), `game/npc/npc_actor.gd` (model or crude figure).
- Arrival storylet gated by place (`data/mirror/storylets.json`, story.arrival).
- Tests: `tests/world/test_places.gd`; `tests/world/test_room_slot.gd` now sets the painted room's id as the factory does.

## Next (in order)

1. GameRoot: build the room through the factory, move the witch between places (after a commit, when witch.place
   changed), placement at arrival, presence sync, hotspot offers (Mirror options), serial presentation with storylets
   after every commit and place change, presentation fixes (line with any speaker, anim/npc for any actor, camera stay
   held, ending kind), postgame mode, main menu boot (`--demo` keeps the hall demo), save/load place, SystemsPresenters.
2. InteractionFlow (witch target, postgame options without a walk), InteractionProbe (ignore hidden hotspots).
3. Event budget: PropEvents clock commits in heartbeats (60 ticks) or when a consequence falls due (C17).
4. Tests: interaction, presence, postgame, save/load, event budget (`tests/world/test_event_budget.gd`), main menu.
5. Goldens: regenerate with UPDATE_GOLDEN for the storylet gate only; check the diff touches only fingerprints/hashes.
6. `docs/engine/PLACES.md`, the full gate.

## Decisions (FW)

- The brief's write set is followed where it is narrower than GAME_SPEC section 7 (no edits to root `data/mirror/*.json`
  beyond the storylet gate; no edits to `data/text/**`, `game/world/character_models.gd`).
- Every room is a `PlaceRoom` (a `Room`), so GameRoot and InteractionFlow keep one typed room.
- Hotspots are `Interactable` nodes in every room kind; a hotspot is offered (its pick layer on) only while Mirror
  offers an action on its target. Stand-in hotspots are boxes named `Hotspot_<target>`, displayed as `obj.<target>`.
- Painted places use the painting's own camera; the game's DioramaCamera is used for the hall and the stand-ins.
- Pixel coordinates on the stand-in: x = (px/1280 - 0.5) * 10 m, z = (py/720 - 0.5) * 6 m (toward the camera is +z).
- Core exit positions are provisional: the shop plate shows no street door and no back door; the street, garden and
  observatory positions are read from their plates or guessed (listed in data/world/hotspots/core.json's places).
- The archive's exit is the hall's `path_out` arch: a hotspot with an anchor shares the arch for `door_archive_street`.
- The painted walk's raccoon only trails a painted witch; with the game's witch it stands its ground.

## Needs from the integrator

- `data/world/hotspots/core.json` is outside the brief's write set (created because the core exits need hotspots to be
  playable). Move it into the core area's ownership if that is the integrator's rule.
- The arrival storylet's gate is the only root catalog change; the goldens need regenerating for it.
