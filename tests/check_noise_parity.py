#!/usr/bin/env python3
"""Parity check: GLSL noise (shaders/*.gdshader) vs GDScript noise
(scripts/terrain_noise.gd).

The world generator places props and builds the terrain collision on the CPU,
while the terrain mesh is displaced on the GPU. If the two height fields
disagree, trees float and the player sinks through the ground.

This re-implements both sides literally:
  * glsl_*   -> uint32 wrapping arithmetic, float32 (as the GPU would)
  * gd_*     -> int64 arithmetic masked to 32 bits, float64 (as GDScript would)

Run: python3 tests/check_noise_parity.py
"""

import struct
import sys
import math

U32 = 0xFFFFFFFF


def f32(x: float) -> float:
    return struct.unpack("f", struct.pack("f", x))[0]


# ---------------------------------------------------------------- GLSL side
def glsl_hash2u(x: int, y: int) -> int:
    h = (x * 374761393 + y * 668265263 + 1013904223) & U32
    h = (((h ^ (h >> 13)) & U32) * 1274126177) & U32
    h = (h ^ (h >> 16)) & U32
    return h


def glsl_hash2f(x: int, y: int) -> float:
    return f32(f32(float(glsl_hash2u(x, y) & 0x7FFFFF)) * f32(1.0 / 8388608.0))


def glsl_value_noise(px: float, py: float) -> float:
    ix_f = math.floor(px)
    iy_f = math.floor(py)
    fx = f32(px - ix_f)
    fy = f32(py - iy_f)
    ux = f32(fx * fx * f32(3.0 - 2.0 * fx))
    uy = f32(fy * fy * f32(3.0 - 2.0 * fy))
    ix = int(f32(ix_f + 8192.0))
    iy = int(f32(iy_f + 8192.0))
    a = glsl_hash2f(ix, iy)
    b = glsl_hash2f(ix + 1, iy)
    c = glsl_hash2f(ix, iy + 1)
    d = glsl_hash2f(ix + 1, iy + 1)
    return f32(f32(a + (b - a) * ux) + (f32(c + (d - c) * ux) - f32(a + (b - a) * ux)) * uy)


def glsl_fbm(px: float, py: float) -> float:
    total = 0.0
    amp = 0.5
    freq = 1.0
    for _ in range(4):
        total = f32(total + f32(amp * glsl_value_noise(f32(px * freq), f32(py * freq))))
        freq = f32(freq * 2.0)
        amp = f32(amp * 0.5)
    return total


def glsl_smoothstep(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return f32(t * t * (3.0 - 2.0 * t))


NOISE_INV_RANGE = 1.0 / 0.60
NOISE_MIN = 0.10

# Construction pads - mirrors TerrainNoise.PADS / the two shaders.
PADS = [
    (3.0, -2.5, 10.0, 1.0),
    (36.0, 58.0, 18.0, 8.3),
    (-72.0, 78.0, 15.0, 14.8),
    (-40.0, -72.0, 24.0, 11.3),
]
PIT_INNER = 9.0
PIT_OUTER = 18.0
PIT_FLOOR = 6.5


def _pad_apply(h, px, py):
    """Flatten pads, then carve the dungeon pit. Order matters and must match
    terrain_height() on the CPU and GPU."""
    for (cx, cy, r, target) in PADS:
        d = math.hypot(px - cx, py - cy)
        if d < r:
            w = 1.0 - glsl_smoothstep(r * 0.55, r, d)
            h = f32(h + (target - h) * w)
    dcx, dcy = PADS[3][0], PADS[3][1]
    pd = math.hypot(px - dcx, py - dcy)
    if pd < PIT_OUTER:
        bowl = 1.0 - glsl_smoothstep(PIT_INNER, PIT_OUTER, pd)
        h = f32(h + (PIT_FLOOR - h) * bowl)
    return h


def glsl_terrain_height(px: float, py: float) -> float:
    n = glsl_fbm(f32(px * 0.016), f32(py * 0.016))
    t = min(max(f32((n - NOISE_MIN) * NOISE_INV_RANGE), 0.0), 1.0)
    h = f32(f32(t * 12.0) + f32(pow(t, 3.0) * 10.0) - 3.0)
    s = glsl_smoothstep(5.0, 24.0, f32(math.sqrt(px * px + py * py)))
    h = f32(1.0 + (h - 1.0) * s)  # mix(SPAWN_HEIGHT, h, s)
    h = _pad_apply(h, px, py)
    lr = math.sqrt((px - 42.0) ** 2 + (py + 30.0) ** 2)
    lake = f32(1.0 - glsl_smoothstep(13.0, 34.0, f32(lr)))
    return f32(h + (-6.5 - h) * lake)


# ------------------------------------------------------------ GDScript side
def gd_hash2f(cx: int, cy: int) -> float:
    h = (cx * 374761393 + cy * 668265263 + 1013904223) & U32
    h = ((h ^ (h >> 13)) * 1274126177) & U32
    h = (h ^ (h >> 16)) & U32
    return float(h & 0x7FFFFF) * (1.0 / 8388608.0)


def gd_value_noise(px: float, py: float) -> float:
    ix_f = math.floor(px)
    iy_f = math.floor(py)
    fx = px - ix_f
    fy = py - iy_f
    ux = fx * fx * (3.0 - 2.0 * fx)
    uy = fy * fy * (3.0 - 2.0 * fy)
    ix = int(ix_f) + 8192
    iy = int(iy_f) + 8192
    a = gd_hash2f(ix, iy)
    b = gd_hash2f(ix + 1, iy)
    c = gd_hash2f(ix, iy + 1)
    d = gd_hash2f(ix + 1, iy + 1)
    ab = a + (b - a) * ux
    cd = c + (d - c) * ux
    return ab + (cd - ab) * uy


def gd_fbm(px: float, py: float) -> float:
    total = 0.0
    amp = 0.5
    freq = 1.0
    for _ in range(4):
        total += amp * gd_value_noise(px * freq, py * freq)
        freq *= 2.0
        amp *= 0.5
    return total


def gd_smoothstep(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def gd_terrain_height(px: float, py: float) -> float:
    n = gd_fbm(px * 0.016, py * 0.016)
    t = min(max((n - NOISE_MIN) * NOISE_INV_RANGE, 0.0), 1.0)
    h = t * 12.0 + pow(t, 3.0) * 10.0 - 3.0
    s = gd_smoothstep(5.0, 24.0, math.hypot(px, py))
    h = 1.0 + (h - 1.0) * s
    for (cx, cy, r, target) in PADS:
        d = math.hypot(px - cx, py - cy)
        if d < r:
            w = 1.0 - gd_smoothstep(r * 0.55, r, d)
            h = h + (target - h) * w
    dcx, dcy = PADS[3][0], PADS[3][1]
    pd = math.hypot(px - dcx, py - dcy)
    if pd < PIT_OUTER:
        bowl = 1.0 - gd_smoothstep(PIT_INNER, PIT_OUTER, pd)
        h = h + (PIT_FLOOR - h) * bowl
    lake = 1.0 - gd_smoothstep(13.0, 34.0, math.hypot(px - 42.0, py + 30.0))
    return h + (-6.5 - h) * lake


# ------------------------------------------------------------------- checks
def main() -> int:
    failures = 0

    # 1) integer hash must be bit-identical (incl. the negative lattice cells
    #    the terrain actually visits: p in [-200,200] * 0.016 * up to 8)
    checked = 0
    for cx in range(8100, 8480, 7):
        for cy in range(8100, 8480, 11):
            if gd_hash2f(cx, cy) != glsl_hash2f(cx, cy):
                print(f"HASH MISMATCH at {cx},{cy}")
                failures += 1
            checked += 1
    print(f"[1] hash parity: {checked} cells compared, {failures} mismatches")

    # 2) value_noise parity
    worst_vn = 0.0
    for i in range(4000):
        px = -14.0 + (i * 0.00703)
        py = -14.0 + ((i * 0.0131) % 28.0)
        worst_vn = max(worst_vn, abs(gd_value_noise(px, py) - glsl_value_noise(px, py)))
    print(f"[2] value_noise max |CPU-GPU| = {worst_vn:.3e}")
    if worst_vn > 1e-5:
        print("    FAIL: value noise diverges")
        failures += 1

    # 3) terrain height parity over the whole 400x400 world, plus the lake
    worst_h = 0.0
    worst_at = (0.0, 0.0)
    hs = []
    n = 0
    step = 400.0 / 256
    for gx in range(257):
        for gz in range(0, 257, 3):
            px = -200.0 + gx * step
            py = -200.0 + gz * step
            a = gd_terrain_height(px, py)
            b = glsl_terrain_height(px, py)
            hs.append(a)
            n += 1
            d = abs(a - b)
            if d > worst_h:
                worst_h, worst_at = d, (px, py)
    print(f"[3] terrain_height max |CPU-GPU| = {worst_h:.3e} m  (worst at {worst_at[0]:.1f},{worst_at[1]:.1f})")
    if worst_h > 1e-3:
        print("    FAIL: CPU/GPU height fields diverge -> props would float")
        failures += 1

    # 3b) every landmark pad must be exactly flat at its target height. The
    # dungeon pad centre sits inside the pit bowl, so its surface is the pit
    # floor, not the pad level.
    for i, (cx, cy, r, target) in enumerate(PADS):
        expect = PIT_FLOOR if i == 3 else target
        a = gd_terrain_height(cx, cy)
        b = glsl_terrain_height(cx, cy)
        if abs(a - expect) > 1e-6:
            print(f"    FAIL: pad centre ({cx},{cy}) is {a:.4f}, expected {expect}")
            failures += 1
        if abs(a - b) > 1e-6:
            print(f"    FAIL: pad centre ({cx},{cy}) CPU/GPU mismatch {a:.6f} vs {b:.6f}")
            failures += 1
    print(f"[3b] pad centres flat and CPU/GPU-identical ({len(PADS)} pads)")

    # 4) sanity of the resulting landscape
    lo, hi = min(hs), max(hs)
    mean = sum(hs) / len(hs)
    under = sum(1 for h in hs if h < -1.5) / len(hs)
    grassy = sum(1 for h in hs if -1.5 <= h < 8.0) / len(hs)
    rocky = sum(1 for h in hs if h > 13.0) / len(hs)
    snowy = sum(1 for h in hs if h > 16.0) / len(hs)
    print(f"[4] height range {lo:.2f} .. {hi:.2f} m, mean {mean:.2f} m over {n} samples")
    print(f"    water (h < -1.5): {under * 100:5.1f}%   grass (-1.5..8): {grassy * 100:5.1f}%")
    print(f"    rock  (h > 13.0): {rocky * 100:5.1f}%   snow  (h > 16.0): {snowy * 100:5.1f}%")
    print(f"    spawn point height h(0,0) = {gd_terrain_height(0.0, 0.0):.4f} m")
    print(f"    lake centre   height h(42,-30) = {gd_terrain_height(42.0, -30.0):.4f} m")

    if not (lo < -1.5):
        print("    FAIL: nothing is below the water plane, the lake would be dry")
        failures += 1
    if hi < 17.0:
        print("    FAIL: no peak reaches the snow line, snow band is unreachable")
        failures += 1
    if not (0.02 < snowy < 0.15):
        print("    FAIL: snow coverage is not in a sane 2..15% band")
        failures += 1
    if not (0.10 < rocky < 0.40):
        print("    FAIL: rock coverage is not in a sane 10..40% band")
        failures += 1
    if not (0.25 < grassy < 0.65):
        print("    FAIL: grass should be the dominant biome (25..65%)")
        failures += 1
    if abs(gd_terrain_height(0.0, 0.0) - 1.0) > 1e-6:
        print("    FAIL: spawn plateau is not exactly SPAWN_HEIGHT at the origin")
        failures += 1

    print()
    print("PARITY OK" if failures == 0 else f"{failures} FAILURE(S)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
