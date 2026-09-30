# Design invariants

These are the rules that stop *Witch You Were Here* from turning into a conventional
adventure game. Each one names where it is enforced, so breaking it fails a build instead of
being noticed six months later.

1. **The player never sees the internal action ontology.**
   `LOOK / ASK / SHOW / WAIT / GO / CAST` are authoring primitives. The player sees natural
   language ("Hang back and watch" in Russian), never the verb.
   *Enforced:* `InteractionOption.label` is the only thing the presenter renders;
   `tests/mirror/test_game_catalog.gd::test_labels_are_russian_prose_not_keys_and_never_expose_the_ontology`.

2. **Knowledge can change the meaning of an existing action.**
   The same verb on the same object offers different acts once the player understands
   something ("Look more closely" becomes "Look at the gear Tomas described").
   *Enforced:* `tests/interaction/test_interaction_resolver.gd` (options change with claims and
   revised models); golden transcripts record the options offered after every step.

3. **NPCs react to what they infer the witch will do, not to hidden trust scores.**
   An NPC's hidden variable is an *expectation* from a small vocabulary (`EXPECT_MAGIC`,
   `EXPECT_PERMISSION`, `EXPECT_DISTANCE`, ...), compared with what the witch actually does.
   *Enforced:* `game/npc/expectation.gd`, `game/npc/response_policy.gd`;
   `tests/npc/test_tomas_clearing.gd::test_expectation_policy_classifies_each_verb_against_what_tomas_expects`.
   There is deliberately no numeric "trust" anywhere (`relationship_value` reads recorded
   boundaries/invitations, not a score).

4. **Dialogue never owns world state.**
   `.dialogue` files hold structure and line *keys*. They read Mirror through a read-only
   context and can change the game only by recording a `DIALOGUE_CHOICE` action.
   *Enforced:* `tests/dialogue/test_dialogue_bridge.gd::test_dialogue_reads_but_never_writes_game_state`.

5. **Mirror owns canonical game events.**
   The hash-linked event log is the truth; every store is a replayable projection. Scenes,
   NPCs and UI submit actions and present committed results.
   *Enforced:* `MirrorEngine.replay_all()` must equal the live projection
   (`tests/save/test_mirror_persistence.gd`); `tests/sim/test_simulation.gd` (a UI playthrough
   yields the identical chain as the headless sim: `tests/interaction/test_game_flow.gd`).

6. **Every important causal effect is observable.**
   If an action changes something the player should be able to reason about, there is
   presentation for it (a pose, a line, a camera beat) and evidence recorded for it.
   *Enforced:* the catalog loader warns on a response contract with no presentation
   (`test_authored_catalog_loads_clean` requires zero warnings).

7. **Magic is useful and mechanically desirable.**
   `cast_repair` is available from the first moment and works spectacularly.

8. **Magic can increase outcome certainty while decreasing motive certainty.**
   After casting, `machine_runs` is `ESTABLISHED` and `why_tomas_withdrew` is
   `UNRESOLVED_BY_DESIGN`; the discrepancy vector shows *motive* and *relationship* missed while
   *outcome* did not.
   *Enforced:* `test_impulsive_magic_raises_outcome_certainty_and_lowers_motive_certainty`.

9. **Contradictions must be survivable.**
   Every wrong path has a way back, and a contradiction is recorded as a revision of the
   player's model, not as a flag.
   *Enforced:* `test_contradictions_are_survivable_the_impulsive_path_recovers`; sims
   `impulsive_recovery` and `impulsive_then_patience`.

10. **The player should revise a model, not merely obtain a key.**
    Progress is gated by `requires_models` / `requires_claims`, never by a held item.
    *Enforced:* `test_options_unlock_from_revised_models_not_from_keys`.

## Other contracts

### The ending action (`ENDING_ACTION`)
When the player chooses **GO** through the path: the world remains unresolved, **the camera does
not follow**, audio is left alone, and the protagonist leaves the frame under her own power.
Implemented by the `go_path_out` action (`data/mirror/actions/go.json`): presentation
`{"kind":"camera","mode":"stay"}` then `{"kind":"leave_frame"}`; `CameraDirector` freezes and
stops easing. *Enforced:* `test_ending_action_contract`,
`test_taking_the_path_out_freezes_the_camera_and_removes_the_witch`.

### One language, one text file
The game is Russian-only and every player-visible string lives in `data/text/ru.json`.
*Enforced:* `tests/mirror/test_text_single_source.gd`, `tools/text_tool.py check`.

### Presentation is not meaning
The Mirror catalog holds ids and text **keys**, never prose, so rewording never invalidates a
save. (Camera/animation *instructions* live in the catalog and do count toward its fingerprint.)
