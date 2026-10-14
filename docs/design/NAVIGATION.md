# Navigation: mobile first, desktop second

Status: working design. Decisions N1 to N3 are **educated guesses** taken on 2026-10-14, because the user asked for
guesses rather than questions. They are recorded in `docs/PLAN.md` section 3, marked to confirm. Touch and mouse
produce the same intent (`CLAUDE.md` invariant), so the design below holds for both.

## 1. Rules the player should feel

1. **One gesture: tap.** Walk, look, talk, choose and advance are all taps. No drag, pinch, swipe, long-press or
   double-tap. Nothing depends on hover.
2. **The camera is not the player's.** Fixed angles; the camera cuts at room boundaries (as in *Alone in the Dark*).
   The player never pans, rotates or zooms. A tap resolves against the camera the player is looking at, now.
3. **The world carries the menus.** Choices, items, knowledge and objectives live in the scene (strips, a satchel,
   a letter cabinet), not in a HUD bar.
4. **Thumb reach.** The satchel and the advance control sit in the lower corners. The upper part of the screen is
   for the scene and the subtitle.
5. **No timers.** Dialogue waits for a tap. A later setting may add auto-advance; it is off by default.
6. **Readable at base scale.** Text is judged on the 360-row base viewport on a phone. Guess: body text at least 14 px
   at that scale, with high contrast on the subtitle box.

## 2. Tap by tap

| The player | The game | Notes |
|---|---|---|
| Taps a walkable place | The witch walks there; a 3D ring marks the target and fades on arrival | A new tap replaces the walk. No queue. |
| Taps an unwalkable place | Walks to the nearest walkable point within about 1 m; otherwise the ring flashes once | Never walks into a wall silently |
| Taps an object | Option strips appear beside it (up to four, full width, one sentence each) | Options are words, never the internal verbs (`DESIGN_INVARIANTS.md`) |
| Taps an option | It runs. The chosen strip takes a wax seal until the reaction ends | Same intent as a click |
| Taps outside the strips | The strips close | A closing tap does not also walk |
| Taps the subtitle box | Advances to the next line | The whole box is the target |
| Taps Skip (shown after the first tap on a long line) | The rest of the reaction plays at once | Guess: Skip appears only on lines longer than one screen |
| Walks into an exit | The room cuts (GO) | Exits are authored doors or arches, not invisible zones |
| Taps the satchel | Opens the letter cabinet: items, what the witch knows of each custom, objectives | One object in the lower corner |
| A new item arrives | A card slides out of the satchel and rests in the corner until tapped | Replaces a sidebar notice |

## 3. The interface (SC1 recommendation)

- **No counters, bars or sidebars.** The no-2D-UI rule stays. The numeric overlays in `02_river_lake_scene.png` (U/0,
  I0) are not adopted.
- **Choices as paper strips** (`06`): full width, readable, and a seal marks the chosen line. The shape and the text
  carry the meaning, not colour alone.
- **Subtitles as a dark translucent box** with a small advance arrow (`09`).
- **One satchel for knowledge, inventory and objectives.** It opens as a letter cabinet (the `06` idea). This is
  where the Minds layer's "what the witch knows of a custom" is shown (REQ-04).
- **Declined for phones:** the bubble bar along the bottom with corner Load and Save (`08`), the full-height sidebar
  with the NEW ITEM notice (`10`), the bottom tray of item cards (`07`). Each covers the scene, and the fixed camera
  already gives the same information in the world.
- **Pause, save and load** stay in the pause slab, opened from a corner icon.

## 4. Camera and cuts

- Bolted camera. A cut at each room boundary is a framing decision, not a transition the player controls.
- **N2 (guess):** a walk in progress is cancelled at a cut. A tap in the new view starts a new walk, so the witch
  never appears to continue a path in a camera that no longer matches it.
- **N3 (guess):** a Minds reaction is not interrupted by a cut. The cut waits until the subtitle box clears; a tap
  advances faster.
- A cut never happens with a strip open. Open strips close first.

## 5. Acceptance checks (to build, gated by DESIGN-FREEZE)

- Every interactive target is at least 48 dp on a phone (device check; a headless layout check at the 360-row base).
- Every action completes with one tap. No test needs hover, drag or double-tap.
- The satchel and the advance control sit in the lower third, on a 16:9 and a 19.5:9 phone profile.
- A subtitle never advances on a timer.
- Every option label is present in the scene, not in a tooltip.
- Tap equals click (the existing input-equivalence test).

## 6. Desktop (second)

- The same taps with a mouse. Hover may show the walk ring sooner, but nothing depends on it.
- Keyboard: accelerators only. Space or Enter advances a subtitle, Esc pauses (already in place). No movement keys
  (`CLAUDE.md`, "no WASD"). Adding Space and Enter changes the input wording and needs confirming (N1).
- Layout is checked at 16:9 and 21:9. The 360-row base scales with the aspect (`expand`), so wide screens gain
  scene, not larger controls.

## 7. Decisions taken as guesses (2026-10-14)

- **N1. Input.** Touch and mouse are primary. No tank controls and no movement keys. Keyboard accelerators only.
  **To confirm:** this rewords the rule from "pointer only" to "no movement keys", and that is a `CLAUDE.md` edit.
- **N2. A walk and a cut.** The walk is cancelled at the cut.
- **N3. A cut and a reaction.** The cut waits for the subtitle; a tap advances faster.

## 8. Alone in the Dark (1992): what we take

Requested by the user: how *Alone in the Dark* works, because it is close to the navigation they have in mind.

**Correction:** it was released in **1992**, not 1982. It was published by Infogrames for MS-DOS, and Frédérick Raynal
designed it. Sources:

- [Alone in the Dark (1992 video game), Wikipedia](https://en.wikipedia.org/wiki/Alone_in_the_Dark_(1992_video_game))
- [Alone in the Dark, The Register (2013 article on the original code)](https://www.theregister.com/2013/10/31/antique_code_show_alone_in_the_dark/)
- [Alone in the Dark, retro review by DarkwyndPT](https://www.indieretronews.com/2019/09/alone-in-dark-survival-horror-classic.html)

Publisher credits differ between sources (Wikipedia gives I•Motion/Interplay for North America; others name
Infogrames and Krisalis). Nothing below depends on that.

What it did:

1. **Fixed camera over pre-rendered backgrounds.** The backdrops are 2D images; the characters and objects are 3D
   polygons on top. A walk-through 3D house was not feasible on the hardware of the time.
2. **The viewpoint changes at room and corridor boundaries.** Entering a new room or corridor cuts to a new fixed
   angle (The Register).
3. **Tank controls.** Up moves the character forward relative to its facing, not relative to the camera. After a cut,
   "forward" changes with the view, and the controls re-orient; The Register notes this was most annoying mid-fight.
4. **Reception.** Reviews judged the fixed views from adequate to poor. The approach is credited with shaping
   Resident Evil and Silent Hill.

What we take and what we leave:

- **Take:** the fixed camera, the cut at room boundaries, and the pre-rendered look (our plates add occlusion through
  the proxy).
- **Leave:** tank controls as the input (N1). A tap names a place or an option, so it never needs a facing.
- **Not claimed:** how AITD handled occlusion. The sources above do not say.
