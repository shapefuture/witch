# The bar

Drop the user's reference images here. The critic compares our frames against **these files**,
not against a description of them:

    docs/visual-gauntlet/bar/reference_hall.png        the faceted library hall (the scene to build)
    docs/visual-gauntlet/bar/reference_characters.png  the witch + raccoon sheet (for when characters arrive)

Then, for each round:

    GODOT=... tools/visual_gauntlet/capture.sh docs/visual-gauntlet/rounds/rNN
    python tools/visual_gauntlet/blind_ab.py docs/visual-gauntlet/rounds/rNN/wide_169.png \
        docs/visual-gauntlet/bar/reference_hall.png /tmp/ab        # A.png, B.png, KEY.json
    python tools/visual_gauntlet/metrics.py docs/visual-gauntlet/rounds/rNN/*.png

`BAR.md` is a written reading of the reference, used only when the image itself is unavailable.
