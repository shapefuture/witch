# Pre-production: what must be decided before the build

Phase: **pre-production.** The game is not being built yet. The user will finalise the design and the narrative,
and this phase collects what the build needs once they are final. Gameplay code, new rooms, new characters and
generated art wait behind two gates:

- **DESIGN-FREEZE**: the questions below are answered, or deliberately deferred.
- **STYLE-LOCK**: the conflicts in `docs/art/STYLE_BIBLE.md` (SC1 to SC4) are decided, and rules R1 to R6 accepted.

Work that is allowed now: the references, the style bible, the navigation study, the test and gate housekeeping,
and the engine hardening (infrastructure, not game content).

## Design questions

- **DQ1.** The witch's goal in the first thirty minutes.
- **DQ2.** The verbs. The six verbs (LOOK, ASK, SHOW, WAIT, GO, CAST) stay internal, and the player never sees them
  (`docs/DESIGN_INVARIANTS.md`). Confirm.
- **DQ3.** The rooms: how many, and which. Candidates from the references: the archive hall (01), a river (02), a
  hotel lobby (04), ruins (05). See SC4.
- **DQ4.** The ending: the path out (`go_path_out`), what it says, and whether there is more than one ending.
- **DQ5.** Session length. A rough target in minutes.
- **DQ6.** Platform priority. The repo says mobile-first; confirm, because it decides the budgets.
- **DQ7.** Input: pointer only (default) or a second mode (N1).

## Narrative questions

- **NQ-a.** The premise: why the witch is in the archive, and what she wants there.
- **NQ-b.** Tomas, Vera, Elian and Ilya: who they are and what they know. Vera's current design is invented in
  `docs/art/new_character_and_props.md`; Elian and Ilya do not have a design. Decisions X2 and X3 in `PLAN.md`.
- **NQ-c.** The raccoon's role. The repo plans a tele-somatic perception channel (`CLAUDE.md`); its meaning
  depends on the story.
- **NQ-d.** The shadow: who she is and what she knows.
- **NQ-e.** The antler witch (`witch_antler.glb`). Is she a second form of the witch, or another person?
- **NQ-f.** Tone. Light and strange, grim, or something else. Examples would help.
- **NQ-g.** The order of places, once SC4 is answered.

## Asset needs (derived after the answers)

Filled in after DESIGN-FREEZE. For each room: plates or painted art, proxy, anchors, lighting notes. For each
character: model, clips, palette, text keys. For props and UI slabs: what the player reads. Audio: none yet.

## Tools present (checked, nothing generated)

- Blender (for plate and proxy builds), numpy and Pillow (for the character and metrics tools), Godot 4.6.3 (the
  binary is in the session scratchpad, not the repo).
- Image and video generation (Higgsfield) costs money per run. `CLAUDE.md` requires an estimate and a cap for
  every run. No generation is planned until the style is locked, and each run needs the user's approval.

## Freeze criteria

- **DESIGN-FREEZE** when DQ1 to DQ7 and NQ-a to NQ-g are answered or explicitly deferred, the room list is written,
  and the cast list is fixed.
- **STYLE-LOCK** when SC1 to SC4 are decided and R1 to R6 are accepted in `STYLE_BIBLE.md`.
