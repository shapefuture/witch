# Game spec: the whole of "Witch you were hear", buildable

Version 1, 2026-10-29. This turns `docs/design/BIBLE.md` (the canon) into places, state, puzzles and contracts that
parallel builders implement. Where the bible leaves a choice open, the choice here is an **educated guess**, numbered
X21 onward (continuing `docs/PLAN.md`), and reversible. Contracts in sections 3 to 5 are frozen for this sweep: a
builder who needs one changed asks the integrator instead of editing around it (AAA v7.1, section 11B.2).

The definition of done for this pass: from the main menu a player starts a new game in the witch's shop and plays the
prologue, acts I to IX and the postgame to the end, in Russian, on stand-in stages where a room's painting is not made
yet; every act's puzzle works through Mirror; a deterministic sim walks every act; the constitution's invariants
(`architecture/constitution.json`) have verifiers; the gate passes. Fidelity grows after that, room by room.

## 1. Decisions (guesses, reviewable)

| id | decision | why |
|---|---|---|
| X21 | The bible lifts DESIGN-FREEZE; its section 17 questions stay open where it says so. | The user supplied it as canon. |
| X22 | The title is the Latin logo "Witch you were hear", exactly as the bible spells it, with no Russian subtitle (`menu.title`). A Russian echo lives in the world: «Ведь мы были здесь», scratched in the House. | A translation would explain what the bible keeps a suggestive layer. |
| X23 | The witch has **copper-ginger hair**, blue-grey eyes and a **violet hood**, made pointed so it reads like the references' hat. This reverses the earlier «русый» decision. | The bible and references 13 to 17 agree on red hair; the hood is the bible's. |
| X24 | First Love is **Мирон** (id `miron`; she calls him Мироша). | «мир» is both world and peace: another world, a calmer one, without making the Fog evil. |
| X25 | Shadow Mirror is **Тень** (id `shadow`, model `shadow.glb`). Her two lines are «Привет.» and «Пойдём.» | «Эй» is a call and can be rude; «Привет» greets someone known. |
| X26 | The raccoon is **Гаврила** (id `raccoon`; she calls him Гаврик, which he dislikes). | A parallel protagonist needs a name; a self-important craftsman's name suits his mock officialdom. |
| X27 | No narrator character. Looks and taps speak in the witch's first person; what she does not witness gets a sparse caption register (third person, present tense, no «ты/вы»). The hall's existing second-person lines stay as they are. | Tone analysis, section 3. |
| X28 | Names: the Fog «Туман», the Original Garden «Наш сад», the Garden Below «Нижний сад», the Basement «Подвал», the Town «Городок», the House «Дом», the hotel «Запределье», Expectation-Sight «чуйка» (her word, never a UI label). | Tone analysis, section 4. |
| X29 | The notebook's seven kinds in her voice: Видела, Слышала, Показали, Думаю, Жду, Переделала, Пока не проверить. The magic modes are verbs in her voice: Делаю (violet), Открываю (verdigris), Встречаю (gold). | The same. |
| X30 | The archive hall stays, as Tomas's archive in the town (Mirror place `clearing`). Its demo flow keeps working in the hall scope. | The user called it a demo that may stay; it is the best-built content and is Tomas's authorship story. |
| X31 | Popochiu is not adopted; the existing interaction layer and Mirror already do its job. LimboAI is not used. | The bible's "remembered stack" predates this engine. |
| X32 | Mirror holds the story: `world.story.act` and `world.witch.place`. Places are presentation; moving is a GO whose effect sets `witch.place`. | Mirror owns meaning. |
| X33 | Consequential choices are Mirror actions (option plaques). `.dialogue` files hold linear exchanges only, with no response lines. | The code analysis found dialogue choices cannot carry consequences yet. |
| X34 | Plot-critical sequences (Мирон's visits, the garden's decay) are Mirror state machines advanced by actions; Minds routines carry ambient life only. | Determinism and sims; WAIT does not run Minds routines today. |
| X35 | The rescue spell **works and holds**: pulled through, Мирон stands in the room for as long as the witch holds the spell; when she lets go he steps back into the Fog. | "The rescue is technically possible" and "First Love genuinely chooses", with no contrived failure. |
| X36 | The ordinary flower grows through a crack in the shop's front step. It offers looking and touching only; no cast, no take, no claim beyond "seen". | An ordinary flower in an ordinary place. |
| X37 | The final impossible event: at dusk every clock in the town stops on the same second, a gold glow comes down the street and the shop bell rings with nobody at the door. Three readings are supported by evidence (the Fog, Тень, her own returned magic); what happened stays «Пока не проверить». | Bible section 10. |
| X38 | Session length for this pass: about 60 to 90 minutes for the whole arc. | First playable; grows later. |
| X39 | Room art: existing plates where a place matches; generated plates (Hugging Face Space, about 4 a day on the free quota) for new places in priority order; a stand-in stage until a place has its plate. New plates use cool violet, blue and magenta masses with gold and red accents and cool or plum shadows (no golden-hour sun), per-texel dithering painted into the texture, one theatrical focal point and five to seven depth layers. | The art analysis measured the hue gap; the quota is the bottleneck. |
| X40 | Bible section 17 continuity: the father's departure is earlier history, Мирон's is the present; the game never connects them in words, only through objects (his drawing in the shop, his toolbox in the basement). The Fog's mechanics and origin stay unresolved. The wand's four branches each leave a trace and a callback. | Bible section 17. |

## 2. Places

| place id | name | art (room) | reference | acts |
|---|---|---|---|---|
| `shop` | Лавка | `assets/painted/shop_ps1` | 16 (inside) | prologue, I, II, VI, VII, IX, postgame |
| `window` | Окно лавки (a close shot from the shop) | `assets/painted/shop_window` | 16 | I |
| `garden` | Наш сад | `assets/painted/garden` | — | prologue, I, postgame |
| `street` | Улица | `assets/painted/street` (variant `quiet`: `street_quiet`) | 17 (mood) | prologue, I, II, VI, VII, VIII, IX |
| `clearing` | Архив (Tomas's) | the archive hall (3D) | 01 | II, VI, VII |
| `observatory` | Обсерватория Ильи | `assets/painted/observatory` | — | II, VI |
| `attic` | Чердак (Гаврила's workshop) | new plate | 17 (clutter) | II, VI, VII, postgame |
| `fog_edge` | Край Тумана | new plate (the spike's) | 13 | I |
| `basement` | Подвал | new plate | 17 | III, postgame |
| `hotel` | Запределье | new plate | 04 | III, V |
| `clocktower` | Часовая башня | new plates (two landings joined by cuts) | 15 | III |
| `garden_below` | Нижний сад | an edit of the garden plate (only her flowers, a straight bench); variants `fading`, `dust` | — | III, IV, V, postgame |
| `threshold` | Порог | new plate (the fogged glass, Мирон's side) | 16 | V |

The place ids are Mirror ids (Minds places in `data/mirror/areas/core/minds.json`). `clearing` keeps its id.

## 3. World state (the `core` area; frozen)

`data/mirror/areas/core/world.json` defines what more than one area uses. **World effects replace a whole top-level
key**, so every world entity holds one field, or a pair that always changes together; an effect restates the whole
entity. NPC state is patched field by field.

| key | initial | values and meaning |
|---|---|---|
| `witch` | `{"place": "shop", "from": ""}` | where she is; `from` the place she came from (for arrival spots). In the postgame it is the viewpoint: the camera stays where she left, and the House's exits move it. |
| `story` | `{"act": "prologue"}` | `prologue`, `act1` ... `act9`, `postgame` |
| `wand` | `{"fate": "held"}` | `held` until act IV, then `shattered`, `kept`, `given` or `hidden` |
| `magic` | `{"state": "full"}` | `full` (prologue, I), `failing` (II), `below` (III to V: it works in the underworld only), `gone` (end of V, VI), `returned` (VII on) |
| `verdigris` | `{"known": false}` | true from act VII: the "open" casts appear |
| `gold` | `{"known": false}` | true once she has met the flower |

| npc id | name | initial `npc_state` | notes |
|---|---|---|---|
| `raccoon` | Гаврила | `{"place": "shop", "stance": "busy"}` | `place: "with_witch"` while he goes with her (acts III to V) |
| `miron` | Мирон | `{"place": "garden", "stance": "warm"}` | `place: "fog"` after act I |
| `shadow` | Тень | `{"place": "", "stance": "passing"}` | "" is nowhere on stage |
| `elian` | Элиан | `{"place": "", "stance": "needs", "address": "vy"}` | `address` "vy" or "ty": his «вы» or «ты» to her |
| `vera` | Вера | `{"place": "street", "stance": "busy"}` | her stall is on the street |
| `ilya` | Илья | `{"place": "observatory", "stance": "delighted"}` | |
| `janitor` | Дворник | `{"place": "", "stance": "working"}` | the town's new lamplighter, from act II |
| `concierge` | Портье | `{"place": "hotel", "stance": "officious"}` | a bird |
| `tomas` | Томас | defined by the hall (root `world.json`) | his place is `clearing` (Minds holder) |

**NPC presence:** an NPC stands in the current room when its `npc_state.<id>.place` equals `witch.place` (or is
`with_witch`); with no `place` field, its Minds holder place counts (Tomas).

**Acts change** only through an action's effect `{"world": {"story": {"act": "actN"}}}`, authored by the area whose
act ends. Every place-bound action has a precondition on `witch.place`; every act-bound action has one on `story.act`
(`{"story.act": "act2"}` or `{"$in": {"story.act": ["act2", "act6"]}}`).

**Moving:** an exit is a world entity (a door, a path) targeted by a GO action whose effect is
`{"world": {"witch": {"place": "<to>", "from": "<from>"}}}`. The area that owns the reason to move owns the exit.
The core area owns the always-open exits listed below.

| exit target | from | to | open when |
|---|---|---|---|
| `door_shop_street` | shop | street | always |
| `door_street_shop` | street | shop | always, except `story.act` = postgame |
| `door_shop_garden` | shop | garden | always |
| `door_garden_shop` | garden | shop | always |
| `window_seat` | shop | window | act I (owned by act1) |
| `window_back` | window | shop | always |
| `door_street_archive` | street | clearing | acts II, VI, VII |
| `door_archive_street` | clearing | street | always |
| `door_street_observatory` | street | observatory | acts II, VI |
| `door_observatory_street` | observatory | street | always |
| `ladder_shop_attic` | shop | attic | from act II |
| `ladder_attic_shop` | attic | shop | always |

Underworld and Fog exits belong to their acts' areas.

## 4. Presentation contracts (for the framework and every content area)

**Place files** (framework-owned): `data/world/places/<place>.json`
`{"id", "room": {"kind": "painted", "dir": "res://assets/painted/<dir>"} | {"kind": "hall"} | {"kind": "stage",
"palette": [...]}, "variants": {"<name>": "<dir>"}, "spots": {"<npc id or default>": [x, y]}, "arrive": {"<from
place>": [x, y]}}`. Pixel coordinates are on the 1280x720 plate. A painted room whose dir has no `room.json` falls
back to a stand-in stage, so every place is playable before its art exists.

**Hotspots** (content-owned, one file per area): `data/world/hotspots/<area>.json`
`[{"place": "shop", "target": "kettle", "at": [x, y], "radius": 48}]`, or `"anchor": "<name>"` instead of `at` in
the archive hall. A target is shown only while Mirror offers at least one available action on it, so act gating is the
actions' preconditions, never the hotspot file. An NPC's hotspot is its body; give NPCs a `spots` entry instead.

**Notebook** (content-owned sidecar): `data/notebook/<area>.json`
`{"<claim id>": {"kind": "seen|heard|shown|inferred|predicted|altered|untestable", "text": "note.<area>.<name>"}}`.
Only claims listed here appear in the notebook; the kind is authored, never derived. A claim whose status is
UNRESOLVED_BY_DESIGN is shown as untestable whatever its kind. The notebook text is in her voice and never an
instruction.

**Чуйка** (Expectation-Sight; content-owned sidecar): `data/expectations/<area>.json`
`[{"id", "npc", "when": {<Mirror condition>}, "ghost": "flinch|reach|turn_away|step_back|hold_breath|look_at:<target>",
"source": "npc|projection", "note": "note.<area>.<name>"}]`. A `projection` entry is a false positive: what the
witch expects, shown as if it were theirs. Seeing a ghost records only that she saw it.

**Presentation kinds** content may use: `line` (`speaker`, `key`; `speaker: "witch"` for her), `dialogue` (`title`,
`npc`), `camera` (`mode`: wide, inspect, conversation, magic_reveal, consequence, stay; `focus`), `magic`
(`effect`: repair, flourish; new `mode`: violet, verdigris, gold), `room_variant` (`variant`), `anim` (`actor`,
`name`), `wait` (`seconds`), the new kinds the systems builder adds: `flash` (`image` (a place id or a capture id),
`sensation` (a `note.` key)), `sight` (shows the чуйка ghosts of the NPCs in the room), `notebook` (opens it at a
claim); and the framework's `ending` (the invitation: the witch leaves, the camera stays, the postgame begins). An unknown kind is a
warning, and the gate's flow test fails on it.

**The witch as a target:** tapping the witch (target `witch`) offers her own actions: чуйка, the wand (until act IV
decides it), the notebook. Areas add actions on `witch` with `valid_targets: ["witch"]`.

## 5. Authoring rules (from the code analysis; each one has bitten)

- A response with no `when` should come last as the default; `allow_no_response` defaults to true, so an action
  whose responses all fail to match commits silently.
- A response's `requires_claims` checks the **action target's** beliefs unless it says `"holder_id": "player"`.
- Knowledge is last-write-wins on status: never write ESTABLISHED for a claim the constitution lists as ambiguous by
  design (Мирон's motive, the Fog's nature, what happened on the last night, the gift inference).
- `once_key` must be unique across all actions; make branches exclusive with a world flag.
- Evidence ids are omitted in repeatable actions.
- Every response has a `presentation`; every action and response loads with zero errors and zero warnings in the game
  scope (`tests/content/test_game_scope_catalog.gd`).
- Text keys: `<group>.<area>.<name>` (groups: ui, menu, opt, obj, speaker, line, dlg, toy, note, place); target
  display names are `obj.<target id>` and speakers `speaker.<npc id>`.
- Lines: at most 90 characters in a bubble and 40 on an option; ё always; «» quotes and — dashes; at most one «!»;
  no caps; no system words (событие, задание, награда, доверие).
- The witch's voice: «ты» to people she knows, feminine forms, quick, coins words; PROVING «Смотри…» with a fresh
  tail each time; HOUND chains of short «А…?» questions; FINE flat with a turn to a chore. «Ну и не надо.» is said
  only after a refusal or a departure, with a full stop, rarely (its budget is four in the whole game).
- Гаврила: dry engineer-speak and mock officialdom about his own work, disclaimers that head off expectation, one-word
  verdicts on her showing off; never «хозяйка». Мирон: warm, unhurried, answers a slightly different question. Тень:
  three words a line at most, no clauses, never explains. Tomas: six words or fewer, imperatives, «...» before
  reluctant speech; says "it's mine" aloud once a scene at most. Элиан: «вы» while he needs her, «ты» when he wants
  company (his `address` state, changed by events). Вера: present tense, situational («сейчас», «не в этот раз»),
  never a general rule. Илья: «глянь», «просто так», never «Смотри» (hers). Дворник: unbothered «вы». Портье: hotel
  officialese, knows more, never explains.
- No line explains anyone's psychology, names her modes, diagnoses, or upgrades a guess into a fact; no line gives a
  lesson or a verdict on her.

## 6. The acts

Each act lists its places, beats (storylets), puzzle, notebook entries, what it publishes for later areas (claims,
operators, world values: the interfaces) and its exit. Claim ids are prefixed with their area. "Requires" lists what
an act reads from earlier areas; a builder writes against these ids even before the earlier area exists.

### Prologue: «Смотри!» (area `prologue`)

Places: shop, garden, street. The pleasure of agency; teaches looking, casting, waiting, asking, showing; the notebook
and чуйка.

- **Morning (storylet):** the shop bell, Гаврила complaining about the noise, the commission board with three
  requests (Вера's oven, Илья's clock "that must keep going backwards", the street lamps).
- **The kettle that sulks (causal literacy, observation has a cost):** a kettle on the flame that will not boil.
  Looking at it: it stops simmering. Casting violet: it boils at once, sprays Гаврила, and the tea tastes of thunder
  (`altered`; the forced result destroyed the chance to learn why). Turning away to tidy (WAIT): it boils by itself.
  Looked at, then turned away from: `prologue_kettle_rule` (inferred, «Думаю»: it boils only unwatched) and the
  operator `op.prologue_unwatched`.
- **Чуйка, a party trick:** tapping herself shows Гаврила's ghost bracing for a bath (a `projection`: she was
  thinking of bathing him); later his real ghost flinches from the kettle.
- **Our garden (perceptual literacy):** Мирон tending. Her violet star-lilies (tidy), his crooked sunflowers, the
  crooked bench he built («Прямо сидят только в приёмной» or similar: he likes it leaning toward the afternoon), the
  rope swing tied with his knot «с петлёй, как ухо» (the motif). Casting to straighten the bench: he sits on it and it
  leans back, laughing (his authorship, gently). Publishes `prologue_garden_two_tastes`, `prologue_bench_crooked`,
  `prologue_knot` (seen), `prologue_sunflowers` (seen).
- **The father's drawing** on the shop wall: a tall man lifting a girl toward a comet. Seen; asked about, Гаврила says
  it is older than him. Nothing more. Publishes `prologue_father_drawing`.
- **Evening:** Мирон mentions the light over the marsh: «Там так тихо.» (heard; publishes `prologue_fog_mentioned`).
- **Exit:** with the kettle rule, the garden claims and the evening heard, a bed or lamp target offers ending the day:
  `story.act` = act1.

### Act I: the person who begins to leave (area `act1`)

Places: shop, window, garden, street, fog_edge. Requires `op.prologue_unwatched`, `prologue_fog_mentioned`.

- **Days as a state machine:** `act1_day` `{"n": 1}` to 5, advanced by ending the day. Each day Мирон's behaviour
  follows the bible's stages: returns with fog-dew on his coat (seen); says "the mill" while his boots carry the
  silver moss that grows only at the Fog's edge (heard + seen; inferred "he wasn't at the mill", which may be wrong);
  leaves only when she is not watching (the kettle rule transfers to a person: watched from the window he lingers,
  when she turns away he goes; she can predict it, «Жду»); stays longer; on the last day, his key on the hook "the way
  you return a borrowed thing" (seen). Then `npc_state.miron.place` = fog.
- **Her three modes as action families:** PROVING (cast something spectacular for him: the garden blooming at night;
  he admires it and still goes), HOUND (follow him, or a chain of questions; he withdraws, stance guarded), FINE (turn
  to a chore, flat; his чуйка ghost braces for a question that does not come). None prevents the departure; each
  leaves different heard and seen entries and changes how he answers.
- **Гаврила's eyes:** the first telesomatic `flash`: she sees, without a caption, the Fog's edge and Мирон's coat
  through Гаврила's eyes (he followed him for her, unasked).
- **The Fog's edge (fog_edge):** she can follow him there on day 4; his scarf on a branch; she calls, and from the
  fog: «Там тихо. Тут никому ничего не надо.» or similar (heard). Publishes `act1_fog_is_quiet` (heard).
- **After:** the notebook gains her reading `act1_replaced` («Думаю»: the Fog replaced me), an inference marked as
  hers. Publishes `act1_miron_left` (seen), `act1_key_on_hook` (seen; postgame evidence), `act1_visits_unwatched`
  (predicted).
- **Exit:** the morning after day 5: `story.act` = act2, `magic.state` = failing.

### Act II: the world discovers substitutes (area `act2`)

Places: shop, street, clearing, observatory, attic. Requires `op.ask_before_acting` (the hall's operator).

- **Failing magic:** every violet cast in act II misfires, funnily and informatively (a lamp lights, then politely
  goes out; Вера's bread turns blue); seen `act2_magic_failing`. Never a chore: misfires reveal how things work.
- **The lamps:** Дворник lights the street lamps with a pole, the job her magic did. «Город нанял. Платят. Фонари не
  спорят.» Seen `act2_lamps_without_me`.
- **Tomas:** the archive hall's whole existing puzzle, entered from the street (the hall's arrival plays on her first
  visit). Act II needs it resolved: the operator `op.ask_before_acting`, or Tomas `partnered` or `quiet`.
- **Элиан (need and care):** he comes into the shop, cap in hand, «вы». Offering a spell embarrasses him; asking
  what he needs: «Ничего.» Making tea and letting him stay (SHOW the tea, then WAIT): his `address` becomes ty and he
  says he just likes it here (heard `act2_elian_company`).
- **Вера (context):** two situations on the street. Arguing with her oven: intervening gets «Не сейчас.»; waiting,
  she solves it and offers a taste (`act2_vera_wait_helped`). Her sign about to fall near a child: waiting lets it
  fall and she is upset; catching it (a GO, not a cast) she thanks her (`act2_vera_direct_helped`). Same verbs,
  opposite outcomes: no universal rule (constitution C7).
- **Илья (wonder without use):** the backwards clock in the observatory. Fixing it disappoints him («Ой. Зачем?»);
  looking with him, he shows how it tells «сколько осталось до того, как было» (shown `act2_ilya_backwards`).
- **Гаврила (the peak that became a standard):** the attic workshop, seventeen unfinished projects (about six
  tappable, the rest visible). The self-stirring spoon worked once; the town now wants one daily; he hid it under a
  cloth. A `flash`: the smell of solder and a hot face (no caption). «Оно не работает.» (heard; false). Inferred
  `act2_raccoon_hid_it`. He refuses her commission (a lamp that lights itself): «Нет.»
- **Тень passes:** on the street she buys a candle the witch can no longer light by magic, lights it with a match, and
  pays with a coin wrapped in string tied in a knot «с петлёй, как ухо». Seen `act2_shadow_coin`;
  `act2_shadow_coin` world flag `{"left": true}` (postgame evidence).
- **Exit:** Tomas resolved and three of {lamps, Элиан, both Вера contexts, Илья, Гаврила's refusal}: the trapdoor in
  the shop opens (she goes looking for her grandmother's strong wand): `story.act` = act3, `magic.state` = below,
  `npc_state.raccoon.place` = with_witch.

### Act III: the Garden Below (area `act3`)

Places: basement, hotel, clocktower, garden_below. Requires `prologue_bench_crooked`, `prologue_sunflowers`,
`prologue_knot`, `act2_ilya_backwards` (optional route).

- **Basement:** old stock, the father's toolbox (a child-size hammer in a big man's box; seen
  `act3_father_toolbox`), the crooked doors of reference 17; one opens onto the hotel.
- **Запределье:** the bird concierge stamps forms; keys with eyes hang on the rack; "rooms are allotted by
  recollection": asked for a room, he asks which one she remembers, and the options are her notebook's places (Наш
  сад needs the prologue's garden claims). Тень sits in the lobby with a key she does not use («Я не остаюсь.»), and
  leaves it on the counter (`act3_shadow_key` `{"left": true}`; postgame evidence).
- **The clock tower (the loop):** climbing returns to the same landing (`act3_loop` `{"n"}`); each loop the clock's
  face grows bored, then asleep (comedy). Revising: looking at the clock shows it runs backwards; with Илья's
  backwards clock in her notebook she can read it ("this tower counts down"), otherwise waiting three loops makes the
  clock yawn and run backwards in front of her. Going down to go up ends the loop: operator
  `op.act3_revise_before_repeating`.
- **Нижний сад:** her lilies everywhere, a straight bench, no sunflowers, the swing tied with a neat bow, everything
  still. Magic works here (the temptation). Looking registers a difference only when she holds the prologue's claim
  (`requires_claims` with `holder_id: player`): `act3_bench_straight`, `act3_no_sunflowers`, `act3_no_knot`. Two
  differences: inferred `act3_only_mine` («Думаю»: this garden is only mine). Each perfecting cast makes it stiller
  (the bees stop).
- **Exit:** `act3_only_mine` known: `story.act` = act4.

### Act IV: the wand and the choice (area `act4`)

Place: garden_below. The hinge.

- **Opening (storylet):** the wand glows; «Ну и не надо.» (one of the four uses), flat.
- **Four exclusive actions on the witch's wand** (a world flag makes them exclusive): break it (`shattered`; she
  keeps the pieces), keep it (`kept`; in the satchel), give it to Гаврила (`given`; «Буду мешать им суп. Шучу.
  Наверное.»), hide it in the basement crate (`hidden`). Each writes `wand.fate`, an altered note, and its own lines.
  None is the right answer; all lead on.
- **Exit:** `story.act` = act5.

### Act V: the unsrescuable rescue (area `act5`)

Places: hotel, threshold, garden_below. Requires `wand.fate`, `op.act3_revise_before_repeating`.

- **The procedure, learned from experiments:** from the concierge, the deepest key (Порог). First an object: the
  desk bell put beyond the fogged glass and pulled back comes back cold and wet with fog (`act5_spell_moves_things`,
  altered: the spell works). Then a willing one: Гаврила volunteers («Я зайду. Ты тянешь. Вернусь с мнением —
  значит, сработало.»); pulled back he grumbles «Я и так возвращался. Ты дёрнула за хвост.» — and she cannot tell her
  pull from his choice (inferred `act5_pull_proves_nothing`). While he is beyond, a `flash`: quiet, cold, a relief she
  cannot name (the Fog is not simply evil).
- **Порог:** Мирон behind the fogged glass, his hand on it (reference 16). Three things she can do, each with its own
  trace; he stays in the Fog in every one:
  - **Pull (violet, held):** he comes through and stands in the room for as long as she holds (`act5_hold`
    `{"held": true}`); she can ask, and he answers kindly and briefly («Привет.» / «Ты устала.» / «Я в порядке.»);
    the moment she lets go (any other action), he steps back through. Altered `act5_he_stood_here`; seen
    `act5_he_went_back`; untestable `act5_would_he_come` (UNRESOLVED_BY_DESIGN).
  - **Wait at the glass:** after a while he lifts his hand from the glass: a wave, or a goodbye, or hello. Seen
    `act5_hand_lifted`; untestable `act5_what_the_wave_meant`.
  - **Show** the sunflower seed or the drawing of the bench: he looks, and touches the glass where it is. Seen.
- **Then her magic goes out:** `magic.state` = gone.
- **The garden cannot be saved (anti-puzzle):** `garden_below` `{"state": "fading"}`, then `dust` after she leaves
  or waits. Casting does nothing; watering turns the water to dust; pressing a flower in the notebook leaves only a
  stain (seen `act5_stain`: the notebook keeps a stain where the flower was). No action sets it back (constitution
  C5). Inferred `act5_cannot_be_restored`.
- **Exit:** the stairs go straight up home: `story.act` = act6, `witch.place` = shop, Гаврила back to `shop`.

### Act VI: among independent people (area `act6`)

Places: shop, street, clearing, observatory, attic. No magic (her casts are absent). Requires the operators
`op.ask_before_acting`, `op.act3_revise_before_repeating`.

- **Tomas's second machine:** he asks her opinion; asking first whether he wants her sketch (the operator) and
  showing it without taking over: he finishes it himself (`act6_tomas_finished_it`).
- **Элиан again:** nothing is broken; sitting with him: «Ничего не сломалось. Просто заходи.» (`act6_elian_ty`).
- **Вера, new contexts:** her cart rolls down the street (acting at once is right); a sharp customer (staying out of
  it is right). Different from act II's pair.
- **Илья:** she watches the backwards clock with him and does not fix it (`act6_ilya_together`).
- **Гаврила's mediocre lamp:** it lights half the room. «Оно так себе. Посмотришь?» Suggesting improvements without
  asking: he covers it. Asking first («Можно скажу?»): «Не сейчас.» — and she lets it be. Sitting in the half-light
  with him: he laughs (`act6_half_light`). The intimate offering accepted.
- **Тень on the shop step at dusk:** «Привет.» She sits a moment and goes, leaving a pressed flower in the ledger: a
  crooked sunflower petal (`act6_shadow_flower` `{"left": true}`; postgame evidence).
- **Exit:** the half-light scene and two others: the night the jars hum (`story.act` = act7).

### Act VII: magic returns (area `act7`)

Places: shop, street, clearing, attic. Requires `wand.fate`.

- **The return (storylet):** joyful, beautiful; `magic.state` = returned, `verdigris.known` = true. The wand's
  callback by branch: kept (it warms in the satchel), shattered (the pieces glow; her hands are enough), given
  (Гаврила hands it back: «Мешает плохо.»), hidden (she may fetch it or leave it).
- **Открываю (verdigris):** casting to hold Tomas's frame steady so he sets the cams himself (stabilise the chooser,
  not the choice) (`act7_enabled_tomas`); the violet cast is still there and still works, and he looks at the result
  like a stranger's. The town's lanterns for the evening: an open cast lays out three colours and people choose; Вера
  chooses differently from what the witch would (`act7_town_chose`).
- **Гаврила shows the half-lamp in public;** people like it for what it is; nobody asks for more.
- **Exit:** the next morning: `story.act` = act8.

### Act VIII: the ordinary flower (area `act8`)

Place: street (the shop's front step).

- **The flower:** an ordinary flower through a crack in the step, not hers and not his. Its options: look, touch the
  petal, leave it be. No cast, no take, no reward, at most two short lines. Seen `act8_flower` only. `gold.known` =
  true (a gentle gold light on her face is the whole of «Встречаю»).
- **Exit:** after meeting it and going anywhere: evening (`story.act` = act9).

### Act IX: the invitation (area `act9`)

Places: street, shop.

- **The impossible event (X37):** every clock stops on the same second and smiles; a gold glow comes down the street;
  the shop bell rings with nobody at the door. Evidence for three readings: fog-dew on the step (the Fog), Тень's
  knot on the bell rope (Тень), the jars humming in tune (her own magic). Looking records seen entries; what happened
  stays untestable `act9_what_happened` (UNRESOLVED_BY_DESIGN).
- **Тень at the open door:** «Привет.» … «Пойдём.» The only way on is to go with her (she may look around first). An
  `ending` presentation: the witch walks out of frame, the camera stays. `story.act` = postgame; `witch.place` stays
  `shop` as the viewpoint, and the postgame mode hides the avatar.

### Postgame: the player looks back (area `postgame`)

Places: shop, attic, basement, garden, garden_below (dust). No avatar: a tap opens options directly; looking is the
only verb.

- **The house is lived in:** objects have new uses (Гаврила's half-lamp in the kitchen, Tomas's spare cam as a
  bookend), the wand's trace by branch (the pieces in a jar, the wand in the satchel on the hook, the wand stirring
  Гаврила's glue, the crate in the basement), «Ведь мы были здесь» scratched on the doorframe.
- **The gift mystery:** the knot on the swing (prologue), the coin's string (act II), the hotel key with the garden's
  number on its tag (act III), the pressed sunflower petal (act VI), his key on the hook (act I). Three seen: inferred
  `postgame_she_knew_him`; with the petal and the knot: inferred `postgame_he_asked_her` (SUPPORTED at most, never
  ESTABLISHED: he asked Тень to look after her). The three truths stay side by side: `postgame_he_left` (seen),
  `postgame_he_chose` (heard, from act I), `postgame_he_cared` (inferred).
- **No end screen:** closing the notebook returns to the menu.

## 7. Workcells (this sweep)

Each builder owns whole files; shared wiring belongs to the integrator. Read sets are the frozen base (the commit the
cell starts from) plus `docs/design/BIBLE.md`, this spec and `docs/engine/CONTENT_PACKAGES.md`.

| cell | builds | writes |
|---|---|---|
| FW | places and room switching (painted, hall, stand-in stage), the full-game boot from the main menu (game scope, the `core` world), hotspots for painted rooms through Mirror affordances and plaques, NPC presence and spots for every NPC, the witch as a target, storylets after every action and place change, the postgame mode (no avatar), the clock's event budget (a six-hour idle session stays under the cap), save and load of the place, the `ending` kind, the hall's arrival storylet gated by place, goldens if a root change rotates them; calls `SystemsPresenters.register` once from the game root | `game/main/**`, `game/world/places/**` (new), `game/interaction/**`, `game/world/room_slot.gd`, `game/world/painted/**`, `data/world/places/**`, root `data/mirror/*.json` and `data/mirror/actions/*.json`, `tests/world/**`, `tests/interaction/**`, `tests/golden/**` |
| SYS | the notebook (seven kinds from the sidecars, the diegetic notebook opened from the witch), чуйка (sidecar, ghost presenter), the `flash`, `sight` and `notebook` presentation kinds (registered through `SystemsPresenters.register(director, host)`), the magic modes' looks (violet, verdigris, gold) | `game/mirror/notebook_view.gd`, `game/presentation/systems_presenters.gd` and new files beside it, `game/ui/notebook_*`, `game/presentation/magic_presentation.gd`, `tests/systems/**` |
| A | prologue and act I | `data/mirror/areas/{prologue,act1}/**`, `data/text/ru/{prologue,act1}.json`, `data/conversations/{prologue,act1}*.dialogue`, `data/world/hotspots/{prologue,act1}.json`, `data/notebook/{prologue,act1}.json`, `data/expectations/{prologue,act1}.json`, `data/sim/{prologue,act1}*.json`, `tests/content/test_{prologue,act1}*.gd` |
| B | acts II and VI | the same pattern for `act2`, `act6` |
| C | acts III, IV and V | the same pattern for `act3`, `act4`, `act5` |
| D | acts VII, VIII, IX and the postgame | the same pattern for `act7`, `act8`, `act9`, `postgame` |
| ART | plates for the new places (Hugging Face Space, quota permitting, in the order fog_edge, garden_below, hotel, attic, basement, threshold, clocktower), the painted-room pipeline, the visual gauntlet against references 13, 15, 16, 17, 04 | `tools/hfspaces/**`, `assets/painted/<new places>/**`, `docs/art/**` (new files) |
| CHARS | the witch's copper-ginger hair, blue-grey eyes and violet pointed hood; crude NPC models (Мирон, Элиан, Вера, Илья, Дворник; Тень from `shadow.glb`); the concierge as a cutout or crude bird | `tools/characters/**` (new builders), `assets/characters/**`, `game/world/character_models.gd` |
| QA | the constitution's verifiers, the tone linter over the Russian text, per-act progress checks, the whole-game sim, the game-scope catalog test | `tests/content/test_game_scope_catalog.gd`, `tests/design/**`, `game/mirror/tone_lint.gd` (Russian rules), `tools/text_tool.py` (lint rules) |

The integrator (the coordinating session) owns: `docs/PLAN.md`, `docs/design/GAME_SPEC.md`, `CLAUDE.md`,
`architecture/**`, `data/mirror/areas/core/**`, `data/text/ru/core.json`, `project.godot`, `export_presets.cfg`, CI,
the tracker, and merging.
