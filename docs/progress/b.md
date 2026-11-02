# Workcell B: acts II and VI (progress and resume notes)

Base: 75de726. Branch: worktree-agent-a77d0633e442fe340. Worktree:
/home/user/witch/.claude/worktrees/agent-a77d0633e442fe340. Not pushed.

Russian text lives only in data/text/ru/act2.json and data/text/ru/act6.json. Everything else uses keys.
This file has no Cyrillic on purpose (the text-single-source test scans docs/).

## Files

- data/mirror/areas/act2/ (world.json, actions.json, storylets.json)
- data/mirror/areas/act6/ (same)
- data/text/ru/act2.json, data/text/ru/act6.json
- data/conversations/act2.dialogue, act6.dialogue (linear, no responses; titles start with the area id)
- data/notebook/act2.json, act6.json (claim -> kind -> note key)
- data/expectations/act2.json, act6.json (chuika ghosts)
- data/world/hotspots/act2.json, act6.json (painted-room targets; coordinates on the 1280x720 plates)
- data/sim_pending/act2_main.json, act6_main.json (integrator moves them to data/sim/)
- tests/content/test_act2_*.gd, test_act6_*.gd

## Interfaces published

Act II: act2_magic_failing, act2_lamps_without_me, act2_elian_company, act2_vera_wait_helped,
act2_vera_direct_helped, act2_ilya_backwards, act2_raccoon_hid_it, act2_shadow_coin (claim and world
act2_shadow_coin {"left": true}). Extra claims (listed in the report): act2_vera_not_now,
act2_vera_sign_fell, act2_clock_fixed, act2_raccoon_refused.

Exit (act II): trapdoor in the shop -> story.act act3, magic.state below, witch basement from shop,
npc raccoon with_witch, npc elian place "" (he goes home). Two actions share the target: the operator
variant (requires op.ask_before_acting) and the quiet variant (npc.tomas.stance quiet). Both need three
of five items: lamps (act2_lamp lit_by_janitor), Elian (address ty), both Vera contexts (oven solved and
sign caught), Ilya (act2_clock shown or fixed), Gavrila's refusal (act2_raccoon_commission refused).

## Mechanics chosen (and why)

- Storylets are presentation only in this engine (consume_storylet emits content, no effects), so every
  state change is an action response. NPC arrivals happen on the witch's LOOK or WAIT (their own action).
- Items for the exit are world flags, because preconditions are AND/OR over world state only; claims are
  AND-only in requires_claims. Combinations of three are generated with $any/$all.
- The raccoon moves to the attic when the witch looks at the ladder (npc.raccoon.place attic), so attic
  scenes have him present. Core owns the ladder GO; the ladder LOOK is ours.
- Violet casts in act II: every CAST action requires magic.state failing and uses magic effect "fizzle".
- Act VI has no CAST actions. Operator-gated options: asking Tomas (second machine) and asking Gavrila
  before suggesting. Operator op.act3_revise_before_repeating is not referenced yet (act III missing;
  the validator would reject an unknown operator).

## Status

- Act II: in progress (see git log for the committed slices).
- Act VI: not started.

## Needs from the integrator

- magic_presentation.gd must handle effect "fizzle" (SYS). Only repair and flourish exist today.
- The hall's cast_repair and cast_flourish (data/mirror/actions/cast.json, root) are not gated by act;
  they stay available in acts II and VI. Gate them or accept the hall-only casts.
- Hotspot for ladder_shop_attic is in act2.json; core should not duplicate it.
- Act III operator op.act3_revise_before_repeating: act VI does not use it yet.
- Storylet "act2_morning" and "act2_attic_dust" are presentation only (FW selects them).

## Voice budgets (VOICES.md)

- Reserved phrase "fine, don't": 1 used in act II (after Gavrila's refusal). Budget 4; act IV has one.
- Reserved greeting (Shadow): act VI uses it per the brief and GAME_SPEC; VOICES reserves the pair for act IX. Flagged.
