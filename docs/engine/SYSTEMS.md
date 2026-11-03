# Systems: the notebook, the chuika, the flash and the magic looks

Owner: the SYS workcell. The contracts are frozen in `docs/design/GAME_SPEC.md` section 4 (presentation kinds, the
notebook and chuika sidecars); this file says how they are built. The text the player reads lives in
`data/text/ru/systems.json` and in the other tables, and nothing here holds game truth: Mirror decides, the systems
cell presents.

## The seam

The game root calls `SystemsPresenters.register(director, host)` once, after it registers its own kinds (`line`,
`dialogue`, `camera`, `anim`, `npc`, `magic`, `leave_frame`, `wait`, `room_variant`). Registration hangs three
presenters on the host (`NotebookPresenter`, `SightPresenter`, `FlashPresenter`) and registers their kinds:

| kind | step fields | what it does | holds the presentation? |
|---|---|---|---|
| `notebook` | `claim` (optional) | opens the notebook at the page that shows the claim | yes, until she closes it |
| `sight` | none | shows the chuika's ghosts of the NPCs in the room | yes, for a few seconds |
| `flash` | `image` (a place id), `sensation` (ignored) | a two-second telesomatic card, no caption | yes, two seconds |
| `magic` | `effect`, `mode` (`violet`, `verdigris`, `gold`), `target` | the magic look (see below) | yes |

`host` offers `runtime` (the Mirror runtime; the `Mirror` autoload when the host has none), `room` (a RoomSlot, read
for `stage_actors()` and `anchor(id)`) and `witch` (a Node3D, for a look at the witch). Each presenter reads these when
its step plays, so a room that changes after registration is seen.

## The notebook

- **Entries** (`game/mirror/notebook_view.gd`). `NotebookView.entries(engine, classes, claims)` lists only the claims
  the witch holds that a sidecar names. `claims` is the merged `data/notebook/<area>.json` (`load_claims`): each
  claim gives a `kind` and a `text` note key. The seven kinds, in the notebook's order: `seen`, `heard`, `shown`,
  `inferred`, `predicted`, `altered`, `untestable`. The kind is authored. A claim whose status is
  `UNRESOLVED_BY_DESIGN` is `untestable` whatever its sidecar says. Entries keep the event they were first learned at,
  and they are interleaved by discovery class (`data/aliveness/classes.json`).
- **Validation.** `load_claims` reports a sidecar entry with an unknown kind, a text that is not a `note.` key, or a
  claim named by two sidecars. Missing directories are fine: no sidecars means an empty notebook.
- **Pages.** `NotebookView.pages(entries, per_page)` groups the entries by kind and cuts each group into pages of at most
  three, so a page never mixes kinds. `page_of(pages, claim)` finds the page a `notebook` step opens at.
- **The slab** (`game/ui/notebook_slab.gd`). One carved slab, centred in the picture, one page at a time, its height the
  height of its tallest page. The kind is a brass tab (`ui.notebook.kind.*`). Taps: the right two thirds turn the page
  (on the last page they close it), the left third turns back, and the close plaque closes it. The plaque is 32 UI
  pixels tall, which is 48 render pixels at 960x540. Space and Enter advance, as they do for lines. The slab takes its
  own taps through an `IntentInput` child, as the main menu does, because the presentation holds the root's input while
  it plays. `closed` is emitted after the tap that closed it, so the presentation resumes outside that tap.
- **The step** (`game/presentation/notebook_presenter.gd`). It opens the slab at the named claim's page (or the first
  page), and the director waits until she closes it.
- **The witch's own options** (`data/mirror/areas/systems/actions.json`). Two LOOK actions on the target `witch`: the
  notebook (`systems_witch_open_notebook`, no precondition: it is offered in the postgame too, as her own record, and it
  opens empty before anything is written), and listening to her chuika (`systems_witch_listen_sight`, not offered in the
  postgame, where nothing is in the room to sense). Their labels are in `data/text/ru/systems.json` (`opt.systems.*`, at
  most 40 characters).

## The chuika (Expectation-Sight)

- **Sidecars** (`game/presentation/expectation_sight.gd`). `data/expectations/<area>.json` is a list of entries:
  `{id, npc, when, ghost, source, note}`. `when` is a Mirror condition, matched by `MirrorConditions` over
  `MirrorRuntime.context_snapshot()` (world, NPC states, clock). `ghost` is one of `flinch`, `reach`, `turn_away`,
  `step_back`, `hold_breath`, `look_at:<target>`. `source` is `npc` or `projection`. `load_entries` rejects an entry that
  breaks these rules, and a repeated id.
- **Who is in the room.** An actor on stage is present when its NPC state puts it at the witch's place (or
  `with_witch`), or when the NPC state has no place at all (Tomas, held by the room).
- **Which ghosts show.** Each entry whose NPC is present and whose `when` matches. Several entries may show for one NPC.
- **A projection is shown exactly like an npc entry.** The presentation descriptor is the NPC and the ghost; the source
  and the note are never read by the presenter. A test pins this.
- **The copies** (`game/presentation/sight_presenter.gd`). Each ghost is a copy of each of the actor's mesh instances,
  added under the same parent and bound to the same skeleton, so it takes the actor's pose and then makes its move. The
  copy is translucent (`render/psx/ghost_silhouette.gdshader`: a faint violet, brightest at its edges, flickering a
  little, and fading in and out). Copies carry the `chuika_ghost` metadata, which is how the presenter skips them when it
  copies the next ghost. A look at a target turns the copy towards the target's position. Copies are removed when the
  step ends.
- **Writes nothing.** Seeing a ghost commits no event and changes no world or NPC state. A test checks both.

## The flash (the raccoon's telesomatic link)

- **The image** (`game/presentation/flash_presenter.gd`). `plate_path(image)` looks for the place file
  `data/world/places/<image>.json`; when its room is painted, the plate is `<room dir>/plate.png`. Otherwise it falls back
  to `assets/painted/<image>/plate.png`. Otherwise the card is a flat violet stand-in. A `sensation` note is accepted and
  never shown.
- **The card.** A quad hung on the camera one metre in front, sized to fill the picture with a margin
  (`card_size`), drawn with `render/psx/flash_card.gdshader`: the plate sampled with a small warp and a red/blue
  offset, a wash of violet, and a soft vignette at its edges. It fades in (0.35 s), holds, and fades out (0.45 s), two
  seconds in all. Its warp is zero under reduced effects (`PSXGlobals.reduced_effects()`).
- **The sound cue.** The painted rooms' `chime` (`assets/painted/sfx/chime.wav`), through `PaintedSfx`.
- **No caption.** The flash draws no label.

## The magic looks (`game/presentation/magic_presentation.gd`)

`MagicPresentation.play(effect, at, mode)`; `mode` defaults to `violet`, so existing callers keep their look.

- **violet** ("I make"): the existing breaking of the rules for `repair` and `flourish`: the palette expands,
  the lens swings, a column rises, and everything resets at the end.
- **verdigris** ("I enable"): a ring of copper-green light opens under the target and holds still, then fades.
  It frames what is there and changes nothing: the palette and the lens are not touched.
- **gold** ("I encounter"): a soft gold disc at her face height, facing the camera, that rises, holds and
  falls. Nothing else moves.
- **fizzle** (`effect: "fizzle"`, act II's misfires): a small violet ball puffs up, sputters three times (a dip and a
  return each), and goes out, shedding six sparks that fall and fade. It never touches the palette or the lens.

The modes' verbs are in the text table (`ui.magic.*`, in `data/text/ru/core.json`); the systems cell shows none of them.
The fizzle emits `sputtered(index)` as each sputter starts, so a test counts the sputters without relying on frame timing.

## Photosafe

No look flashes more than three times a second. A flash is one dip in brightness and its return.

- The fizzle's sputters start at 0.3, 0.8 and 1.3 seconds, so two a second at most (`MagicPresentation.max_flicker_hz()`).
- A flash card flashes once in two seconds.
- The chuika copies flicker at about 1.4 times a second, at under a tenth of their brightness.
- Verdigris and gold only rise, hold and fall.

`tests/systems/test_magic_modes.gd` pins the fizzle's count, order and spacing, and the rate bound from its constants;
`tests/systems/test_flash.gd` pins the flash brightening once. The chuika's flicker and the verdigris and gold looks follow
from their constants and are described here.

## Tests

- `tests/systems/test_notebook_kinds.gd`: the seven kinds from a fixture sidecar; an open question is untestable; pages
  group by kind; sidecars are validated.
- `tests/systems/test_notebook_slab.gd`: the slab builds headless, opens at a claim, turns by tap, closes by its plaque,
  ignores taps that miss it, and its close target is at least 48 pixels at 960x540.
- `tests/systems/test_notebook_presenter.gd`: the step opens at the named claim and waits; the director plays it through
  the registered handler and holds until she closes it.
- `tests/systems/test_expectation_sight.gd`: the ghost contract; the loader; presence; selection by conditions; a
  projection and an npc ghost look the same; the moves end at rest; seeing ghosts writes nothing to Mirror; the copies
  appear and are removed.
- `tests/systems/test_flash.gd`: plate resolution; the card fills the picture; no caption; the sound cue; the stand-in;
  reduced effects; a flash step through the registered seam takes its card away; a flash brightens once over two seconds.
- `tests/systems/test_magic_modes.gd`: the fizzle sputters three times, in order, no faster than twice a second; each
  look's nodes and signals; verdigris and gold leave the palette alone; violet still breaks and settles.
- `tests/systems/test_systems_content.gd`: every systems step in `data/mirror` has a handler once the seam is registered;
  every magic step names a look and an effect that `MagicPresentation` plays.
- `tests/systems/test_systems_actions.gd`: the witch's two options in the game scope; the chuika's postgame gate; the
  labels are in the table and at most 40 characters.
- `tests/systems/test_systems_registration.gd`: the three kinds have live handlers after registration; an unknown kind is
  reported, not skipped.
- `tests/mirror/test_notebook.gd`: the earlier notebook API, now fed by sidecars.

The fixtures are in `tests/systems/fixtures/` and `tests/systems/stub_room.gd` and `stub_host.gd` stand in for the room
and the host. The tests use keys, not Russian prose, because the text-table scan covers `tests/`.

## Decisions (educated guesses where the spec is open)

- The kind tabs and the notebook's controls are in the text table; the notebook's words are the witch's
  (`ui.notebook.*`, `ui.systems.*`, `opt.systems.*`).
- The notebook's page turn is a tap on the right two thirds; the left third turns back. A forward tap on the last page
  closes the notebook. This keeps the whole slab a large target, as the brief asks.
- A `flash` is a card in the camera's space, not a change to the room, so it cannot change what Mirror shows.
- A `look_at:<target>` ghost turns to the target's position, or to the witch's when the target is `witch` or `player`.
- The `sight` step waits for its ghosts (about two seconds for a single entry, longer for more). The entries stagger
  0.35 seconds apart.
- The gold glow sits 1.6 metres above the step's `at` point, which is the witch's face when the game root passes her
  position.
- `image` names a place (or a painted directory). The spec's "capture id" has no file yet, so it resolves like any other
  name that has no plate.
- The notebook is offered in the postgame as her record, and it has no precondition. The chuika is withheld there.
- A flash rises to full strength and falls back once, in two seconds (0.35 s in, a hold, 0.45 s out). The spec gives only
  "about two seconds".
- The fizzle's core is a violet ball that puffs up, sputters three times (each a dip to 35% of its size and back) and goes
  out, shedding six sparks. The "clearly magic failing" reading rests on that pattern and the sparks, not on a sound.
- Verdigris opens its ring over 0.8 seconds and holds it for 1.4; gold rises over 0.9, holds for 1.0 and falls over 0.9.
  These timings are guesses. No rendered frame has been checked against the references.

## Needs from the integrator

- `game/main/game_root.gd` must call `SystemsPresenters.register(presentation, self)` once, after
  `_register_presentation()`. At this commit nothing calls it, so the `notebook`, `sight` and `flash` steps are unhandled
  in the game.
- `game/main/game_root.gd` `_play_magic` must pass the step's look: `magic.play(effect, at, str(entry.get("mode", "violet")))`.
  Until then verdigris and gold steps play as violet.
- The notebook's taps are taken by the slab itself, so the root's tap routing needs no change.
