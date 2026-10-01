"""The camera solve and the layout of the hall, in Godot space (metres).

The wide camera is recovered from the reference still (1672x941):

* the shelf boards of the left wall converge at about (710, 612) and the right wall's at about
  (830, 690) (painted perspective is loose); the hall axis' vanishing point is taken at (730, 612);
* the witch (1.3 m with her hat) stands with her feet at y=828 and her hat tip at y=605, the raccoon
  (0.7 m) spans 725..865: both put the horizon at y~612 and the eye at ~1.3 m;
* a 55 degree vertical lens (the critic's "wide lens"; the floor spiral's foreshortening and the
  witch's size agree within the painting's looseness), so the horizon 141 px below centre is an
  up-tilt of 8.9 degrees.

Everything else is placed by unprojecting the pixel where the reference shows it onto the floor (or
onto a wall plane), so the hall is built *for* this camera. `REF_PX` keeps those pixel picks.
"""
import math

import numpy as np

from .space import Cam, look_basis, placement, v3

REF_SIZE = (1672, 941)
FOV_V = 55.0
EYE_H = 1.3
HORIZON_Y = 612.0
AXIS_VP_X = 730.0
SPAWN = v3((1.0, 0.0, 0.3))
SPAWN_PX = (960.0, 828.0)
FOCUS_DISTANCE = 8.0      # the framing's look-at point: on the optical axis, 8 m out


def solve_wide_camera():
    """Pitch from the horizon, yaw from the hall axis' vanishing point, position from the spawn."""
    w, h = REF_SIZE
    f = (h / 2.0) / math.tan(math.radians(FOV_V) / 2.0)
    pitch = math.atan((HORIZON_Y - h / 2.0) / f)          # up-tilt
    yaw = 0.0                                              # azimuth of the optical axis, + = right of -Z
    for _ in range(30):
        fwd = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
        cam = Cam((0, 0, 0), look_basis((0, 0, 0), fwd), FOV_V, REF_SIZE)
        d = cam.ray(AXIS_VP_X, HORIZON_Y)
        err = math.atan2(d[0], -d[2])                       # the axis VP must look straight down -Z
        yaw -= err
        if abs(err) < 1e-10:
            break
    d = cam.ray(*SPAWN_PX)
    t = EYE_H / -d[1]
    pos = SPAWN - d * t
    pos[1] = EYE_H
    fwd = np.array([math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)])
    return pos, fwd, math.degrees(pitch), math.degrees(yaw)


CAM_POS, CAM_FWD, PITCH_UP, YAW_RIGHT = solve_wide_camera()
WIDE_FRAMING = {
    "focus": CAM_POS + CAM_FWD * FOCUS_DISTANCE,
    "distance": FOCUS_DISTANCE,
    "pitch_deg": -PITCH_UP,
    "yaw_deg": -YAW_RIGHT,
    "fov": FOV_V,
    "roll_deg": 0.0,
}
assert np.allclose(placement(WIDE_FRAMING["focus"], FOCUS_DISTANCE, -PITCH_UP, -YAW_RIGHT), CAM_POS, atol=1e-6)


def ref_cam():
    return Cam(CAM_POS, look_basis(CAM_POS, CAM_POS + CAM_FWD), FOV_V, REF_SIZE)


REF = ref_cam()


def floor_at(px, py):
    """World point on the floor seen at reference pixel (px, py)."""
    p = REF.hit_plane_y(px, py, 0.0)
    p[1] = 0.0
    return p


def depth_point(px, py, depth):
    return REF.point_at_depth(px, py, depth)


def x_at(px, depth):
    """World x of a point at reference column px and view depth `depth` (on the horizon)."""
    return float(REF.point_at_depth(px, HORIZON_Y, depth)[0])


def z_at(depth):
    return float(REF.point_at_depth(AXIS_VP_X, HORIZON_Y, depth)[2])


# ---- the plan, from reference pixels --------------------------------------------------------------
# Walls are planes of constant x (the nave) or z (the arch wall, the alcove's back wall).
NAVE_LEFT = x_at(0, 4.15)            # front of the left bookcases: the shelf slopes give 3.4 m left of the eye
NAVE_RIGHT = x_at(1672, 4.45)        # front of the right shelves: they leave the frame at 4.4 m
LEFT_END_Z = z_at(8.1)               # the left bookcase ends at the pilaster (screen x ~380)
RIGHT_END_Z = z_at(7.6)              # the right shelves end beside the statue (screen x ~1220)
ARCH_WALL_Z = z_at(10.0)             # the wall with the great arch and the eye
ALCOVE_BACK_Z = z_at(13.2)           # the beam-lit recess behind the statue (screen x 930..1220)
ALCOVE_RIGHT = x_at(1225, 13.2) + 0.6
ARCH_X = float(depth_point(578, 600, 10.0)[0]) - 0.12   # centre of the great arch (screen x 410..745)
ARCH_HALF_W = 1.75
ARCH_SPRING = 3.3                     # where the jambs start to curve in
ARCH_APEX = 5.6
PASSAGE_LEN = 4.4                     # the vaulted passage behind the arch
STAIR_ROOM_DEPTH = 5.0                # the second shelf room past the third arch

STATUE_AT = v3((3.55, 0.0, -2.3))
TOWER_A_AT = floor_at(850, 738)       # the dark central bookcase tower (screen x 770..930)
TOWER_B_AT = floor_at(992, 740)       # the beam-lit pointed tower behind the statue's left
PILASTER_AT = np.array([NAVE_LEFT + 0.35, 0.0, LEFT_END_Z - 0.55])
CARPET_C = floor_at(655, 836)
POOL = floor_at(880, 822)            # the brightest floor in the reference: just left of and behind the witch
OCULUS_PX = (1148, 58)
OCULUS_Y = 10.4
OCULUS = REF.hit_plane_y(OCULUS_PX[0], OCULUS_PX[1], OCULUS_Y)
SUN_DIR = (OCULUS - POOL) / np.linalg.norm(OCULUS - POOL)
ORB_AT = depth_point(128, 525, 3.55)  # the purple globe's centre, left foreground
RACCOON_FLOOR = floor_at(1045, 865)   # where the reference shows it (the game perches it on a shelf)

# Gameplay things the reference does not show, placed where they keep the picture readable.
# The machine stands at the foot of the dark tower (brass reads against it); the bell hangs on a
# bracket bolted to a post of the right bookcases, over the floor the witch can reach.
MACHINE_AT = v3((0.2, 0.0, -2.35))
MACHINE_YAW = -12.0
TOMAS_AT = v3((1.35, 0.0, -1.55))
TOMAS_YAW = 12.0
BELL_HANG = v3((NAVE_RIGHT - 1.2, 2.95, 0.95))
BELL_YAW = 0.0
BELL_TILT_DEG = 24.0
RIGHT_BOARD_GAP = 1.05
RIGHT_FIRST_BOARD = 0.32
RACCOON_PERCH = v3((NAVE_RIGHT - 0.35, RIGHT_FIRST_BOARD + 2 * RIGHT_BOARD_GAP + 0.035, -1.25))


def summary():
    return {
        "camera": [round(float(c), 3) for c in CAM_POS], "pitch_up": round(PITCH_UP, 3), "yaw_right": round(YAW_RIGHT, 3),
        "nave": [round(NAVE_LEFT, 2), round(NAVE_RIGHT, 2)], "arch_wall_z": round(ARCH_WALL_Z, 2), "arch_x": round(ARCH_X, 2),
        "statue": [round(float(c), 2) for c in STATUE_AT], "oculus": [round(float(c), 2) for c in OCULUS],
        "sun_dir": [round(float(c), 3) for c in SUN_DIR], "carpet": [round(float(c), 2) for c in CARPET_C],
    }
