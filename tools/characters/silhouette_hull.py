#!/usr/bin/env python3
"""The visual hull of a character from its cut-out views: no network, no GPU, a few seconds on one CPU core.

    python tools/characters/silhouette_hull.py build/views/witch_t_nolegs/views hull.glb [--faces 30000] [--size 224] [--diag]

A voxel stays solid only if it falls inside the silhouette of every view (front, right, back, left; `--diag` adds the two 3/4 views, dilated more because they are not
exactly 45 degrees). Surface by marching cubes on a blurred occupancy, then Taubin smoothing and a quadric decimation. The views are orthographic and the figure is the same
height in all of them (tools/characters/multiview.py makes them so), which is all the camera the carving needs.

What it is for: a free first shape to paint (image2rig.py paint), a deformation target for a template, a prototype to look at before spending quota.
What it is not: it has no face relief and no concavities (a silhouette cannot see them), and a hat brim comes out as the intersection of two silhouettes.
"""
import argparse
import sys
from pathlib import Path

import numpy as np

CAM = {"front": (1.0, 0.0), "right": (0.0, 1.0), "back": (-1.0, 0.0), "left": (0.0, -1.0)}    # image u = ux * x + uz * z (image2rig.CAMERAS)
DIAG = {"front34": (0.7071, 0.7071), "back34": (-0.7071, -0.7071)}


def _mask(path):
    from PIL import Image
    return np.asarray(Image.open(path).convert("RGBA"))[..., 3] > 127


def landmarks(front):
    """From the front cut-out of a T-pose figure, in units of its height: the arm row, the half span and the torso's half width."""
    m = _mask(front)
    ys, xs = np.where(m)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    height = float(y1 - y0)
    arm_row = float(np.median(np.concatenate([ys[xs <= x0 + 3], ys[xs >= x1 - 3]])))
    lo, hi = int(arm_row + .05 * height), int(arm_row + .25 * height)
    widths = [np.ptp(np.where(m[r])[0]) for r in range(lo, hi) if m[r].any()]
    span = (x1 - x0) / 2 / height
    return {"arm_y": (y1 - arm_row) / height, "span": span, "torso": min(min(widths) / 2 / height if widths else .12, span * .5)}


def load_views(folder, diag=False):
    """{name: (mask, (x0, x1, y0, y1))} with the mask grown a little (the views disagree by a few pixels)."""
    from scipy import ndimage
    out = {}
    for name in list(CAM) + (list(DIAG) if diag else []):
        m = _mask(Path(folder) / (name + ".png"))
        ys, xs = np.where(m)
        if not len(xs):
            raise SystemExit("%s is empty" % name)
        out[name] = (ndimage.binary_dilation(m, iterations=3 if name in CAM else 14), (int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())))
    return out


def carve(views, size=224, half_x=0.62, half_z=0.45, arm=None):
    """Occupancy over x in [-half_x, half_x], y in [0, 1] (the figure's height), z in [-half_z, half_z]; returns (occupancy, (xs, ys, zs)).
    `arm` = (landmarks, radius): outboard of the torso, in the arm's row band, a limb is a tube `radius` deep (units of the height). Two silhouettes cannot see how thin an
    arm is: without this the arm comes out as deep as the body, and swings through it when the rig lowers it."""
    height = float(np.mean([views[n][1][3] - views[n][1][2] for n in CAM]))
    xs = np.linspace(-half_x, half_x, size)
    zs = np.linspace(-half_z, half_z, size * 3 // 4)
    ys = np.linspace(0.0, 1.0, size * 2)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    occ = np.ones(X.shape, bool)
    for name, (m, (x0, x1, _y0, y1)) in views.items():
        ux, uz = CAM.get(name) or DIAG[name]
        px = np.rint((x0 + x1) / 2 + (ux * X + uz * Z) * height).astype(int)
        py = np.rint(y1 - Y * height).astype(int)
        ok = (px >= 0) & (px < m.shape[1]) & (py >= 0) & (py < m.shape[0])
        inside = np.zeros(X.shape, bool)
        inside[ok] = m[py[ok], px[ok]]
        occ &= inside
    if arm:
        lm, radius = arm
        band = (np.abs(Y - lm["arm_y"]) < .07) & (np.abs(X) > lm["torso"] * 1.15)
        occ &= ~(band & (np.abs(Z) > radius))
    return occ, (xs, ys, zs)


def surface(occ, axes, smooth_iters=12):
    """Largest solid piece to a smoothed triangle mesh (positions, faces)."""
    from scipy import ndimage
    from skimage import measure
    import trimesh
    occ = ndimage.binary_opening(occ, iterations=1)
    lab, n = ndimage.label(occ)
    if n > 1:
        sizes = ndimage.sum(occ, lab, range(1, n + 1))
        occ = lab == 1 + int(np.argmax(sizes))
    xs, ys, zs = axes
    blurred = ndimage.gaussian_filter(occ.astype(float), 1.2)
    verts, faces, _, _ = measure.marching_cubes(blurred, 0.5, spacing=(xs[1] - xs[0], ys[1] - ys[0], zs[1] - zs[0]))
    verts += np.array([xs[0], ys[0], zs[0]])
    mesh = trimesh.Trimesh(verts, faces)
    trimesh.smoothing.filter_taubin(mesh, iterations=smooth_iters)
    return np.asarray(mesh.vertices), np.asarray(mesh.faces)


def hull(folder, faces=30000, size=224, diag=False, arm_depth=0.0):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import image2rig as ir
    views = load_views(folder, diag)
    occ, axes = carve(views, size, arm=(landmarks(Path(folder) / "front.png"), arm_depth) if arm_depth else None)
    P, F = surface(occ, axes)
    return ir.simplify(P, F, faces)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("views")
    ap.add_argument("dest")
    ap.add_argument("--faces", type=int, default=30000)
    ap.add_argument("--size", type=int, default=224)
    ap.add_argument("--diag", action="store_true", help="also use the two 3/4 views")
    ap.add_argument("--arm-depth", type=float, default=0.0, help="T-pose figures: make the arms tubes this deep (a fraction of the height, e.g. 0.05)")
    a = ap.parse_args(argv)
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import image2rig as ir
    P, F = hull(a.views, a.faces, a.size, a.diag, a.arm_depth)
    ir.write_glb(a.dest, P, F)
    print("%s: %d triangles, %.2f x %.2f x %.2f" % ((a.dest, len(F)) + tuple(np.ptp(P, axis=0))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
