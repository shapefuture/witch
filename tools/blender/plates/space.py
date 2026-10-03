"""Godot-space camera math, shared by the plate renderer, the anchors and the proxy.

Godot convention: metres, +Y up, a camera at yaw 0 looks toward -Z. `placement` and `compute_pose`
are ports of game/camera/camera_director.gd (keep them in step), `look_basis` is Godot's
`Basis.looking_at` followed by `rotate_object_local(Vector3.BACK, roll)`.
"""
import math

import numpy as np

UP = np.array([0.0, 1.0, 0.0])


def v3(p):
    return np.asarray(p, dtype=np.float64).reshape(3)


def placement(look_at, distance, pitch_deg, yaw_deg):
    """CameraDirector.placement: the camera position for a look-at point, distance and angles."""
    pitch, yaw = math.radians(pitch_deg), math.radians(yaw_deg)
    return v3(look_at) + np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)]) * distance


def compute_pose(mode, focus_points, framing):
    """CameraDirector.compute_pose (pure). `framing` = {focus, distance, pitch_deg, yaw_deg, fov, roll_deg}."""
    if mode == "stay":
        return {}
    room_focus = v3(framing["focus"])
    center = room_focus
    if focus_points:
        center = np.mean([v3(p) for p in focus_points], axis=0)
    d, p, y = framing["distance"], framing["pitch_deg"], framing["yaw_deg"]
    fov, roll = framing["fov"], framing.get("roll_deg", 0.0)
    if mode == "inspect":
        return {"look_at": center + [0, 1.1, 0], "distance": d * 0.44, "pitch_deg": p - 3.0, "yaw_deg": y, "roll_deg": roll - 1.5, "fov": fov - 8.0}
    if mode == "conversation":
        return {"look_at": center + [0, 1.0, 0], "distance": d * 0.46, "pitch_deg": p - 3.0, "yaw_deg": y + 16.0, "roll_deg": roll + 2.2, "fov": fov - 10.0}
    if mode == "magic_reveal":
        return {"look_at": center + [0, 1.2, 0], "distance": d * 0.8, "pitch_deg": p - 11.0, "yaw_deg": y, "roll_deg": roll - 45.0, "fov": fov + 8.0}
    if mode == "consequence":
        return {"look_at": center + [0, 0.9, 0], "distance": d * 0.55, "pitch_deg": p - 2.0, "yaw_deg": y - 10.0, "roll_deg": roll - 1.2, "fov": fov - 6.0}
    return {"look_at": room_focus, "distance": d, "pitch_deg": p, "yaw_deg": y, "roll_deg": roll, "fov": fov}


def look_basis(position, target, roll_deg=0.0):
    """Columns x, y, z of the camera basis (the camera looks along -z), as a 3x3 array."""
    z = v3(position) - v3(target)
    z /= np.linalg.norm(z)
    x = np.cross(UP, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    basis = np.stack([x, y, z], axis=1)
    if abs(roll_deg) > 1e-6:
        r = math.radians(roll_deg)
        rz = np.array([[math.cos(r), -math.sin(r), 0], [math.sin(r), math.cos(r), 0], [0, 0, 1]])
        basis = basis @ rz
    return basis


class Cam:
    """A pinhole camera in Godot space: position, basis columns, vertical fov, pixel size."""

    def __init__(self, position, basis, fov_v_deg, size, near=0.1, far=80.0):
        self.position = v3(position)
        self.basis = np.asarray(basis, dtype=np.float64)
        self.fov_v = float(fov_v_deg)
        self.size = (int(size[0]), int(size[1]))
        self.near, self.far = near, far

    @classmethod
    def from_pose(cls, pose, size, near=0.1, far=80.0, fov_extra=0.0):
        """A plate camera from a CameraDirector pose. Roll is NOT baked (plates are rendered level)."""
        pos = placement(pose["look_at"], pose["distance"], pose["pitch_deg"], pose["yaw_deg"])
        return cls(pos, look_basis(pos, pose["look_at"]), pose["fov"] + fov_extra, size, near, far)

    @property
    def focal_px(self):
        return (self.size[1] / 2.0) / math.tan(math.radians(self.fov_v) / 2.0)

    def to_view(self, points):
        p = np.atleast_2d(np.asarray(points, dtype=np.float64)) - self.position
        return p @ self.basis          # rows: (x, y, z) in camera space; visible points have z < 0

    def project(self, points, size=None):
        """Pixel coordinates (x right, y down) and view depth (positive in front) of world points."""
        w, h = size or self.size
        f = (h / 2.0) / math.tan(math.radians(self.fov_v) / 2.0)
        v = self.to_view(points)
        depth = -v[:, 2]
        safe = np.where(np.abs(depth) < 1e-9, 1e-9, depth)
        px = w / 2.0 + f * v[:, 0] / safe
        py = h / 2.0 - f * v[:, 1] / safe
        return np.stack([px, py], axis=1), depth

    def ray(self, px, py, size=None):
        """World-space unit direction through pixel (px, py)."""
        w, h = size or self.size
        f = (h / 2.0) / math.tan(math.radians(self.fov_v) / 2.0)
        d = self.basis @ np.array([(px - w / 2.0) / f, (h / 2.0 - py) / f, -1.0])
        return d / np.linalg.norm(d)

    def hit_plane_y(self, px, py, y=0.0, size=None):
        d = self.ray(px, py, size)
        t = (y - self.position[1]) / d[1]
        return self.position + d * t

    def hit_plane(self, px, py, point, normal, size=None):
        d = self.ray(px, py, size)
        n = v3(normal)
        t = np.dot(v3(point) - self.position, n) / np.dot(d, n)
        return self.position + d * t

    def point_at_depth(self, px, py, depth, size=None):
        """The world point on pixel (px, py) whose view depth is `depth`."""
        d = self.ray(px, py, size)
        along = -np.dot(d, self.basis[:, 2])
        return self.position + d * (depth / along)

    def to_json(self):
        return {"position": [round(float(c), 5) for c in self.position],
                # the contract lists the axes (columns): [[xx, xy, xz], [yx, yy, yz], [zx, zy, zz]]
                "basis": [[round(float(self.basis[r, c]), 6) for r in range(3)] for c in range(3)],
                "fov_v_deg": round(self.fov_v, 4), "near": self.near, "far": self.far, "size": list(self.size)}
