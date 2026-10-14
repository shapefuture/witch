# Navigation: what Alone in the Dark teaches us

Requested by the user: how *Alone in the Dark* works, because it is close to the navigation they have in mind.

**Correction:** *Alone in the Dark* was released in **1992**, not 1982. It was published by Infogrames for MS-DOS,
and Frédérick Raynal designed it. Sources:

- [Alone in the Dark (1992 video game), Wikipedia](https://en.wikipedia.org/wiki/Alone_in_the_Dark_(1992_video_game))
- [Alone in the Dark, The Register (2013 article on the original code)](https://www.theregister.com/2013/10/31/antique_code_show_alone_in_the_dark/)
- [Alone in the Dark, retro review by DarkwyndPT](https://www.indieretronews.com/2019/09/alone-in-dark-survival-horror-classic.html)

Publisher credits differ between sources (Wikipedia gives I•Motion/Interplay for North America; others name
Infogrames and Krisalis). Nothing below depends on that.

## How it navigates

1. **Fixed camera over pre-rendered backgrounds.** The backdrops are 2D images; the characters and objects are
   3D polygons on top. A walk-through 3D house was not feasible on the hardware of the time. This is a technical
   constraint that became the look.
2. **The viewpoint changes at room and corridor boundaries.** Entering a new room or corridor cuts to a new fixed
   angle (The Register). The cut works like a film cut, which is how the design was discussed.
3. **Tank controls.** Up moves the character forward relative to its facing, not relative to the camera. After a
   cut the camera is different, so "forward" changes with the view, and reviewers found this annoying in fights.
4. **Reception.** Reviews judged the fixed views from adequate to poor. The approach is credited with shaping
   Resident Evil and Silent Hill.

## How it compares with our rules

| Alone in the Dark | Witch (current rules, `CLAUDE.md`) | What we take |
|---|---|---|
| Pre-rendered 2D backdrops, 3D characters | Pre-rendered plates over a low-poly proxy, 3D characters | Same technique; ours adds occlusion through the proxy. Our plates are the bar in `docs/visual-gauntlet/`. |
| Camera cuts at room and corridor boundaries | Bolted camera; shot changes are cuts; only the spell eases | Matches. Keep the cut as a framing decision. |
| Tank controls, relative to the character's facing | **Pointer only.** Tap or click the ground to walk; no WASD | We avoid the re-orientation problem, because a tap names a place, not a direction. |
| Controls change after a cut | A tap after a cut must resolve against the new camera (to be checked in code) | Open: see N2 below. |

## Decisions this raises

- **N1. Input mode.** Keep pointer-only (default, per `CLAUDE.md`), or add a keyboard or gamepad mode with
  tank-style movement for desktop and accessibility. Changing the default means revising the input invariant.
- **N2. What a cut does to a walk in progress.** Default: the walk is cancelled at the cut, and the player taps
  again in the new view. The alternative is to finish the walk in the new camera, which can read as the
  character teleporting. The Register reports that the shifts were most annoying mid-fight, because the controls
  had to re-orient; the default avoids that by not carrying a walk across a cut. Whether the code already does
  this is to be checked in `game/` before the default is recorded as built.
- **N3. Cut during a reaction.** A Minds reaction should not be interrupted by a room cut. Default: a cut waits
  until the reaction's subtitle has finished (the action queue already sequences presentations).

## What we do not copy

- Tank controls as the only input (N1 is open; the default stays pointer-only).
- Fixed angles that change while the player is in a fight. The game has no combat in the current design.
- Any claim about how AITD handled occlusion. The sources above do not say, so this document makes none.
