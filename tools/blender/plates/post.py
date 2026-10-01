"""From linear render passes to the plate files: tone, paint-over, grade, grain, and the encodings of
depth.png (RG8), key.png and glow.png (L8 shares).

The grade is fitted ONCE, on the wide plate against the reference, and the same tables are applied
to every plate and to the props' vertex colours, so the plates agree with each other."""
import json
import math
import os

import numpy as np
from PIL import Image
from scipy import ndimage

LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)


def lum(rgb):
    return rgb @ LUMA


def srgb_encode(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def srgb_decode(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def tone(rgb, exposure=1.0):
    """Linear scene light -> display (sRGB-encoded 0..1). A filmic curve (ACES fit) with a soft toe."""
    x = np.maximum(rgb * exposure, 0.0)
    y = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14)
    return srgb_encode(y)


def auto_exposure(rgb, target_median=0.14):
    """The exposure that puts the tone-mapped median luma at `target_median` (fitted on the wide)."""
    lo, hi = 0.05, 50.0
    sample = rgb[::4, ::4]
    for _ in range(40):
        mid = math.sqrt(lo * hi)
        if np.median(lum(tone(sample, mid))) < target_median:
            lo = mid
        else:
            hi = mid
    return math.sqrt(lo * hi)


def blur(img, sigma):
    if img.ndim == 3:
        return np.stack([ndimage.gaussian_filter(img[..., c], sigma) for c in range(img.shape[2])], -1)
    return ndimage.gaussian_filter(img, sigma)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def crop169(img):
    h, w = img.shape[:2]
    nw = int(round(h * 16 / 9))
    if nw >= w:
        return img
    x0 = (w - nw) // 2
    return img[:, x0:x0 + nw]


# ---- paint-over --------------------------------------------------------------------------------------

def paint_over(img, z, key_share, glow_share, fov_v, haze_col=(0.62, 0.53, 0.38), far=80.0, strength=1.0):
    """The matte-painting step, procedural: aerial haze from depth, dodge where the key falls, a glow
    along the beam's edges and round the bright sources, burn in the near dark masses, darker corners."""
    h, w = img.shape[:2]
    s = h / 878.0
    out = img.copy()
    zz = np.where(np.isfinite(z) & (z < far), z, far)
    # haze: distant things lift toward warm beige
    hz = (smoothstep(7.0, 24.0, zz) * 0.22 * strength)[..., None]
    out = out * (1 - hz) + np.array(haze_col, np.float32) * hz
    l = lum(out)
    # dodge where the key light lands (soft), burn the near shade
    kb = blur(key_share * l, 6 * s)
    out = out * (1.0 + 0.45 * strength * smoothstep(0.05, 0.4, kb))[..., None]
    near_dark = (1 - smoothstep(2.5, 6.0, zz)) * (1 - smoothstep(0.02, 0.2, blur(key_share, 4 * s)))
    out = out * (1.0 - 0.28 * strength * near_dark)[..., None]
    # glow: bright sources and the beam's edges bloom a little (warm)
    l = lum(out)
    bright = np.clip(l - 0.55, 0, None)[..., None] * out / np.maximum(l, 1e-4)[..., None]
    edge = np.abs(blur(key_share, 2 * s) - blur(key_share, 9 * s))
    bloom = blur(bright, 10 * s) * 0.55 + blur(bright, 40 * s) * 0.35
    bloom += (blur(edge, 6 * s) * 0.18 * strength)[..., None] * np.array([1.0, 0.86, 0.6], np.float32)
    bloom += (blur(glow_share * l, 8 * s) * 0.25 * strength)[..., None] * np.array([1.0, 0.7, 0.4], np.float32)
    out = out + bloom * strength
    # darker corners, measured in units of the frame height so every aspect agrees
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.hypot((xx - w / 2) / (h / 2), (yy - h / 2) / (h / 2)) / math.hypot(16 / 9, 1.0)
    out = out * (1.0 - 0.38 * strength * smoothstep(0.45, 1.05, r))[..., None]
    return np.clip(out, 0, 1)


def paper(img, seed=7, amount=0.045):
    """A fine paper grain over everything: fibrous noise (stretched sideways) plus a soft mottle."""
    h, w = img.shape[:2]
    rng = np.random.default_rng(seed)
    n = ndimage.gaussian_filter(rng.standard_normal((h, w)).astype(np.float32), (0.6, 1.4))
    n /= n.std() + 1e-6
    m = ndimage.gaussian_filter(rng.standard_normal((h, w)).astype(np.float32), 5.0)
    m /= m.std() + 1e-6
    g = 1.0 + amount * n + amount * 0.6 * m
    return np.clip(img * g[..., None], 0, 1)


# ---- grade: quantile match in Lab --------------------------------------------------------------------

def _lab(img):
    from skimage import color
    return color.rgb2lab(np.clip(img, 0, 1))


def _rgb(lab):
    from skimage import color
    return np.clip(color.lab2rgb(lab), 0, 1)


def fit_grade(src, ref, strength=0.6, n=65):
    """Tables mapping src's Lab quantiles onto ref's, applied at `strength`."""
    a, b = _lab(src).reshape(-1, 3), _lab(ref).reshape(-1, 3)
    q = np.linspace(0, 100, n)
    return {"strength": strength, "src": [np.percentile(a[:, c], q).tolist() for c in range(3)],
            "dst": [np.percentile(b[:, c], q).tolist() for c in range(3)]}


def apply_grade(img, lut):
    shape = img.shape
    lab = _lab(img.reshape(-1, 1, 3)).reshape(-1, 3)
    out = lab.copy()
    for c in range(3):
        src, dst = np.array(lut["src"][c]), np.array(lut["dst"][c])
        src = np.maximum.accumulate(src + np.arange(len(src)) * 1e-6)
        mapped = np.interp(lab[:, c], src, dst)
        out[:, c] = lab[:, c] + lut["strength"] * (mapped - lab[:, c])
    return _rgb(out.reshape(-1, 1, 3)).reshape(shape)


# ---- maps ---------------------------------------------------------------------------------------------

def share(group, total, sigma=1.5):
    """Smoothed share of a light group in the pixel's light (energy-weighted, so dark noise dies)."""
    lg, lt = np.maximum(lum(group), 0), np.maximum(lum(total), 0)
    return np.clip(blur(lg, sigma) / np.maximum(blur(lt, sigma), 1e-5), 0, 1)


def encode_depth(z, near, far):
    zz = np.where(np.isfinite(z), z, far)
    v = np.clip((zz - near) / (far - near), 0, 1)
    q = np.floor(v * 65535.0).astype(np.uint32)
    return np.stack([(q >> 8).astype(np.uint8), (q & 255).astype(np.uint8)], -1)


def decode_depth(rg, near, far):
    q = rg[..., 0].astype(np.float64) * 256 + rg[..., 1]
    return near + q / 65535.0 * (far - near)


def downsample(img, size):
    mode = "RGB" if img.ndim == 3 else "L"
    im = Image.fromarray(img if img.dtype == np.uint8 else (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), mode)
    return np.asarray(im.resize(size, Image.LANCZOS))


def save_png(path, arr):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if arr.dtype != np.uint8:
        arr = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    if arr.ndim == 3 and arr.shape[2] == 2:
        # RG8 as a 2-channel PNG would be read as grey+alpha; store as RGB with B = 0
        arr = np.concatenate([arr, np.zeros(arr.shape[:2] + (1,), np.uint8)], -1)
    Image.fromarray(arr).save(path, optimize=True)


def stats(img):
    l = lum(img)
    mx, mn = img.max(-1), img.min(-1)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    return {"median": float(np.median(l)), "p99": float(np.percentile(l, 99)), "sat": float(sat.mean())}
