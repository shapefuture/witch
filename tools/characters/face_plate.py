"""Photo-projected face plate (the technique of the user's "Shadow" model, generalised).

1. **Mapping.** Landmarks (eye centres, nose tip, mouth, chin) are read once off the concept
   art (pixels) and placed on the witch's head (model units). A least-squares affine maps model
   (x, y) to reference pixels, so a tilted or slightly turned head in the art still lands
   upright and centred on the plate.
2. **Texture.** The face crop is upscaled Lanczos x3, resampled (bicubic) through that affine
   into an upright texture whose pixels are linear in model x/y, colour-normalised to the
   target skin tone (a low-pass of the skin, so painted shading planes flatten but eyes, lips
   and brows keep their contrast), and mirrored from the better half for symmetry.
3. **Window.** Pixels outside the face window (the skin region connected to the face centre,
   symmetric after mirroring) become hair colour. Eye regions get their dark lines deepened,
   everything an unsharp mask, then 5-bit quantisation.
4. **Plate.** A grid over the head front follows the head's analytic surface, displaced by a
   relief (nose ridge and tip, alae, lips, brow ridge, eye sockets, cheekbones, chin) whose
   sizes are fractions of the eye spacing, so it fits any head. UVs are the same linear map
   from model x/y, so the texture lands exactly where the landmarks say.
"""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as ndi

A = np.array
LANDMARKS = ('eyeR', 'eyeL', 'nose', 'mouth', 'chin')   # eyeR = her right eye = image left


def affine_fit(model_pts, px_pts):
    """2x3 M with px ~= M @ (x, y, 1), least squares."""
    X = np.hstack([A(model_pts, float), np.ones((len(model_pts), 1))])
    M, res, _, _ = np.linalg.lstsq(X, A(px_pts, float), rcond=None)
    return M.T


def _lum(a):
    return a @ A([.3, .55, .15])


def skin_mask(a):
    """Skin vs hair (orange, low blue), hood/flowers (blue-heavy) and dark background."""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    L = _lum(a)
    br = b / np.maximum(r, 1e-3)
    gr = g / np.maximum(r, 1e-3)
    return (r >= g) & (g >= b * .98) & (br > .44) & (br < .86) & (gr > .55) & (gr < .9) & (L > .30)


class FaceSpec:
    """Everything needed to make one face: reference, landmarks, plate window, colours."""

    def __init__(s, ref, px, model, win, size, keep, target, hair, eye_r=.05, upscale=3,
                 hairline=None, eye_contrast=.5, eye_dark=.5, paint=None):
        s.ref = ref                  # path of the concept image
        s.px = px                    # landmark -> (x, y) pixels in the reference
        s.model = model              # landmark -> (x, y) on the head, model units
        s.win = win                  # (x0, x1, y0, y1) model rectangle the texture covers
        s.size = size                # (w, h) texture pixels
        s.keep = keep                # 'her_right' or 'her_left': the half that is mirrored over
        s.target = A(target, float)  # skin tone after normalisation (display-referred)
        s.hair = A(hair, float)      # fill outside the face window
        s.eye_r = eye_r              # eye region radius (model units) for the crisp lines
        s.upscale = upscale
        s.hairline = hairline        # model y where the forehead meets the hair (None: estimate)
        s.eye_contrast = eye_contrast
        s.eye_dark = eye_dark
        s.paint = paint              # Features to repaint crisply (see paint_features), or None

    # model <-> texture -------------------------------------------------------------------------
    def tex_uv(s, x, y):
        x0, x1, y0, y1 = s.win
        return (A(x, float) - x0) / (x1 - x0), (y1 - A(y, float)) / (y1 - y0)

    def tex_xy(s):
        """Model (x, y) of every texel centre."""
        w, h = s.size
        x0, x1, y0, y1 = s.win
        xs = x0 + (np.arange(w) + .5) / w * (x1 - x0)
        ys = y1 - (np.arange(h) + .5) / h * (y1 - y0)
        return np.meshgrid(xs, ys)


def warp_reference(spec):
    """Upright face texture (float RGB, h x w) resampled from the Lanczos-x3 reference."""
    ref = Image.open(spec.ref).convert('RGB')
    keys = [k for k in LANDMARKS if k in spec.px and k in spec.model]
    M = affine_fit([spec.model[k] for k in keys], [spec.px[k] for k in keys])
    X, Y = spec.tex_xy()
    u = M[0, 0] * X + M[0, 1] * Y + M[0, 2]
    v = M[1, 0] * X + M[1, 1] * Y + M[1, 2]
    pad = 6
    bx0, by0 = int(math.floor(u.min())) - pad, int(math.floor(v.min())) - pad
    bx1, by1 = int(math.ceil(u.max())) + pad, int(math.ceil(v.max())) + pad
    crop = ref.crop((bx0, by0, bx1, by1))
    k = spec.upscale
    big = np.asarray(crop.resize((crop.size[0] * k, crop.size[1] * k), Image.LANCZOS)).astype(float) / 255
    # landmark pixels are pixel-centre coordinates; upscaled index = k*(p - origin + .5) - .5
    cu = k * (u - bx0 + .5) - .5
    cv = k * (v - by0 + .5) - .5
    out = np.stack([ndi.map_coordinates(big[..., c], [cv, cu], order=3, mode='nearest') for c in range(3)], 2)
    resid = np.array([M @ (*spec.model[q], 1) for q in keys]) - A([spec.px[q] for q in keys])
    return np.clip(out, 0, 1), M, float(np.abs(resid).max())


def face_texture(spec, debug=None):
    """-> (PIL RGB texture, info). `debug` is an optional path prefix for intermediate images."""
    a, M, resid = warp_reference(spec)
    h, w = a.shape[:2]
    X, Y = spec.tex_xy()
    mask = skin_mask(a)

    # colour normalisation: low-pass of skin -> gain toward target, applied where skin is
    sy, sx = h * .09, w * .025          # tall, narrow: keeps per-column shading planes, drops them
    est = mask.astype(float)
    L = _lum(a)
    for _ in range(2):
        den = ndi.gaussian_filter(est, (sy, sx)) + 1e-6
        low = np.stack([ndi.gaussian_filter(a[..., c] * est, (sy, sx)) / den for c in range(3)], 2)
        ll = _lum(low)
        est = (mask & (L > .72 * ll) & (L < 1.3 * ll)).astype(float)
    den = ndi.gaussian_filter(est, (sy, sx)) + 1e-6
    low = np.stack([ndi.gaussian_filter(a[..., c] * est, (sy, sx)) / den for c in range(3)], 2)
    gain = np.clip(spec.target / np.maximum(low, .05), .6, 2.6)
    soft = np.clip(ndi.gaussian_filter(ndi.binary_dilation(mask, iterations=2).astype(float), 1.0), 0, 1)[..., None]
    out = np.clip(a * (1 + (gain - 1) * soft), 0, 1)

    # symmetry: x is linear in columns and the window is centred on x=0
    xc = (0 - spec.win[0]) / (spec.win[1] - spec.win[0]) * w        # column of the face axis
    half = int(round(xc))
    sym = out.copy()
    msym = mask.copy()
    if spec.keep == 'her_right':      # her right = image left = small x columns
        src = out[:, :half][:, ::-1]
        sym[:, half:half + src.shape[1]] = src[:, :w - half]
        msym[:, half:half + src.shape[1]] = mask[:, :half][:, ::-1][:, :w - half]
    else:
        src = out[:, half:][:, ::-1]
        n = min(half, src.shape[1])
        sym[:, half - n:half] = src[:, src.shape[1] - n:]
        msym[:, half - n:half] = mask[:, half:][:, ::-1][:, src.shape[1] - n:]

    # face window: skin connected to the face centre, holes (eyes, brows, lips) filled, then
    # reduced to a smooth symmetric contour: per-row half width, median-smoothed, jaw narrowing
    # monotonically to the chin, and a round hairline arc above the brows (petals and fringe
    # in the art would otherwise leave spikes)
    win = ndi.binary_closing(msym, iterations=2)
    win = ndi.binary_opening(win, iterations=1)
    lab, _ = ndi.label(win)
    yrow = lambda yy: (spec.win[3] - yy) / (spec.win[3] - spec.win[2]) * h
    cy = int(np.clip(yrow(spec.model['nose'][1]), 0, h - 1))
    win = lab == lab[cy, half]
    win = ndi.binary_fill_holes(ndi.binary_closing(win, iterations=4))
    hw = np.zeros(h)
    for j in range(h):
        c = np.nonzero(win[j, half:])[0] if spec.keep == 'her_left' else np.nonzero(win[j, :half][::-1])[0]
        if len(c):
            run = np.split(c, np.nonzero(np.diff(c) > 1)[0] + 1)[0]
            hw[j] = run.max() + 1 if run[0] <= 2 else 0
    hw = ndi.median_filter(hw, size=9, mode='nearest')
    chin_row = yrow(spec.model['chin'][1])
    j_wide = int(np.argmax(np.where(np.arange(h) > yrow(spec.model['eyeL'][1]), hw, 0)))
    for j in range(j_wide + 1, h):                  # jaw: never widens again below the cheeks
        hw[j] = min(hw[j], hw[j - 1])
    hw[int(math.ceil(chin_row)) + 1:] = 0           # rows below the chin are never face
    ey_row = yrow(spec.model['eyeL'][1])
    top_row = yrow(spec.hairline) if spec.hairline else max(0., ey_row - 1.6 * (ey_row - yrow(spec.model['nose'][1])) * 1.4)
    hw_e = hw[int(ey_row)]
    for j in range(int(ey_row)):                    # hairline arc from the eye line up to the top
        t = (ey_row - j) / max(ey_row - top_row, 1)
        hw[j] = hw_e * math.sqrt(max(0., 1 - t * t)) if t < 1 else 0
    hw = ndi.gaussian_filter1d(hw, 1.5)
    cols = np.abs(np.arange(w) + .5 - xc)
    win = cols[None, :] < hw[:, None]
    edge = ndi.gaussian_filter(win.astype(float), .7)[..., None]
    sym = sym * edge + spec.hair * (1 - edge)

    if spec.paint is None:
        # crisp, dark-lined eyes: local contrast up, pixels darker than their surroundings deepened
        eyes = np.zeros((h, w), bool)
        for k in ('eyeR', 'eyeL'):
            ex, ey = spec.model[k]
            eyes |= ((X - ex) / (spec.eye_r * 1.3)) ** 2 + ((Y - ey) / spec.eye_r) ** 2 < 1
        ew = ndi.gaussian_filter(eyes.astype(float), 1.5)[..., None]
        loc3 = np.stack([ndi.gaussian_filter(sym[..., c], 4.0) for c in range(3)], 2)
        sym = sym + (sym - loc3) * spec.eye_contrast * ew
        Ls = _lum(np.clip(sym, 0, 1))
        loc = ndi.gaussian_filter(Ls, 3.0)
        # only the lash line and iris deepen; a darkened lower lid reads as a squint
        upper = np.zeros((h, w))
        for k in ('eyeR', 'eyeL'):
            upper = np.maximum(upper, np.clip((Y - (spec.model[k][1] - .25 * spec.eye_r)) / (.3 * spec.eye_r), 0, 1))
        k_ = np.clip((loc - Ls - .02) / .2, 0, 1) * ew[..., 0] * upper
        sym = np.clip(sym * (1 - spec.eye_dark * k_)[..., None], 0, 1)
    else:
        # the photo keeps the skin shading; eyes, brows and lips are repainted crisply
        sym = paint_features(sym, spec, win)
    eyes = np.zeros((h, w), bool)
    for k in ('eyeR', 'eyeL'):
        ex, ey = spec.model[k]
        eyes |= ((X - ex) / (spec.eye_r * 1.3)) ** 2 + ((Y - ey) / spec.eye_r) ** 2 < 1

    im = Image.fromarray((np.clip(sym, 0, 1) * 255 + .5).astype(np.uint8))
    im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=55, threshold=2))
    sharp = im.filter(ImageFilter.UnsharpMask(radius=1.0, percent=110, threshold=1))
    em = Image.fromarray((ndi.gaussian_filter(eyes.astype(float), 1.5) * 255).astype(np.uint8))
    im = Image.composite(sharp, im, em)
    q = np.asarray(im).astype(float) / 255
    q = np.round(q * 31) / 31                       # 5 bits per channel
    tex = Image.fromarray((q * 255 + .5).astype(np.uint8))
    if debug:
        Image.fromarray((a * 255).astype(np.uint8)).save(debug + '_warp.png')
        Image.fromarray((win * 255).astype(np.uint8)).save(debug + '_window.png')
        tex.resize((w * 4, h * 4), Image.NEAREST).save(debug + '_tex_x4.png')
    rows = []
    for j in range(h):
        c = np.nonzero(win[j])[0]
        if len(c):
            yy = spec.win[3] - (j + .5) / h * (spec.win[3] - spec.win[2])
            rows.append((yy, (c.max() + 1 - xc) / w * (spec.win[1] - spec.win[0])))
    return tex, dict(affine=M, resid_px=resid, window_rows=rows)


# ---- repainted features ----------------------------------------------------------------------------
def _seg(w, h, p, n, tilt, side):
    """Almond outline (the source's `seg`): superellipse, outer corner lifted by `tilt`."""
    pts = []
    for k in range(n):
        th = 2 * math.pi * k / n
        c, s_ = math.cos(th), math.sin(th)
        x = w * math.copysign(abs(c) ** (2 / p), c)
        pts.append((x, h * math.copysign(abs(s_) ** (2 / p), s_) - tilt * side * x / w))
    return pts


def paint_features(a, spec, win, ss=4):
    """Repaint eyes, brows and lips over the photo texture at `ss`x, then box-downsample.

    The art's features are 5-15 px across; upscaled they read as smears. Here the photo's own
    features are first replaced by a masked low-pass of the surrounding skin (so the plate's
    shading survives), then the features are drawn from the source's `tex_face` geometry
    (model units, same frame as the landmarks) and blended back through soft masks."""
    h, w = a.shape[:2]
    P = spec.paint
    x0, x1, y0, y1 = spec.win
    W4, H4 = w * ss, h * ss
    kx, ky = W4 / (x1 - x0), H4 / (y1 - y0)
    S = lambda x, y: ((x - x0) * kx, (y1 - y) * ky)
    X, Y = spec.tex_xy()
    ew, eh, tilt = P['eye_w'], P['eye_h'], P['tilt']
    ym = spec.model['mouth'][1]

    # 1. suppress the photo's eyes, brows, lips: fill from surrounding skin (normalised blur)
    sup = np.zeros((h, w))
    for k in ('eyeR', 'eyeL'):
        ex, ey = spec.model[k]
        sup = np.maximum(sup, (((X - ex) / (ew * P.get('sup_w', 1.55))) ** 2 + ((Y - ey - .004) / (eh * 2.1)) ** 2 < 1).astype(float))
        sup = np.maximum(sup, (((X - ex - math.copysign(.012, ex)) / (ew * 1.35)) ** 2 + ((Y - ey - .085) / .022) ** 2 < 1).astype(float))
    sup = np.maximum(sup, ((X / .085) ** 2 + ((Y - ym) / .03) ** 2 < 1).astype(float))
    sup = np.clip(ndi.gaussian_filter(sup, 1.5) * 1.4, 0, 1) * win
    keep = ((sup <= .05) & win).astype(float)

    def fill(sig):
        den = ndi.gaussian_filter(keep, sig)
        num = np.stack([ndi.gaussian_filter(a[..., c] * keep, sig) for c in range(3)], 2)
        return num / np.maximum(den, 1e-6)[..., None], den
    near, dn = fill(6.)
    far, _ = fill(24.)
    wn = np.clip(dn / .08, 0, 1)[..., None]           # deep inside a region: take the wide fill
    base = np.clip(near * wn + far * (1 - wn), 0, 1)
    a = a * (1 - sup[..., None]) + base * sup[..., None]

    # 2. paint at ss x on top of the cleaned photo
    big = Image.fromarray((np.clip(a, 0, 1) * 255 + .5).astype(np.uint8)).resize((W4, H4), Image.BICUBIC)
    d = ImageDraw.Draw(big)
    C8 = lambda c: tuple(int(round(max(0, min(1, v)) * 255)) for v in c)
    px = lambda m: max(1, int(round(m * kx)))

    def soft(cx, cy, rx, ry, col, alpha, blur):
        m = Image.new('L', big.size, 0)
        X0, Y0 = S(cx - rx, cy + ry)
        X1, Y1 = S(cx + rx, cy - ry)
        ImageDraw.Draw(m).ellipse([X0, Y0, X1, Y1], fill=255)
        m = m.filter(ImageFilter.GaussianBlur(blur * ss)).point(lambda v: int(v * alpha))
        big.paste(Image.new('RGB', big.size, C8(col)), (0, 0), m)

    for sg, k in ((1, 'eyeL'), (-1, 'eyeR')):
        cx, cy = spec.model[k]
        soft(cx, cy + eh * .9, ew * 1.15, eh * .75, P['lid_shade'], .45, 2.5)          # lid fold shading
        soft(cx, cy - eh * 1.2, ew * .9, eh * .45, P['lid_shade'], .25, 2.0)           # soft under-eye
        d.polygon([S(cx + x, cy + y) for x, y in _seg(ew * 1.12, eh * 1.28, 2.0, 32, tilt, sg)], fill=C8(P['lid']))
        al = _seg(ew, eh, 1.7, 32, tilt, sg)
        d.polygon([S(cx + x, cy + y) for x, y in al], fill=C8(P['white']))
        soft(cx, cy + eh * .55, ew * .85, eh * .35, P['white_shade'], .55, .8)          # lid shadow on the white
        # iris rings clipped into the almond
        ir = P['iris_r']
        for r_, col in zip((ir, ir * .86, ir * .62), P['iris']):
            pts = []
            for q in range(32):
                t = 2 * math.pi * q / 32
                x, y = r_ * math.cos(t), r_ * math.sin(t)
                m_ = ((abs(x) / ew) ** 1.7 + (abs(y) / (eh * .98)) ** 1.7) ** (1 / 1.7)
                f = 1 / m_ if m_ > 1 else 1
                pts.append(S(cx - sg * .002 + x * f, cy + y * f))
            d.polygon(pts, fill=C8(col))
        pr = ir * .45
        X0, Y0 = S(cx - sg * .002 - pr, cy + pr)
        X1, Y1 = S(cx - sg * .002 + pr, cy - pr)
        d.ellipse([X0, Y0, X1, Y1], fill=C8(P['pupil']))
        cr = ir * .22                                                                   # one catch-light, same side on both eyes
        X0, Y0 = S(cx + ir * .32 - cr, cy + ir * .38 + cr)
        X1, Y1 = S(cx + ir * .32 + cr, cy + ir * .38 - cr)
        d.ellipse([X0, Y0, X1, Y1], fill=(255, 252, 240))
        top = sorted([p for p in al if p[1] >= -.004], key=lambda p: p[0])
        d.line([S(cx + x, cy + y + .002) for x, y in top], fill=C8(P['lash']), width=px(P['lash_w']), joint='curve')
        ox = ew * sg                                                                    # wing flick at the outer corner
        d.line([S(cx + ox * .92, cy + .003 - tilt * .5), S(cx + ox * 1.2, cy + .012), S(cx + ox * 1.36, cy + .018)],
               fill=C8(P['lash']), width=px(P['lash_w'] * .6), joint='curve')
        low = sorted([p for p in al if p[1] <= 0], key=lambda p: p[0])
        d.line([S(cx + x, cy + y - .002) for x, y in low], fill=C8(P['lower_lid']), width=px(.003), joint='curve')
        # brow: thin arch, orange-brown with a darker lower edge
        us = np.linspace(0, 1, 11)
        bx = [cx + sg * (-.05 + .135 * u) for u in us]
        by = [cy + P['brow_dy'] + .016 * math.sin(math.pi * u) ** 1.2 - .016 * u * u for u in us]
        d.line([S(x, y) for x, y in zip(bx, by)], fill=C8(P['brow']), width=px(.0105), joint='curve')
        d.line([S(x, y - .0035) for x, y in zip(bx, by)], fill=C8(P['brow_d']), width=px(.0035), joint='curve')
    # lips: soft coral, small closed smile
    up = [(-.056, .004), (-.03, .015), (-.011, .0195), (0, .012), (.011, .0195), (.03, .015), (.056, .004), (.03, -.002), (-.03, -.002)]
    lo = [(-.050, -.002), (-.026, -.014), (0, -.0185), (.026, -.014), (.050, -.002), (.03, 0), (-.03, 0)]
    sc = P.get('mouth_sc', 1.)
    d.polygon([S(x * sc, ym + y * sc) for x, y in lo], fill=C8(P['lip_lo']))
    d.polygon([S(x * sc, ym + y * sc) for x, y in up], fill=C8(P['lip_up']))
    d.line([S(x * sc, ym + y * sc) for x, y in ((-.058, .006), (-.03, 0), (0, -.002), (.03, 0), (.058, .006))], fill=C8(P['lip_line']), width=px(.0032), joint='curve')
    soft(0, ym - .011 * sc, .016, .005, P['lip_hi'], .5, .6)

    small = np.asarray(big.resize((w, h), Image.BOX)).astype(float) / 255
    # soft blend: painted features through a feathered mask, photo shading everywhere else
    feat = ndi.gaussian_filter(np.maximum(sup, 0), .8)[..., None]
    return a * (1 - feat) + small * feat


# ---- relief and plate ----------------------------------------------------------------------------
def relief(x, y, lm):
    """Facial relief (model units) at (x, y), sized by the eye spacing `d` of the landmarks."""
    ex, ey = abs(lm['eyeL'][0]), lm['eyeL'][1]
    d = 2 * ex
    yn, ym, yc = lm['nose'][1], lm['mouth'][1], lm['chin'][1]
    ax = abs(x)
    h = 0.
    # nose: bridge rising from between the brows to the tip, a short under-plane below it
    top = ey + .10 * d
    if yn - .10 * d <= y <= top:
        if y >= yn:
            tt = (top - y) / (top - yn)
            hn = d * (.012 + .085 * tt ** 1.6)
            sg = d * (.045 + .05 * tt)
        else:
            tt = (y - (yn - .10 * d)) / (.10 * d)
            hn = d * .097 * tt
            sg = d * .095
        h += hn * math.exp(-(ax / sg) ** 2)
    h += d * .025 * math.exp(-(((ax - .085 * d) / (.045 * d)) ** 2 + ((y - (yn + .01 * d)) / (.04 * d)) ** 2))   # alae
    h += d * .030 * math.exp(-((ax / (.24 * d)) ** 4 + ((y - ym) / (.06 * d)) ** 2))                           # lips
    h += d * .030 * math.exp(-((y - (ey + .36 * d)) / (.08 * d)) ** 2) * (1 if ax < ex * 1.5 else math.exp(-((ax - ex * 1.5) / (.2 * d)) ** 2))  # brow
    h -= d * .028 * math.exp(-(((ax - ex) / (.26 * d)) ** 2 + ((y - ey) / (.17 * d)) ** 2))                    # sockets
    h += d * .030 * math.exp(-(((ax - ex * 1.25) / (.22 * d)) ** 2 + ((y - (ey - .38 * d)) / (.2 * d)) ** 2))   # cheekbones
    h += d * .032 * math.exp(-((ax / (.2 * d)) ** 2 + ((y - (yc + .12 * d)) / (.1 * d)) ** 2))                 # chin
    return h


def plate(spec, rx_of, front_z, ys, fs, edge_off=.004, lift=.008, relief_fn=relief, xmax=None):
    """Grid over the head front: rows `ys`, columns `fs` (fractions of the head half-width
    `rx_of(y)`, optionally capped by `xmax(y)`), on `front_z(x, y)` plus relief.
    -> part dict with V, F, ax, uv (tile-local, v down) and smooth vertex normals vn."""
    V, UV, F = [], [], []
    C = len(fs)
    for j, y in enumerate(ys):
        rx = rx_of(y)
        if xmax is not None:
            rx = min(rx, xmax(y))
        for i, f in enumerate(fs):
            x = f * rx
            edge = i in (0, C - 1) or j in (0, len(ys) - 1)
            z = front_z(x, y) + (edge_off if edge else lift + relief_fn(x, y, spec.model))
            V.append((x, y, z))
            UV.append(spec.tex_uv(x, y))
    for j in range(len(ys) - 1):
        for i in range(C - 1):
            a = j * C + i
            F += [(a, a + 1, a + C + 1), (a, a + C + 1, a + C)]
    V = A(V, float)
    F = A(F, int)
    Nv = np.zeros_like(V)
    for f_ in F:
        q = V[f_]
        n = np.cross(q[1] - q[0], q[2] - q[0])
        if n[2] < 0:
            n = -n
        Nv[f_] += n
    Nv /= np.linalg.norm(Nv, axis=1, keepdims=True)
    ax = A([(0, y, front_z(0, y) - .25) for y in ys])
    return dict(V=V, F=F, ax=ax, fb=None, uv=A(UV, float), vn=Nv)
