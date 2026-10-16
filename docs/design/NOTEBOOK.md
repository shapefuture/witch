# The notebook and the staged reveal (built 2026-10-16, stream L)

Sources: `ALIVENESS.md` (what makes the world feel alive), `ROOM_OF_US_REVIEW.md` items 1 to 3.

## The notebook (`game/mirror/notebook_view.gd`)

A read-only view over the claims the witch holds. It writes nothing to Mirror, returns ids and kinds only
(the words live in `data/text/ru.json`), and phrases no task: an entry is a fact or a question.

Each entry has:

- **kind**, where the belief came from:
  - `seen`: established, and backed by evidence (she watched it happen);
  - `told`: it came from another mind (a claim share, hearsay, a custom the household holds);
  - `guessed`: a possibility she has not confirmed;
  - `open`: an UNRESOLVED_BY_DESIGN question. It stays visible: the notebook never hides what the design has left open.
- **event_id**: the event she first learned it at (or last updated it). `source_event` opens that event
  (its kind, its subject, its place in the log), so every entry traces back to its moment (ROOM_OF_US item 2).
- **discovery_class**: from `data/aliveness/classes.json`. Entries are dealt round-robin across classes
  (`DiscoveryClasses.interleave`), so one class does not fill the page (ROOM_OF_US item 3).

Tests: `tests/mirror/test_notebook.gd` (every entry opens its event; open questions stay open; kinds are told
apart; neighbours differ in class).

## The staged reveal (`game/presentation/staged_reveal.gd`)

Inspecting an object reveals its plaque in layers, one per tap, in this fixed order:
`evocative` (the line that sets the scene), `surprise`, `memory`, `connection`. Whatever order the data was
written in, the layers come out in that order. An object shows only the layers it has, and the last one stays
on the plaque. Unknown layer names are ignored rather than guessed at.

Tests: `tests/presentation/test_staged_reveal.gd`.

## Not wired yet

- The notebook is not on screen. It needs a diegetic page (`Diegetic`, `PlaqueStack`) and a satchel tap in
  `game/main/game_root.gd`, which belongs to the integrator unit (`witch-29y.12.16`, L-live, X13).
- `StagedReveal` is not yet driven by `PlaqueStack`. The plaque presenter takes the layers when the
  object-inspection wiring lands with L-live.
- Claim text keys: a claim has no authored line yet. The UI will look up `claim.<id>` when content exists
  (content waits for DESIGN-FREEZE).
