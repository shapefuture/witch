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

## Act VI (published, exit, lamp fix)

- Published claims: act6_tomas_finished_it, act6_elian_ty, act6_vera_cart, act6_vera_customer (both new Vera
  contexts), act6_ilya_together, act6_half_light, act6_shadow_flower (claim and world act6_shadow_flower {"left": true}).
- Exit (the jars, shop): story.act act7 once act6_lamp is sat (the half-light) and two of five items hold:
  act6_done_tomas, act6_done_elian, act6_done_vera, act6_done_ilya, act6_shadow_flower left.
- Softlock fix: an unasked suggestion covers the lamp (act6_lamp covered). Gavrila takes the cloth off on a wait
  (act6_uncover_lamp, a WAIT that sets shown), so the half-light stays reachable. Test:
  test_suggesting_covers_the_lamp_and_waiting_has_him_uncover_it, and the worst-choices route in
  test_the_exit_stays_reachable_after_the_worst_choices. The sim is data/sim_pending/act6_main.json.
- Vera's two contexts: the cart (acting at once, GO, is right; waiting crashes it) and the customer (waiting is
  right; stepping in spoils the deal). Same verbs, opposite outcomes (C7).
- Tomas's second machine targets tomas: asking first needs op.ask_before_acting; taking the tools leaves the work
  to the witch (no claim).

## Status

- Act II: done (commit 74441d9, now in the integrated branch). The listening LOOK on the attic ladder uses core's
  ladder hit area (target ladder_shop_attic, core hotspot at 530,420 radius 48). act2.json has no ladder entry.
- Act VI: done in the commit that carries this note (22 actions, 1 storylet, 16 dialogues, 7 claims).

## Needs from the integrator

- magic_presentation.gd must handle effect "fizzle" (SYS). Only repair and flourish exist today.
- The hall's cast_repair and cast_flourish (data/mirror/actions/cast.json, root) are not gated by act;
  they stay available in acts II and VI. Gate them or accept the hall-only casts.
- ladder_shop_attic: core's hotspot serves both the exit and act II's listening LOOK. No act2 entry, no duplicate.
- Act III operator op.act3_revise_before_repeating: act VI does not use it yet.
- Storylet "act2_morning" and "act2_attic_dust" are presentation only (FW selects them).

## Voice budgets (VOICES.md)

- Reserved phrase "fine, don't": 1 used in act II (after Gavrila's refusal). Budget 4; act IV has one.
- Reserved greeting (Shadow): act IX already spends the one allowed greeting (dlg.act9_shadow_hi.1, the voice
  lint budget is 1). Act VI's Shadow says a different line on the step (dlg.act6.shadow_hello.1), as VOICES asks
  (her earlier lines are other words). The brief and GAME_SPEC asked for the greeting in act VI: conflict, flagged.
