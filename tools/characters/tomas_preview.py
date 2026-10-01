#!/usr/bin/env python3
"""Previews for tools/characters/tomas.py: a small numpy rasteriser (orthographic, flat facets,
nearest-sampled face texture, skinned poses). Nothing here is shipped.

    python tools/characters/tomas_preview.py --out DIR [--sheet SHEET.webp]

DIR/tomas_6view.png    FRONT, BACK, LEFT SIDE, RIGHT SIDE and two quarter views
DIR/tomas_vs_sheet.png the sheet's three views above ours at the same scale (needs --sheet)
DIR/tomas_anim.png     frames of idle / walk / talk / work
DIR/tomas_small.png    at the size the game shows him (wide shot and close-up), nearest upscaled
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tomas  # noqa: E402

BG = np.array((.14, .14, .14))


def posed(surfaces, pose=None, offsets=None):
	m = tomas.skin_matrices(pose, offsets)
	out = {}
	for k, d in surfaces.items():
		p = np.c_[d['P'], np.ones(len(d['P']))]
		acc = np.zeros((len(p), 3))
		for slot in range(4):
			w = d['W'][:, slot]
			if not w.any():
				continue
			mm = m[d['J'][:, slot]]
			acc += w[:, None] * np.einsum('nij,nj->ni', mm, p)[:, :3]
		out[k] = dict(d, P=acc)
	return out


def render(surfaces, tex, yaw=0., pitch=0., size=(300, 460), ppm=280., centre=(0, .78, 0), light=None):
	"""Orthographic view of the model turned by `yaw` degrees (0 = his front, 90 = his left side
	towards the camera) and tilted by `pitch` (positive looks down on him)."""
	w, h = size
	ya, pa = math.radians(yaw), math.radians(pitch)
	f = np.array((-math.sin(ya) * math.cos(pa), -math.sin(pa), -math.cos(ya) * math.cos(pa)))   # camera looks along f
	r = np.cross(f, (0, 1, 0))
	r /= np.linalg.norm(r)
	u = np.cross(r, f)
	lit = light if light is not None else (-.55 * r + .65 * u - .55 * f)
	lit = lit / np.linalg.norm(lit)
	img = np.zeros((h, w, 3)) + BG
	zb = np.full((h, w), np.inf)
	c = np.array(centre, float)
	for name, d in surfaces.items():
		p = d['P'].reshape(-1, 3, 3)
		col = d['C'].reshape(-1, 3, 3)[:, 0]
		n = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
		n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
		front = n @ f < 0
		sx = w / 2 + ((p - c) @ r) * ppm
		sy = h / 2 - ((p - c) @ u) * ppm
		sz = (p - c) @ f
		uv = d['UV'].reshape(-1, 3, 2) if d.get('UV') is not None else None
		shade = .52 + .62 * np.clip(n @ lit, 0, 1)
		for i in np.nonzero(front)[0]:
			x0, x1 = int(max(math.floor(sx[i].min()), 0)), int(min(math.ceil(sx[i].max()), w - 1))
			y0, y1 = int(max(math.floor(sy[i].min()), 0)), int(min(math.ceil(sy[i].max()), h - 1))
			if x1 < x0 or y1 < y0:
				continue
			xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + .5, np.arange(y0, y1 + 1) + .5)
			x_a, x_b, x_c = sx[i]
			y_a, y_b, y_c = sy[i]
			den = (y_b - y_c) * (x_a - x_c) + (x_c - x_b) * (y_a - y_c)
			if abs(den) < 1e-12:
				continue
			l0 = ((y_b - y_c) * (xs - x_c) + (x_c - x_b) * (ys - y_c)) / den
			l1 = ((y_c - y_a) * (xs - x_c) + (x_a - x_c) * (ys - y_c)) / den
			l2 = 1 - l0 - l1
			inside = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
			if not inside.any():
				continue
			z = l0 * sz[i, 0] + l1 * sz[i, 1] + l2 * sz[i, 2]
			sub = zb[y0:y1 + 1, x0:x1 + 1]
			ok = inside & (z < sub)
			if not ok.any():
				continue
			sub[ok] = z[ok]
			if uv is not None:
				uu = l0 * uv[i, 0, 0] + l1 * uv[i, 1, 0] + l2 * uv[i, 2, 0]
				vv = l0 * uv[i, 0, 1] + l1 * uv[i, 1, 1] + l2 * uv[i, 2, 1]
				tx = np.clip((uu * tex.shape[1]).astype(int), 0, tex.shape[1] - 1)
				ty = np.clip((vv * tex.shape[0]).astype(int), 0, tex.shape[0] - 1)
				rgb = tex[ty, tx] * col[i]
				img[y0:y1 + 1, x0:x1 + 1][ok] = rgb[ok] * shade[i]
			else:
				img[y0:y1 + 1, x0:x1 + 1][ok] = col[i] * shade[i]
	return np.clip(img, 0, 1)


def to_img(a):
	return Image.fromarray((np.clip(a, 0, 1) * 255 + .5).astype('uint8'))


def label(im, text, xy):
	ImageDraw.Draw(im).text(xy, text, fill=(220, 220, 200))


def sheet_views(sheet_path, scale):
	"""The concept sheet's three Tomas views, scaled so 1 m = SHEET_PPM * scale px."""
	sh = Image.open(sheet_path).convert('RGB')
	boxes = {'front': (655, 330, 805, 655), 'side': (842, 330, 1000, 655), 'back': (1008, 330, 1166, 655)}
	out = {}
	for k, b in boxes.items():
		c = sh.crop(b)
		out[k] = c.resize((int(c.width * scale), int(c.height * scale)), Image.LANCZOS)
	return out


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument('--out', required=True)
	ap.add_argument('--sheet')
	ap.add_argument('--only', default='')
	args = ap.parse_args()
	os.makedirs(args.out, exist_ok=True)
	face_png = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
		'assets', 'characters', 'tomas_face.png')
	tex = np.asarray(Image.open(face_png).convert('RGB')).astype(float) / 255
	meta = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tomas_face.json')
	cx = tomas.SHEET_CX
	if os.path.exists(meta):
		import json
		cx = json.load(open(meta))['sheet_cx']
	surf = tomas.flatten(tomas.build_parts(cx))
	tris = sum(len(d['P']) // 3 for d in surf.values())
	print('triangles', tris)
	todo = args.only.split(',') if args.only else ['six', 'cmp', 'anim', 'small']

	if 'six' in todo:
		views = [('FRONT', 0, 0), ('BACK', 180, 0), ('LEFT SIDE', 90, 0), ('RIGHT SIDE', -90, 0),
			('FRONT-LEFT QUARTER', 40, 8), ('BACK-RIGHT QUARTER', -140, 8)]
		cell = (330, 520)
		sheet = Image.new('RGB', (cell[0] * 3, (cell[1] + 18) * 2), tuple(int(v * 255) for v in BG))
		for i, (name, yaw, pitch) in enumerate(views):
			im = to_img(render(surf, tex, yaw, pitch, cell, ppm=310., centre=(0, .80, 0)))
			x, y = (i % 3) * cell[0], (i // 3) * (cell[1] + 18)
			sheet.paste(im, (x, y))
			label(sheet, name, (x + 8, y + cell[1] + 3))
		sheet.save(os.path.join(args.out, 'tomas_6view.png'))

	if 'cmp' in todo and args.sheet:
		scale = 2.0
		ppm = tomas.SHEET_PPM * scale
		sv = sheet_views(args.sheet, scale)
		ours = {'front': (0, 0), 'side': (90, 0), 'back': (180, 0)}
		hh = sv['front'].height
		cmp_ = Image.new('RGB', (sum(v.width for v in sv.values()) + 40, hh * 2 + 40), (30, 30, 30))
		x = 0
		for k in ('front', 'side', 'back'):
			cmp_.paste(sv[k], (x, 0))
			# sheet crop rows 330..655 -> the feet (y=640) sit 310 px below the crop top
			feet_px = (tomas.SHEET_FEET - 330) * scale
			w = sv[k].width
			centre_y = (feet_px - hh / 2) / ppm
			im = to_img(render(surf, tex, ours[k][0], 0, (w, hh), ppm=ppm, centre=(0, centre_y, 0)))
			# match the sheet's horizontal placement of the body axis
			ax_px = {'front': (cx - 655) * scale, 'side': (915 - 842) * scale, 'back': (1088.5 - 1008) * scale}[k]
			shift = int(round(ax_px - w / 2))
			im = Image.fromarray(np.roll(np.asarray(im), shift, axis=1))
			cmp_.paste(im, (x, hh + 20))
			label(cmp_, 'sheet ' + k, (x + 6, hh + 4))
			label(cmp_, 'model ' + k, (x + 6, 2 * hh + 24))
			x += w + 20
		cmp_.save(os.path.join(args.out, 'tomas_vs_sheet.png'))

	if 'anim' in todo:
		rows = []
		cell = (180, 300)
		for an, (fn, dur) in tomas.ANIMATIONS.items():
			frames = []
			for k in range(8):
				t = dur * k / 8
				pose, hips = fn(t, dur)
				ps = posed(surf, pose, hips)
				yaw = 60 if an == 'work' else 35
				frames.append(to_img(render(ps, tex, yaw, 6, cell, ppm=175., centre=(0, .82, 0))))
			row = Image.new('RGB', (cell[0] * 8, cell[1] + 16), tuple(int(v * 255) for v in BG))
			for k, fr in enumerate(frames):
				row.paste(fr, (k * cell[0], 16))
			label(row, '%s  (%.1f s, 8 frames)' % (an, dur), (6, 2))
			rows.append(row)
		out = Image.new('RGB', (rows[0].width, sum(r.height for r in rows)))
		y = 0
		for r in rows:
			out.paste(r, (0, y))
			y += r.height
		out.save(os.path.join(args.out, 'tomas_anim.png'))

	if 'small' in todo:
		# the wide shot shows him ~40 px tall, a close-up ~150 px: render there, upscale nearest x4
		ims = []
		for px_tall, yaw in ((42, 20), (42, -30), (150, 20)):
			ppm = px_tall / 1.55
			sz = (int(px_tall * .7) + 6, px_tall + 6)
			a = render(surf, tex, yaw, 4, sz, ppm=ppm, centre=(0, .775, 0))
			im = to_img(a)
			ims.append(im.resize((im.width * 4, im.height * 4), Image.NEAREST))
		out = Image.new('RGB', (sum(i.width for i in ims) + 20 * len(ims), max(i.height for i in ims)), (30, 30, 30))
		x = 0
		for im in ims:
			out.paste(im, (x, out.height - im.height))
			x += im.width + 20
		out.save(os.path.join(args.out, 'tomas_small.png'))


if __name__ == '__main__':
	main()
