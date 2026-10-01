# The bar

Drop the user's reference images here. The critic compares our frames against **these files**,
not against a description of them:

    docs/visual-gauntlet/bar/reference_hall.png        the faceted library hall (the scene to build)
    docs/visual-gauntlet/bar/reference_characters.png  the witch + raccoon sheet (for when characters arrive)

Then, for each round:

    GODOT=... tools/visual_gauntlet/capture.sh docs/visual-gauntlet/rounds/rNN
    python tools/visual_gauntlet/blind_ab.py docs/visual-gauntlet/rounds/rNN/wide_169.png \
        docs/visual-gauntlet/bar/reference_hall.png /tmp/ab --print-prompt   # /tmp/ab/{A,B}.png, /tmp/ab_KEY.json
    python tools/visual_gauntlet/metrics.py docs/visual-gauntlet/rounds/rNN/*.png
    python tools/visual_gauntlet/squint.py docs/visual-gauntlet/rounds/rNN/wide_169.png docs/visual-gauntlet/bar/reference_hall.png
    python tools/visual_gauntlet/regions.py docs/visual-gauntlet/bar/reference_hall.png docs/visual-gauntlet/rounds/rNN/wide_169.png

The critic prompt is `tools/visual_gauntlet/critic_prompt.md` (see "Tools" in `BAR.md`).

`BAR.md` is a written reading of the reference, used only when the image itself is unavailable.
