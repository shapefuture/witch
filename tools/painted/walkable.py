#!/usr/bin/env python3
"""Derives where a character may stand in a painted room, from the room's own depth (an experiment).

    python tools/painted/walkable.py assets/painted/hall_clean [--preview walkable.png] [--check]

Reads room.json (the calibrated depth grid, the camera, the actors' feet) and props.json (the lifted objects),
and writes a "walkable" block back into room.json; nothing else in the file changes.

1. The depth grid is lifted to 3D points (the painting's camera, metres) and smoothed; a surface normal and a
   height above the floor plane (y = 0) come from it.
2. Floor is a surface that faces up (normal.y > MIN_NY) and lies near the floor plane: within FLOOR_BELOW
   under it and MAX_STEP above it (the dais the statue stands on is a step of 0.2-0.4 m: the depth model
   smooths it into a ramp, which is what the character climbs). It must be connected, on screen, to the
   witch's feet; objects (the lifted props) are not floor.
3. The floor is rasterised into a coarse grid in world x/z (CELL metres), each cell keeping its mean height.
4. What a lifted prop hides is not in the painting: cells that project inside a prop's mask but have floor to
   both sides of them are filled (height interpolated across), so the character can walk behind the statue.
   The prop's own footprint is an obstacle (a disc under its pivot).
5. Cells too near the edge of the floor or of an obstacle for the character's body (CLEARANCE), or whose feet
   would leave the frame, are not standable. The bolted camera never follows, so the frame is the stage.

The block: cell size, grid origin (world x, z of the grid's corner), rows of characters ('#' the character's
centre may be here, '+' floor, but too close to an edge, '.' not floor), and heights_cm (the floor's height
per cell, row by row). Everything is world metres in the painting's camera frame (camera at x = 0, z = 0,
looking down -z).
"""
import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

CELL = 0.25            # metres; the nav grid of game/world/painted/painted_walkable.gd
MIN_NY = 0.85          # up-facing surface: normal.y (about 32 degrees of slope)
FLOOR_BELOW = 0.12     # metres below the floor plane that still counts as floor (depth noise)
MAX_STEP = 0.36        # metres above the floor plane: the dais (0.3) is walkable, a rock or a shelf plinth is not
SMOOTH_PX = 4.0        # smoothing of the lifted points before the normal is taken
CLEARANCE = 0.30       # the character's radius: the stored region is where her centre may be
MIN_FOOTPRINT = 0.40   # a prop's footprint radius is read from its mask, but never smaller than this
FRAME_MARGIN = (60, 24)   # pixels of the frame (sides, bottom) that the feet keep clear of
MIN_PIXELS = 3         # floor pixels a cell needs
FILL_RUN = 12          # cells: the widest hidden gap that is bridged between floor on both sides
PROP_GROW = 3          # pixels: a prop's mask grows by this before it hides floor
HIDDEN_GROW = 3        # cells: depth beside a tall prop is smeared, so what lies this near its shadow is rebuilt too
FAR_LIMIT = 11.0       # metres of camera depth: beyond it the monocular depth is not trusted to walk on


class Camera:
    def __init__(self, room):
        self.w, self.h = room["image_size"]
        self.eye = float(room["eye_height"])
        self.pitch = math.radians(room["pitch_deg"])
        self.f = (self.h / 2.0) / math.tan(math.radians(room["fov_v"]) / 2.0)
        self.up = np.array([0.0, math.cos(self.pitch), math.sin(self.pitch)])
        self.fwd = np.array([0.0, math.sin(self.pitch), -math.cos(self.pitch)])

    def rays(self, xs, ys):
        dx = (xs - self.w / 2.0) / self.f
        dy = -(ys - self.h / 2.0) / self.f
        return dx[..., None] * np.array([1.0, 0.0, 0.0]) + dy[..., None] * self.up + self.fwd

    def to_pixel(self, x, y, z):
        """Painting pixel of world points (arrays)."""
        rel = np.stack([x, y - self.eye, z], axis=-1)
        depth = rel @ self.fwd
        return (self.w / 2.0 + self.f * rel[..., 0] / depth, self.h / 2.0 - self.f * (rel @ self.up) / depth)


def depth_image(room):
    gw, gh = room["grid_size"]
    step = room["grid_step"]
    w, h = room["image_size"]
    grid = np.array(room["depth_grid"], np.float32).reshape(gh, gw)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    return ndi.map_coordinates(grid, [ys / step, xs / step], order=1, mode="nearest")


def lift(room, cam):
    z = depth_image(room)
    ys, xs = np.mgrid[0:cam.h, 0:cam.w].astype(np.float32)
    rays = cam.rays(xs, ys)
    points = np.array([0.0, cam.eye, 0.0]) + rays * z[..., None]
    return points, rays


def surface_normals(points, rays):
    smooth = np.stack([ndi.gaussian_filter(points[..., i], SMOOTH_PX) for i in range(3)], axis=-1)
    n = np.cross(np.gradient(smooth, axis=1), np.gradient(smooth, axis=0))
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    toward = -rays / np.linalg.norm(rays, axis=-1, keepdims=True)
    n *= np.sign((n * toward).sum(-1))[..., None]
    return smooth, n


def prop_masks(room_dir, size):
    """Each lifted prop's full-frame mask, and its pivot pixel (props.json); empty without props.json."""
    path = Path(room_dir) / "props.json"
    out = []
    if not path.exists():
        return out
    w, h = size
    for prop in json.loads(path.read_text(encoding="utf-8")).get("props", []):
        full = np.zeros((h, w), bool)
        if prop.get("kind") == "cutout":
            x, y, rw, rh = prop["rect"]
            m = np.asarray(Image.open(Path(room_dir) / prop["mask"]).convert("L").resize((rw, rh)), np.uint8) > 127
            x1, y1 = min(x + rw, w), min(y + rh, h)
            full[y:y1, x:x1] = m[: y1 - y, : x1 - x]
        elif "polygon" in prop:
            canvas = Image.new("L", (w, h), 0)
            ImageDraw.Draw(canvas).polygon([tuple(p) for p in prop["polygon"]], fill=255)
            full = np.asarray(canvas) > 127
        else:
            continue
        pivot = prop.get("pivot")
        if pivot is None:
            ys, xs = np.where(full)
            pivot = [float(xs.mean()), float(ys.max())]
        out.append({"id": prop["id"], "mask": full, "pivot": [float(pivot[0]), float(pivot[1])]})
    return out


def floor_pixels(room, cam, points, rays, props):
    smooth, normal = surface_normals(points, rays)
    height = smooth[..., 1]
    mask = (height > -FLOOR_BELOW) & (height < MAX_STEP) & (normal[..., 1] > MIN_NY)
    mask &= -points[..., 2] < FAR_LIMIT
    mask = ndi.binary_opening(mask, iterations=2)
    for prop in props:
        mask &= ~ndi.binary_dilation(prop["mask"], iterations=PROP_GROW)
    labels, _ = ndi.label(mask)
    witch = room["actors"]["witch"]["pixel"]
    label = labels[int(witch[1]), int(witch[0])]
    if label == 0:
        raise SystemExit("the witch's feet (%s) are not on the floor the depth gives" % witch)
    return labels == label, smooth


def footprint(prop, cam, points):
    """Where a prop stands: a disc (centre x, z and radius in metres) under its pivot, as wide as its mask is
    near its bottom."""
    ys, xs = np.where(prop["mask"])
    bottom = ys.max()
    near = ys > bottom - max(8, int((bottom - ys.min()) * 0.25))
    width_px = float(max(xs[near & (ys == row)].max() - xs[near & (ys == row)].min() for row in np.unique(ys[near])))
    px, py = prop["pivot"]
    p = points[int(py), int(px)]
    radius = max(MIN_FOOTPRINT, width_px * 0.5 * -p[2] / cam.f)
    return {"id": prop["id"], "at": [float(p[0]), float(p[2])], "radius": float(radius), "height": float(p[1])}


def rasterise(floor, smooth, grid_box):
    x0, z0, nx, nz = grid_box
    ys, xs = np.where(floor)
    ys, xs = ys[::2], xs[::2]
    p = smooth[ys, xs]
    i = np.floor((p[:, 0] - x0) / CELL).astype(int)
    j = np.floor((p[:, 2] - z0) / CELL).astype(int)
    keep = (i >= 0) & (i < nx) & (j >= 0) & (j < nz)
    flat = j[keep] * nx + i[keep]
    count = np.bincount(flat, minlength=nx * nz).reshape(nz, nx)
    total = np.bincount(flat, weights=p[keep, 1], minlength=nx * nz).reshape(nz, nx)
    known = count >= MIN_PIXELS
    height = np.where(known, total / np.maximum(count, 1), 0.0)
    return known, height


def fill_hidden(known, height, hidden, run=FILL_RUN):
    """Cells a prop hides: filled when floor lies on both sides along a row of world x (or a column of z)."""
    filled = known.copy()
    out = height.copy()
    for axis in (1, 0):
        view = (lambda a: a) if axis == 1 else (lambda a: a.T)
        k, hgt, hid, f, o = view(known), view(height), view(hidden), view(filled), view(out)
        for r in range(k.shape[0]):
            row = k[r]
            c = 0
            n = row.shape[0]
            while c < n:
                if row[c] or not hid[r, c]:
                    c += 1
                    continue
                s = c
                while c < n and not row[c] and hid[r, c]:
                    c += 1
                if s > 0 and c < n and row[s - 1] and row[c] and c - s <= run:
                    for t in range(s, c):
                        a = (t - s + 1) / (c - s + 1)
                        f[r, t] = True
                        o[r, t] = hgt[r, s - 1] * (1 - a) + hgt[r, c] * a
    return filled, out


def build(room, room_dir):
    cam = Camera(room)
    points, rays = lift(room, cam)
    props = prop_masks(room_dir, (cam.w, cam.h))
    floor, smooth = floor_pixels(room, cam, points, rays, props)

    ys, xs = np.where(floor)
    p = smooth[ys, xs]
    x0 = math.floor(p[:, 0].min() / CELL - 2) * CELL
    z0 = math.floor(p[:, 2].min() / CELL - 2) * CELL
    nx = int(math.ceil((p[:, 0].max() - x0) / CELL)) + 3
    nz = int(math.ceil((p[:, 2].max() - z0) / CELL)) + 3
    known, height = rasterise(floor, smooth, (x0, z0, nx, nz))
    known = ndi.binary_closing(known, iterations=1) | known
    cx = x0 + (np.arange(nx) + 0.5) * CELL
    cz = z0 + (np.arange(nz) + 0.5) * CELL
    gx, gz = np.meshgrid(cx, cz)
    height = np.where(known & (height == 0.0), ndi.maximum_filter(height, size=3), height)

    # What each prop hides: the cells that, at the prop's foot height, project inside its mask.
    obstacles = []
    hidden = np.zeros_like(known)
    for prop in props:
        foot = footprint(prop, cam, points)
        obstacles.append(foot)
        h_ref = float(np.clip(foot["height"], 0.0, MAX_STEP))
        px, py = cam.to_pixel(gx, np.full_like(gx, h_ref), gz)
        ok = (px >= 0) & (px < cam.w) & (py >= 0) & (py < cam.h)
        inside = np.zeros_like(known)
        inside[ok] = ndi.binary_dilation(prop["mask"], iterations=PROP_GROW)[py[ok].astype(int), px[ok].astype(int)]
        hidden |= ndi.binary_dilation(inside, iterations=HIDDEN_GROW)
    known, height = fill_hidden(known, height, hidden & ~known)

    for foot in obstacles:
        known &= np.hypot(gx - foot["at"][0], gz - foot["at"][1]) > foot["radius"]

    # The frame is the stage: feet stay inside it.
    px, py = cam.to_pixel(gx, height, gz)
    known &= (px >= FRAME_MARGIN[0]) & (px < cam.w - FRAME_MARGIN[0]) & (py < cam.h - FRAME_MARGIN[1])

    # One piece, connected to the witch's feet.
    witch_p = points[int(room["actors"]["witch"]["pixel"][1]), int(room["actors"]["witch"]["pixel"][0])]
    wi, wj = int((witch_p[0] - x0) // CELL), int((witch_p[2] - z0) // CELL)
    labels, _ = ndi.label(known)
    if labels[wj, wi] == 0:
        raise SystemExit("the witch's cell is not on the cleaned floor")
    known = labels == labels[wj, wi]

    padded = np.pad(known, 1)
    distance = ndi.distance_transform_edt(padded)[1:-1, 1:-1] * CELL
    standable = known & (distance >= CLEARANCE)
    labels, _ = ndi.label(standable)
    if labels[wj, wi] == 0:
        raise SystemExit("the witch's cell is too close to the edge of the floor")
    standable = labels == labels[wj, wi]
    for name, actor in room["actors"].items():
        a = actor["position"]
        if not standable[int((a[2] - z0) // CELL), int((a[0] - x0) // CELL)]:
            print("warning: %s's feet are not on standable floor" % name)

    rows = []
    for j in range(nz):
        rows.append("".join("#" if standable[j, i] else ("+" if known[j, i] else ".") for i in range(nx)))
    heights = np.where(known, np.round(height * 100.0), 0).astype(int)
    return {
        "cell": CELL,
        "origin": [round(x0, 4), round(z0, 4)],
        "size": [nx, nz],
        "clearance": CLEARANCE,
        "rows": rows,
        "heights_cm": [int(v) for v in heights.ravel()],
        "obstacles": [{"id": o["id"], "at": [round(o["at"][0], 3), round(o["at"][1], 3)], "radius": round(o["radius"], 3)} for o in obstacles],
    }


def write_preview(room, room_dir, block, path):
    cam = Camera(room)
    img = Image.open(Path(room_dir) / "plate.png").convert("RGB").resize((cam.w, cam.h))
    draw = ImageDraw.Draw(img, "RGBA")
    x0, z0 = block["origin"]
    nx, nz = block["size"]
    cell = block["cell"]
    heights = np.array(block["heights_cm"], float).reshape(nz, nx) / 100.0
    for j, row in enumerate(block["rows"]):
        for i, ch in enumerate(row):
            if ch == ".":
                continue
            corners = []
            for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1)):
                px, py = cam.to_pixel(np.array(x0 + (i + di) * cell), np.array(heights[j, i]), np.array(z0 + (j + dj) * cell))
                corners.append((float(px), float(py)))
            draw.polygon(corners, fill=(40, 255, 80, 110) if ch == "#" else (255, 230, 40, 90), outline=(0, 0, 0, 140))
    for o in block["obstacles"]:
        ring = []
        for t in range(48):
            a = t / 48 * math.tau
            px, py = cam.to_pixel(np.array(o["at"][0] + math.cos(a) * o["radius"]), np.array(0.3), np.array(o["at"][1] + math.sin(a) * o["radius"]))
            ring.append((float(px), float(py)))
        draw.line(ring + ring[:1], fill=(255, 40, 40, 255), width=2)
    for name, actor in room["actors"].items():
        px, py = actor["pixel"]
        draw.ellipse((px - 5, py - 5, px + 5, py + 5), outline=(255, 255, 255, 255), width=2)
    img.save(path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("room_dir")
    parser.add_argument("--preview", help="write the walkable cells over the plate to this PNG")
    parser.add_argument("--check", action="store_true", help="only verify that room.json's block matches the depth")
    args = parser.parse_args(argv)
    room_path = Path(args.room_dir) / "room.json"
    room = json.loads(room_path.read_text(encoding="utf-8"))
    block = build(room, args.room_dir)
    if args.preview:
        write_preview(room, args.room_dir, block, args.preview)
    standable = sum(r.count("#") for r in block["rows"])
    print("walkable: %dx%d cells of %.2f m, %d standable, obstacles %s" % (
        block["size"][0], block["size"][1], block["cell"], standable, [(o["id"], o["at"], o["radius"]) for o in block["obstacles"]]))
    if args.check:
        same = room.get("walkable") == block
        print("room.json walkable block %s" % ("matches" if same else "DIFFERS from the depth"))
        return 0 if same else 1
    room["walkable"] = block
    room_path.write_text(json.dumps(room) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
