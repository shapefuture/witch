# The Minds layer

> Mirror owns meaning. The Minds layer is how Mirror decides what a *happening* means to each of the minds
> standing around it, what the world does about it later, and what a group comes to take for granted.

A tap on a painted globe is not a menu choice, so it never passes through `resolve_action`. It is a
**happening** in a place. `MirrorMinds` turns one happening into one atomic Mirror transaction:

```
 happening {kind, actor, subject, place, data, hints}
      |
      v  WitnessSelector     who perceives it (presence, distance, line of sight, attention, overheard)
      v  MindsInterpreter    what each witness makes of it (beliefs, relationship, stance; may misread)
      v  ConventionBook      do these readings feed a custom?  (threshold, holders, cap, decay)
      v  MindsRules          which world rules answer it: reactions now, consequences later, evidence
      v  Mirror.engine.record_world_event      ONE transaction: the happening + every witness's observation
      v  ConsequenceQueue    what fell due when the clock moved (advance_time, or an action's time_cost)
```

Code is in `game/mirror/minds/`, data in `data/mirror/minds/`, the painted-room bridge in
`game/mirror/prop_events.gd`. The runtime owns it: `Mirror.minds` (a `MirrorMinds`).

## State is derived, decisions are recorded

`MindsState` (presence, the deferred queue, the folklore book, "have the starting beliefs been written") is a
pure function of the event log: `apply(event)` reads only a committed event's payload, and every call into
`MirrorMinds` first re-synchronises (`_sync`) with the log. So a loaded save, a replay, a rolled-back preview
and an uninterrupted run cannot disagree, and no save format changed. Every *decision* (who witnessed, what was
read, what was scheduled or cancelled, which convention moved) is made when the event is committed and written
into the `WorldEventHappened` payload as absolute values; applying it later needs no rule data. Consequences:

- retuning `data/mirror/minds` never invalidates a save (the data is **not** part of the engine catalog, so it
  is not in the catalog fingerprint; scheduling, firing and adopting never touch the fingerprint);
- `engine.replay_all()` reproduces every witness's claims, models, relationships and evidence, and
  `minds.rebuild()` reproduces the queue and the folklore (tests: `test_minds_queue`, `test_hall_rules`, the
  save-mid-run test over every `data/sim` script);
- there is no randomness anywhere: the same inputs write the same chain (`test_the_same_inputs_...`).

## The engine primitive (addons/mirror_engine, additive)

`MirrorEngine.record_world_event(actor, subject, payload, observations)` commits a `WorldEventHappened` plus one
`ObservationRecorded` per witness in one transaction (rollback leaves none behind). `payload.effects`
(`{world, npc_state}`) is applied like a response's effects and re-applied by replay; an observation may carry
`relationship_effects` (`{a, b, tags, payload}`), also replayed. `check_requirements(definition, holder, ctx)`
is the public form of the claim/model/operator gate; `next_world_event_id()` names the event before it exists.
See `PROVENANCE.md`.

## 1. Witness selection

`WitnessSelector.select(event, kind_def, candidates, config)` is pure. For each holder in Mirror's presence
table: the actor perceives `direct`; others perceive by `sight` (same place, clear line, attention not away,
in range) or `sound` (same place, or the next place if the sound `carries`: then it is `overheard`, faint).
Clarity (0 to 100) falls with distance and attention. Whoever is left is reported in `unaware` with a reason
(`off_stage`, `out_of_range`, `no_line_of_sight`, `not_attending`, `absent`) and learns nothing: not even an
observation event is recorded for them. Evidence is typed by channel: direct/sight `DIRECT`, sound `INDIRECT`,
overheard `AMBIGUOUS`.

Perception data only the scene knows travels as `hints`: `present` (who is on stage: Mirror may put Tomas "in
the clearing" while the painted hall does not show him), `absent`, `distance {holder: metres}`,
`los {holder: bool}`, `attention {holder: idle|attending|busy|away|asleep}`, `loudness`. Presence itself is
Mirror's: `minds.set_presence(holder, place)` records it.

## 2. Per-holder interpretation

`interpretations.json`: rules compete per witness like response contracts (highest `priority*10 + specificity`,
then id). A rule may require the holder's own claims/models/operators (`requires_claims`, `requires_models`,
...), read their relationship with the actor (`relation.count`, `relation.tags`, `relation.interpretations`),
their stance (`npc.<id>.<field>`), the clarity of the perception (`min_clarity`/`max_clarity`, `channels`), and
active conventions. It yields `reads` (a label: `play`, `tampering`, `blame`...), a `perceived` account
(`actor_id`, `outcome`, `motive`), and holder-scoped effects. Anything `perceived` shares with the event's
`truth` is compared with the engine's own `discrepancy.compare`: a witness who blames the wrong person is
recorded `misread` with `DiscrepancyKind.ACTOR`; `minds.compare_accounts(event_id, a, b)` returns the
discrepancy vector between two witnesses' accounts. A model effect `{"type": "ensure"}` means "support this
model, or begin it": resolved at commit into the plain `support` / `upsert` the engine replays.

## 3. Deferred consequences

A world-rule variant's `transformation.schedule` entries become `ConsequenceQueue` entries
`{id, due, event, origin, slot, when}`. Ids are issued in scheduling order; `(due, id)` is the firing order.
The queue is consumed by the clock: `minds.advance_time(n)` (or any committed transaction that advances it,
e.g. an action with a `time_cost`, via `transaction_committed`) fires everything due, each as a normal
happening that can itself be witnessed and trigger rules. Firing is chunk-invariant (advancing 10 equals 5+5).
Bounds (`minds.json limits`): `max_pending`, `max_chain_depth` (a consequence of a consequence...),
`max_fired_per_pump`; a `slot` with policy `replace | skip | stack` gives "one answer at a time"; a `when`
condition is re-checked at firing (`consequence.fizzled`). Results of fired consequences are emitted on
`minds.consequence_fired` and returned by `take_fired()` (the signal can fire inside a time-costing action's
commit, before that action's own presentation).

## 4. Folklore / conventions

`conventions.json`: a community's repeated readings of the same kind become a convention. Per convention:
adoption `threshold` (events fed), `min_holders` (distinct minds), `cap` on the tally, `decay {every, amount}`,
`retire_at`; the first `max_origin_events` event ids are recorded as its **origin events**. Changes are
`adopted | stalled | retired | forgotten | capped`. A convention is a causal force three ways: it biases
interpretation (`force.bias`) for its members; it grants members engine operators (`force.enables_operators`,
revoked on retirement); and world-rule variants can depend on it (`trigger.requires_convention`,
`trigger.convention_change`) or be altered by it (`variant.conventions.<id>.patch`: `set` by dotted path, or
`<key>_add`). `share_claim` is unchanged and word for word; conventions are a separate mechanism (the
test `test_share_claim_stays_word_for_word_...` pins both).

## 5. The four laws, as a linter

`FourLawsLinter.lint(data, {table, engine})` runs in `tests/mirror/test_four_laws.gd` against the real catalog.
Errors fail the build, with the rule id, a code and a sentence saying what to add.

| Law | What is checked (codes) |
|---|---|
| 1 Invariant relations | every rule declares an `invariant` {relation, polarity, roles, constraints}; each variant instantiates that relation (`variant_relation_mismatch`), keeps the polarity (`polarity_flip`), binds every role (`unbound_role`), and its transformation satisfies the constraints (`constraint_violation`: `delay_min`, `delay_max`, `same_reaction`, `needs_convention`), also as altered by each convention (`convention_patch_breaks_invariant`); exceptions narrow, never reverse (`exception_flips_polarity`) |
| 2 Evidence | a learnable rule has >= 2 (major: 3) independent manifestations with distinct sources (`too_few_manifestations`), in >= 2 domains (`too_few_domains`), each giving the witch something to learn (`no_player_evidence`) |
| 3 Model revision | a `revision` {model, deeper_model, exception, teaches}: the model is formed (`model_never_formed`), a `revise` (never a bare `contradict`) leads to the deeper one (`revision_unreachable`, `punishing_contradiction`), and the exception teaches (`exception_teaches_nothing`) |
| 4 Cultural persistence | every convention declares `origin {event_kinds, fed_by}` that resolves and can feed it (`no_origin`, `fed_by_mismatch`), is bounded (`unbounded_adoption`, `unbounded_tally`, `never_decays`), reachable (`unreachable_adoption`) and does something (`no_causal_force`); `lint_state(minds)` checks at runtime that whatever is adopted has origin events in the log |
| structure | event kinds, subjects, holders, conventions, operators, reaction ops, template tokens and text keys all resolve (`unknown_*`, `missing_text`) |

`FourLawsLinter.five_tests(data)` and `recombinations(data)` report the five tests of a world rule (can state,
demonstrate, infer, recombine, surprise); a rule that never meets another is a warning.

## The hall's three rules (data/mirror/minds/world_rules.json)

| Rule | Invariant | Manifestations (domain) | Boundary (revision) |
|---|---|---|---|
| `rule.hall.echo` The hall answers late | an answer is the *same move* made later (`delay_min 1`, `same_reaction`) | globe answered by statue (physical), statue by globe (physical), the raccoon repeating the poke (social) | the hall keeps only the latest touch: `m.hall.every_poke_answered` is revised into `m.hall.latest_poke_answered` |
| `rule.hall.regard` Whatever moves is looked at | attention follows motion at once (`delay_max 0`) | the raccoon looks (social), the statue leans in (physical), Tomas remarks (relational) | what nobody saw nobody looks at: `m.hall.everything_watches` into `m.hall.seen_motion_is_watched` |
| `rule.hall.name` What two minds agree on sticks | a shared reading becomes a custom (`needs_convention`) | the globe hops for play (physical), the raccoon plays by itself (social), Tomas says it aloud (epistemic) | one mind repeating changes nothing: `m.hall.repetition_makes_custom` into `m.hall.shared_reading_makes_custom` |

They recombine because their consequences are each other's triggers: the raccoon looks where an echo lands
(regard x echo), and once the globe is a toy the statue answers after 1 tick instead of 3 and the raccoon runs to
meet it (name x echo, a convention patching a variant). Tomas starts out reading the witch's pokes as meddling
(`interp.tomas.poke_is_tampering` supports his model `m.tomas.pokes_harmless` each time nothing breaks) and
flips to `play` once that model passes 0.6, which is what lets the custom form on the fourth poke; he never
reads the statue as play, so `conv.hall.statue_is_a_toy` stalls forever (the counterexample). The whole
playthrough is `data/sim/hall_rules.json` (golden: `tests/golden/hall_rules.json`); read the transcript with
`godot --headless --path . -- --debug-sim data/sim/hall_rules.json`.

## The painted-room adapter

`PropEvents` (a Node, `game/mirror/prop_events.gd`):

```gdscript
var bridge := PropEvents.attach(painted_room, Mirror)   # connects prop_pressed (2 or 3 args) and walked
painted_room.add_child(bridge)                          # in the tree it also runs the clock (1 tick per second)
bridge.reaction_requested.connect(_on_reaction)         # {op: PROP_REACT|LOOK_AT|FOLLOW|APPROACH|COMMENT, ...}
bridge.presentation_ready.connect(_on_lines)            # existing presentation kinds (a COMMENT is a `line`)
bridge.play_prop_reactions_on_room()                    # optional: PROP_REACT -> PaintedProp.play(reaction)
bridge.set_attention("raccoon", "away")                 # perception hint the scene owns
```

It reads who is on stage and how far each actor is from the thing touched off the room (`actors`), passes that
as hints, and holds no truth. `walked` is throttled (`walk_min_distance`) and `WALKED` is a quiet kind: written
only when somebody reacts. Tested against a stub emitter (`tests/mirror/test_prop_events.gd`); `PaintedRoom`
itself is untouched. The room does not yet emit `walked`; the adapter connects to it when it appears.

## Adding a rule

1. Event kinds, subjects and holders go in `minds.json`; words go in `data/text/ru.json` (keys only in data).
2. Write the rule in `world_rules.json`: invariant first, then variants (each with `relation`, `domain`, `form`,
   `source`, `trigger`, `transformation`, `evidence`), an exception, and the `revision`.
3. `GODOT=... SKIP_RENDER=1 ./tests/run_tests.sh test_four_laws` names whatever is missing.
4. Add a `data/sim` script that plays it, `UPDATE_GOLDEN=1 ./tests/run_tests.sh golden`, and read the diff.

## Not built (by design, so far)

Raccoon tele-somatic signal as a perception channel; spreading a convention between communities; interpretation
rules that read other witnesses' accounts (gossip as discrepancy); a UI for the witch's knowledge of a custom;
`PaintedRoom` emitting `walked` and consuming `reaction_requested` (coordinator).
