# Pre-production: what must be decided before the build

Phase: **pre-production.** The game is not being built yet. The user finalises the design and the narrative, and this
phase collects what the build needs once they are final. Gameplay code, new rooms, new characters and generated art
wait behind three gates:

- **DESIGN-FREEZE**: the questions below are answered, or deliberately deferred.
- **STYLE-LOCK**: the look is fixed as in `STYLE_BIBLE.md`, anchored to the master prompt (`ps1p`). SC1 is confirmed and SC3
  decided; SF, SC5, SC6 (screen effects) and SC7 (palette base) are answered, and rules R1 to R12 are accepted.
- **HALL**: the archive hall is a demo scene that may or may not stay in the final game, decided at DESIGN-FREEZE. The grade and geometry work waits on it.

Work that is allowed now: the references, the style bible, the navigation design, the test and gate housekeeping, and
the engine hardening (infrastructure, not game content).

Answered so far (2026-10-14): DQ6 and DQ7 below.

## Design questions

- **DQ1.** The witch's goal in the first thirty minutes.
- **DQ2.** The verbs. The six verbs (LOOK, ASK, SHOW, WAIT, GO, CAST) stay internal, and the player never sees them
  (`docs/DESIGN_INVARIANTS.md`). Options are shown as sentences. Confirm.
- **DQ3.** The rooms: how many, and which. None of the reference settings is canon (SC4). The archive hall is built
  but may not stay (HALL).
- **DQ4.** The ending: the path out (`go_path_out`), what it says, and whether there is more than one ending.
- **DQ5.** Session length. A rough target in minutes.
- **DQ6. Answered 2026-10-14:** mobile first, desktop second. The budgets follow the phone.
- **DQ7. Answered 2026-10-14 (guess N1):** touch and mouse are primary. No tank controls and no movement keys.
  Keyboard adds accelerators only (advance, pause). To confirm, because it rewords the pointer-only rule.

## Narrative questions

- **NQ-a.** The premise: why the witch is in the archive, and what she wants there.
- **NQ-b.** Tomas, Vera, Elian and Ilya: who they are and what they know. Vera's current design is invented in
  `docs/art/new_character_and_props.md`; Elian and Ilya have no design. Decisions X2 and X3 in `PLAN.md`.
- **NQ-c.** The raccoon's role. The repo plans a tele-somatic perception channel (`CLAUDE.md`); its meaning depends on
  the story.
- **NQ-d.** The shadow: who she is and what she knows.
- **NQ-e.** The antler witch (`witch_antler.glb`). Is she a second form of the witch, or another person?
- **NQ-f.** Tone. Light and strange, grim, or something else. Examples would help.
- **NQ-g.** The order of places. None of the settings in the references is canon (SC4).

## Asset needs (derived after the answers)

Filled in after DESIGN-FREEZE. For each room: plates or painted art, proxy, anchors, lighting notes. For each
character: model, clips, palette, text keys. For props and the interface: what the player reads and taps.
Audio: none yet.

## Tools present (checked, nothing generated)

- Blender (for plate and proxy builds), numpy and Pillow (for the character and metrics tools), Godot 4.6.3 (the binary
  is in the session scratchpad, not the repo).
- Image and video generation (Higgsfield) costs money per run. `CLAUDE.md` requires an estimate and a cap for every
  run. No generation is planned until the style is locked, and each run needs the user's approval.

## Freeze criteria

- **DESIGN-FREEZE** when DQ1 to DQ5 and NQ-a to NQ-g are answered or explicitly deferred (DQ6 and DQ7 are done), the
  room list is written, and the cast list is fixed.
- **STYLE-LOCK** when SC1 is confirmed, SC3 is decided, SF, SC5, SC6 and SC7 are answered, and R1 to R12 are restated and accepted in `STYLE_BIBLE.md`.
- **HALL** decided at DESIGN-FREEZE, with the other design questions.
