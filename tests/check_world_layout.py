#!/usr/bin/env python3
"""Simulates world_generator.gd's placement rules and chunk bucketing.

The RNG is not Godot's RandomNumberGenerator, so exact counts will differ run to
run, but acceptance rates, chunk populations and the instance budget are the
same algorithm. This is how the numbers quoted in the report were produced.

Run: python3 tests/check_world_layout.py
"""

import math
import random
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from check_noise_parity import gd_terrain_height  # noqa: E402

WATER = -1.5
GRASS_LINE = 8.0
ROCK_LINE = 13.0
CHUNK_GRID = 8
CELL = 400.0 / CHUNK_GRID
CEILING = 8000

# (name, count, water_clearance, max_height, max_slope, scale_min, scale_max)
SPECS = [
    ("Grass", 4200, 0.4, GRASS_LINE, 0.35, 0.75, 1.35),
    ("Flowers_y", 250, 0.7, 6.0, 0.22, 0.80, 1.20),
    ("Flowers_w", 250, 0.7, 6.0, 0.22, 0.80, 1.20),
    ("Flowers_p", 250, 0.7, 6.0, 0.22, 0.80, 1.20),
    ("TreesConifer", 100, 1.0, ROCK_LINE, 0.40, 0.75, 1.35),
    ("TreesBroadleaf", 100, 1.0, ROCK_LINE, 0.40, 0.75, 1.30),
    ("Rocks", 100, 0.3, 999.0, 2.0, 0.60, 2.20),
]


def slope(px, py, e=0.75):
    hx = gd_terrain_height(px + e, py) - gd_terrain_height(px - e, py)
    hz = gd_terrain_height(px, py + e) - gd_terrain_height(px, py - e)
    length = math.sqrt((hx / (2 * e)) ** 2 + 1.0 + (hz / (2 * e)) ** 2)
    return 1.0 - 1.0 / length


def scatter(rng, count, clearance, max_h, max_slope):
    out, guard, attempts = [], 0, count * 40
    while len(out) < count and guard < attempts:
        guard += 1
        px, py = rng.uniform(-190, 190), rng.uniform(-190, 190)
        h = gd_terrain_height(px, py)
        if h < WATER + clearance or h > max_h:
            continue
        if max_slope < 1.0 and slope(px, py) > max_slope:
            continue
        out.append((px, h, py))
    return out, guard


def main():
    rng = random.Random(20260826)
    total = 0
    chunks_total = 0
    problems = []
    print(f"{'prop':16s} {'want':>5s} {'got':>5s} {'attempts':>9s} {'chunks':>7s} "
          f"{'min/chunk':>9s} {'max/chunk':>9s}")
    print("-" * 74)
    for name, count, clearance, max_h, max_slope, _smin, _smax in SPECS:
        spots, guard = scatter(rng, count, clearance, max_h, max_slope)
        buckets = {}
        for px, h, pz in spots:
            cx = min(max(int((px + 200.0) / CELL), 0), CHUNK_GRID - 1)
            cz = min(max(int((pz + 200.0) / CELL), 0), CHUNK_GRID - 1)
            buckets.setdefault((cx, cz), []).append((px, h, pz))
            if h < WATER:
                problems.append(f"{name}: instance at height {h:.2f} is underwater")
        sizes = [len(v) for v in buckets.values()] or [0]
        print(f"{name:16s} {count:5d} {len(spots):5d} {guard:9d} {len(buckets):7d} "
              f"{min(sizes):9d} {max(sizes):9d}")
        if len(spots) < count:
            problems.append(f"{name}: only {len(spots)}/{count} placed")
        total += len(spots)
        chunks_total += len(buckets)

    print("-" * 74)
    print(f"{'TOTAL':16s} {sum(s[1] for s in SPECS):5d} {total:5d} {'':9s} {chunks_total:7d}")
    print()
    print(f"MultiMesh instances: {total} / {CEILING} ceiling  "
          f"({'OK' if total <= CEILING else 'OVER BUDGET'})")
    print(f"MultiMeshInstance3D nodes: {chunks_total} (chunk grid {CHUNK_GRID}x{CHUNK_GRID}, "
          f"{CELL:.0f} m cells)")
    print(f"visibility_range_end 55 m is meaningful only because a chunk AABB is {CELL:.0f} m; "
          f"one world-spanning MultiMesh would never be culled")
    if total > CEILING:
        problems.append(f"instance budget exceeded: {total} > {CEILING}")

    print()
    if problems:
        print(f"{len(problems)} PROBLEM(S):")
        for p in problems:
            print("  - " + p)
        return 1
    print("WORLD LAYOUT OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
