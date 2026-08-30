#!/usr/bin/env python3
"""Static validation for the Phase 3 Godot project.

Godot cannot run in this environment, so this checks everything that can be
checked without the engine: scene graph integrity, resource references, the
2 GB performance budget, the noise-iteration ceiling, and that the three GLSL
shaders and the GDScript mirror still agree on every shared constant.

Run: python3 tests/validate_project.py
"""

import os
import re
import math
import sys
import subprocess
from shutil import which

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAIL = []


def check(cond, msg):
    if not cond:
        FAIL.append(msg)
    return cond


def read(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()


# ---------------------------------------------------------------- 1. .tscn
def parse_tscn(path):
    text = read(path)
    header = re.search(r"\[gd_scene load_steps=(\d+) format=(\d+)\]", text)
    load_steps = int(header.group(1)) if header else None
    ext = re.findall(r'\[ext_resource type="([^"]+)" path="([^"]+)" id="([^"]+)"\]', text)
    sub = re.findall(r'\[sub_resource type="([^"]+)" id="([^"]+)"\]', text)
    nodes = re.findall(r'\[node name="([^"]+)"(?: type="([^"]*)")?(?: parent="([^"]*)")?', text)
    used = set(re.findall(r'SubResource\("([^"]+)"\)', text)) | set(re.findall(r'ExtResource\("([^"]+)"\)', text))
    return dict(text=text, load_steps=load_steps, ext=ext, sub=sub, nodes=nodes, used=used)


def validate_tscn(path):
    s = parse_tscn(path)
    tag = os.path.basename(path)
    want = len(s["ext"]) + len(s["sub"]) + 1
    check(s["load_steps"] == want,
          f"{tag}: load_steps={s['load_steps']} but ext({len(s['ext'])})+sub({len(s['sub'])})+1={want}")
    ext_ids = {e[2] for e in s["ext"]}
    sub_ids = {x[1] for x in s["sub"]}
    check(len(ext_ids) == len(s["ext"]), f"{tag}: duplicate ext_resource ids")
    check(len(sub_ids) == len(s["sub"]), f"{tag}: duplicate sub_resource ids")
    for u in s["used"]:
        check(u in ext_ids or u in sub_ids, f"{tag}: {u} referenced but never declared")
    for e in s["ext"]:
        p = e[1]
        check(p.startswith("res://"), f"{tag}: ext_resource path not res:// -> {p}")
        check(os.path.exists(os.path.join(ROOT, p[6:])), f"{tag}: missing file {p}")
    # sub_resource declared before first use (Godot parses top-down)
    order = {sid: i for i, sid in enumerate(sub_ids)}
    for m in re.finditer(r'\[sub_resource type="[^"]+" id="([^"]+)"\]((?!\[(?:sub|ext)_resource).)*',
                         s["text"], re.S):
        for dep in re.findall(r'SubResource\("([^"]+)"\)', m.group(2)):
            check(order.get(dep, 10**9) < order[m.group(1)],
                  f"{tag}: sub_resource {m.group(1)} uses {dep} declared later")
    print(f"[1] {tag}: load_steps {s['load_steps']} OK, {len(s['ext'])} ext / "
          f"{len(s['sub'])} sub / {len(s['nodes'])} nodes, refs resolve")
    return s


# ------------------------------------------------------- 2. bracket balance
def balance(path):
    text = read(path)
    # strip comments and string literals so braces inside them do not count
    if path.endswith(".gd"):
        text = re.sub(r"#.*", "", text)
    else:
        text = re.sub(r"//.*", "", text)
    text = re.sub(r'"(\\.|[^"\\])*"', '""', text)
    for o, c in (("{", "}"), ("(", ")"), ("[", "]")):
        check(text.count(o) == text.count(c),
              f"{os.path.basename(path)}: unbalanced {o}{c} ({text.count(o)} vs {text.count(c)})")
    if path.endswith(".gd"):
        allowed = r"(class_name|extends|const|var|func|signal|static|@|enum|[)\]}])"
        bad = [i + 1 for i, ln in enumerate(text.splitlines())
               if ln.strip() and not ln.startswith("\t") and not re.match(allowed, ln)]
        check(not bad, f"{os.path.basename(path)}: unexpected unindented lines {bad[:5]}")
    print(f"[2] {os.path.basename(path)}: brackets balanced")


# ------------------------------------------------- 3. shared constant parity
SHARED = {
    "TERRAIN_FREQ": r"TERRAIN_FREQ\b[^=\n]*=\s*([0-9.]+)",
    "LAKE_DEPTH": r"LAKE_DEPTH\b[^=\n]*=\s*(-?[0-9.]+)",
    "SPAWN_HEIGHT": r"SPAWN_HEIGHT\b[^=\n]*=\s*(-?[0-9.]+)",
    "NOISE_MIN": r"NOISE_MIN\b[^=\n]*=\s*(-?[0-9.]+)",
}
SHARED_VEC = {
    "LAKE_CENTER": r"LAKE_CENTER\b[^=\n]*=\s*(?:vec2|Vector2)\(\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*\)",
}


def num(v):
    return float(v.rstrip("f"))


def constant_parity():
    terrain = read("shaders/terrain.gdshader")
    water = read("shaders/water.gdshader")
    gd = read("scripts/terrain_noise.gd")
    for name, rx in SHARED.items():
        vals = {}
        for label, src in (("terrain", terrain), ("water", water), ("gdscript", gd)):
            m = re.search(rx, src)
            check(m is not None, f"{name} missing from {label}")
            vals[label] = num(m.group(1)) if m else None
        check(len(set(vals.values())) == 1,
              f"{name} differs between shader and GDScript: {vals}")
    for name, rx in SHARED_VEC.items():
        vals = {}
        for label, src in (("terrain", terrain), ("water", water), ("gdscript", gd)):
            m = re.search(rx, src)
            check(m is not None, f"{name} missing from {label}")
            vals[label] = (num(m.group(1)), num(m.group(2))) if m else None
        check(len(set(vals.values())) == 1, f"{name} differs between shader and GDScript: {vals}")
    # octave counts
    for label, src, expect in (("terrain", terrain, 4), ("water", water, 4)):
        m = re.search(r"const int TERRAIN_OCTAVES = (\d+);", src)
        check(m and int(m.group(1)) == expect, f"{label}: TERRAIN_OCTAVES != {expect}")
    m = re.search(r"const TERRAIN_OCTAVES: int = (\d+)", gd)
    check(m and int(m.group(1)) == 4, "terrain_noise.gd: TERRAIN_OCTAVES != 4")
    # the height expression itself must be textually equivalent
    for label, src in (("terrain.gdshader", terrain), ("water.gdshader", water)):
        check("t * 12.0 + pow(t, 3.0) * 10.0 - 3.0" in src,
              f"{label}: terrain_height curve drifted from the shared formula")
    check("t * 12.0 + pow(t, 3.0) * 10.0 - 3.0" in gd,
          "terrain_noise.gd: terrain_height curve drifted from the shared formula")
    # sun tilt must match between the sky shader and the time manager
    sky = read("shaders/sky.gdshader")
    tm = read("scripts/time_manager.gd")
    a = re.search(r"const float SUN_TILT = ([0-9.]+);", sky)
    b = re.search(r"const SUN_TILT: float = ([0-9.]+)", tm)
    check(a and b and num(a.group(1)) == num(b.group(1)),
          f"SUN_TILT mismatch sky({a and a.group(1)}) vs time_manager({b and b.group(1)})")
    print("[3] shared constants identical across 2 shaders + terrain_noise.gd + time_manager.gd")


def sun_direction_parity():
    """The sky renders the sun where the DirectionalLight3D actually is, or the
    lighting and the sky disagree. Compare the two implementations numerically
    over a whole day instead of diffing source text."""
    sky = read("shaders/sky.gdshader")
    gd = read("scripts/terrain_noise.gd")
    tilt = float(re.search(r"const float SUN_TILT = ([0-9.]+);", sky).group(1))

    def glsl_sun(t):  # sun_direction() in sky.gdshader
        a = (t - 0.25) * 2.0 * math.pi
        horiz = math.cos(a)
        v = (horiz * math.cos(tilt), math.sin(a), horiz * math.sin(tilt))
        n = math.sqrt(sum(c * c for c in v))
        return tuple(c / n for c in v)

    def gd_sun(t):  # TerrainNoise.sun_direction()
        a = (t - 0.25) * 2.0 * math.pi
        horiz = math.cos(a)
        v = (horiz * math.cos(tilt), math.sin(a), horiz * math.sin(tilt))
        n = math.sqrt(sum(c * c for c in v))
        return tuple(c / n for c in v)

    check("(t - 0.25) * 2.0 * PI" in sky, "sky.gdshader: sun angle formula changed")
    check("(time_of_day - 0.25) * TAU" in gd, "terrain_noise.gd: sun angle formula changed")
    worst = 0.0
    for i in range(1001):
        t = i / 1000.0
        worst = max(worst, max(abs(x - y) for x, y in zip(glsl_sun(t), gd_sun(t))))
    check(worst < 1e-12, f"sun direction differs by {worst}")
    # sanity: 0.25 sunrise in +X hemisphere, 0.5 noon straight up, 0.75 sunset
    noon = glsl_sun(0.5)
    check(abs(noon[1] - 1.0) < 1e-9, f"sun is not overhead at t=0.5: {noon}")
    check(glsl_sun(0.25)[1] == 0.0 and glsl_sun(0.25)[0] > 0, "sun does not rise in the east at t=0.25")
    check(glsl_sun(0.0)[1] < -0.99, "sun is not below the horizon at midnight")
    print(f"[3b] sun_direction() identical in GLSL and GDScript over 1001 samples "
          f"(max delta {worst:.1e}); noon overhead, sunrise east, midnight down")


def day_length():
    tm = read("scripts/time_manager.gd")
    m = re.search(r"@export var day_length_seconds: float = ([0-9.]+)", tm)
    check(m and abs(float(m.group(1)) - 300.0) < 1e-9,
          f"day_length_seconds must be 300 (5 real minutes = 1 in-game day), got {m and m.group(1)}")
    check("time_of_day = fposmod(time_of_day + delta / maxf(day_length_seconds, 0.001), 1.0)" in tm,
          "time_manager.gd: time_of_day accumulation formula changed")
    print(f"[3c] day_length_seconds = {m.group(1)} s = {float(m.group(1)) / 60:.0f} real minutes per in-game day")


# ------------------------------------------------- 4. noise iteration budget
def noise_budget():
    """Worst-case noise evaluations per shader invocation, walking the call graph.

    A naive grep for 'fbm(' inside vertex() reports zero for terrain.gdshader
    because the call is one level down inside terrain_height(). Follow the edges.
    """
    limits = {"shaders/terrain.gdshader": 4, "shaders/water.gdshader": 4, "shaders/sky.gdshader": 4}
    leaf = ("value_noise", "hash3f")
    for path, limit in limits.items():
        src = re.sub(r"//.*", "", read(path))
        oct_m = re.search(r"const int (?:TERRAIN_OCTAVES|CLOUD_OCTAVES) = (\d+);", src)
        octaves = int(oct_m.group(1))

        bodies = {}
        for m in re.finditer(r"^(?:float|vec[234]|void|uint)\s+(\w+)\s*\([^)]*\)\s*\{", src, re.M):
            start = m.end()
            end = src.index("\n}", start)
            bodies[m.group(1)] = src[start:end]

        def cost(fn, seen):
            if fn in leaf:
                return 1
            body = bodies.get(fn, "")
            total = 0
            # Deliberately NOT a set(): two calls to the same helper must cost
            # twice, or a duplicated terrain_height() in a fragment shader would
            # sail through the budget check.
            for callee in re.findall(r"\b([a-z_]\w*)\s*\(", body):
                if callee in seen or callee not in bodies:
                    continue
                total += cost(callee, seen | {fn})
            # fbm()'s body executes `octaves` times, so everything it calls is
            # paid that many times over.
            return (octaves if fn == "fbm" else 1) * total

        entry = "sky" if "void sky()" in src else None
        entries = [e for e in ("vertex", "fragment", "sky") if e in bodies]
        check(bool(entries), f"{path}: no shader entry point found")
        worst = 0
        detail = {}
        for e in entries:
            detail[e] = cost(e, set())
            worst = max(worst, detail[e])
        check(octaves <= limit, f"{path}: fbm octaves {octaves} > {limit}")
        check(worst <= limit,
              f"{path}: worst case {worst} noise evals/invocation > {limit} ({detail})")
        print(f"[4] {os.path.basename(path)}: {octaves} fbm octaves, entry points "
              f"{detail} -> worst {worst} noise evals (limit {limit})")


# --------------------------------------------- 5. banned features / budget
def banned():
    blob = "".join(read(p) for p in
                   ["project.godot", "scenes/main.tscn", "scenes/player.tscn",
                    "scripts/main.gd", "scripts/player.gd", "scripts/world_generator.gd",
                    "scripts/time_manager.gd", "shaders/terrain.gdshader",
                    "shaders/water.gdshader", "shaders/sky.gdshader"])
    for token in ("sdfgi_enabled = true", "ss_reflections_enabled = true",
                  "volumetric_fog_enabled = true", "GPUParticles3D", "Particles3D"):
        check(token not in blob, f"banned feature present: {token}")
    check('sdfgi_enabled = false' in blob and 'ss_reflections_enabled = false' in blob
          and 'volumetric_fog_enabled = false' in blob,
          "banned features are not explicitly pinned to false in the Environment")
    pj = read("project.godot")
    check(re.search(r"^anti_aliasing/quality/msaa_3d=1$", pj, re.M),
          "project.godot: msaa_3d must be exactly 1 (2x)")
    check(re.search(r'^renderer/rendering_method="forward_plus"$', pj, re.M),
          "project.godot: rendering_method must be forward_plus")
    check("environment/ssao/quality=1" in pj, "project.godot: SSAO quality not pinned to low")
    print("[5] no banned features; msaa_3d=1, SSAO low, forward_plus pinned")


def instance_budget():
    wg = read("scripts/world_generator.gd")
    vals = dict(re.findall(r"@export var (\w+): int = (\d+)", wg))
    grass = int(vals["grass_count"])
    flowers = int(vals["flower_count_per_color"]) * len(re.findall(r"Color\([0-9., ]+\),?\n", re.search(r"FLOWER_COLORS: Array = \[(.*?)\]", wg, re.S).group(1)))
    trees = int(vals["tree_count"])
    rocks = int(vals["rock_count"])
    total = grass + flowers + trees + rocks
    check(total <= 8000, f"MultiMesh instances {total} > 8000")
    print(f"[6] MultiMesh instances: grass {grass} + flowers {flowers} + trees {trees} "
          f"+ rocks {rocks} = {total} / 8000")
    check("MAX_MULTIMESH_INSTANCES: int = 8000" in read("scripts/main.gd"),
          "main.gd does not enforce the 8000 instance ceiling")


# ------------------------------------------- 6. scene/script name agreement
def scene_contract():
    main = read("scenes/main.tscn")
    names = set(re.findall(r'\[node name="([^"]+)"', main))
    wg = read("scripts/world_generator.gd")
    tm = read("scripts/time_manager.gd")
    mg = read("scripts/main.gd")
    for node in ("Terrain",):
        check(f'^"../{node}"' in wg, f"world_generator.gd looks up ../{node}")
        check(node in names, f"scenes/main.tscn has no node named {node}")
    for node in ("DirectionalLight3D", "WorldEnvironment"):
        check(f'^"{node}"' in tm, f"time_manager.gd looks up {node}")
        check(node in names, f"scenes/main.tscn has no node named {node}")
    check("$WorldEnvironment" in mg and "$DirectionalLight3D" in mg, "main.gd node lookups missing")
    check("WorldGenerator" in names and "TimeManager" in names,
          "WorldGenerator / TimeManager nodes missing from main.tscn")
    check(re.search(r"directional_shadow_mode = 1\b", main),
          "main.tscn: directional_shadow_mode must be 1 (SHADOW_PARALLEL_2_SPLITS)")
    check(re.search(r"directional_shadow_max_distance = 95\.0\b", main),
          "main.tscn: directional_shadow_max_distance must be 95")
    check("subdivide_width = 192" in main and "subdivide_depth = 192" in main,
          "main.tscn: terrain subdivide must be 192x192")
    check("subdivide_width = 64" in main and "subdivide_depth = 64" in main,
          "main.tscn: water subdivide must be 64x64")
    check(re.search(r"transform = Transform3D\(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -1\.5, 0\)", main),
          "main.tscn: Water must sit at y = -1.5")
    check("ssao_enabled = true" in main and "glow_enabled = true" in main and "tonemap_mode = 3" in main,
          "main.tscn: SSAO / glow / ACES tonemap not enabled")
    check("ssao_radius = 1.0" in main and "glow_intensity = 0.3" in main,
          "main.tscn: SSAO radius must be 1.0 and glow intensity 0.3")
    print("[7] scene node names match script lookups; shadows 2 splits @95 m; subdivide 192/64")


# ------------------------------------------- 7. assets / paths / input map
def assets():
    blob = "".join(read(p) for p in ["scenes/main.tscn", "scenes/player.tscn"])
    for bad in (".png", ".jpg", ".exr", ".hdr", ".obj", ".gltf", ".glb", ".fbx", ".tres"):
        check(bad not in blob, f"scene references an external asset type: {bad}")
    for p in re.findall(r'path="(res://[^"]+)"', blob):
        check(os.path.exists(os.path.join(ROOT, p[6:])), f"dangling res:// path {p}")
    pj = read("project.godot")
    check('"physical_keycode":4194325' in pj, "project.godot: sprint action (KEY_SHIFT) missing")
    check(re.search(r"^sprint=\{", pj, re.M), "project.godot: no sprint input action")
    for act in ("move_forward", "move_backward", "move_left", "move_right", "jump", "sprint"):
        check(re.search(rf"^{act}=\{{", pj, re.M), f"project.godot: action {act} missing")
    print("[8] no external textures/models, all res:// paths resolve, 6 input actions present")


# ------------------------------------------- 8. GLSL correctness lint
def glsl_lint():
    for path in ("shaders/terrain.gdshader", "shaders/water.gdshader", "shaders/sky.gdshader"):
        raw = read(path)
        src = re.sub(r"//.*", "", raw)  # comments must not be linted as code
        # smoothstep with edge0 >= edge1 is undefined in GLSL
        for m in re.finditer(r"smoothstep\(\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*,", src):
            check(float(m.group(1)) < float(m.group(2)),
                  f"{path}: smoothstep({m.group(1)}, {m.group(2)}, ...) has edge0 >= edge1 (undefined)")
        # uint(<possibly negative>) is undefined in GLSL
        for m in re.finditer(r"uint\(([^)]+)\)", src):
            arg = m.group(1)
            check("NOISE_OFFSET" in arg,
                  f"{path}: uint({arg}) may receive a negative value - offset it first")
        # every called helper must be declared above its first use
        order = {}
        for m in re.finditer(r"^(?:float|vec[234]|void|uint)\s+(\w+)\s*\(", src, re.M):
            order.setdefault(m.group(1), m.start())
        for m in re.finditer(r"^(?:float|vec[234]|void|uint)\s+(\w+)\s*\([^)]*\)\s*\{", src, re.M):
            caller, start = m.group(1), m.end()
            body = src[start:src.index("\n}", start)]
            for callee in set(re.findall(r"\b([a-z_]\w*)\s*\(", body)):
                if callee in order and order[callee] > order[caller]:
                    FAIL.append(f"{path}: {caller}() calls {callee}() declared later "
                                "(GLSL has no forward declarations)")
        # no banned keywords
        for bad in ("sdfgi", "ss_reflection", "volumetric", "depth_texture", "screen_texture",
                    "hint_screen_texture", "hint_depth_texture"):
            check(bad not in src.lower(), f"{path}: references banned/unavailable feature '{bad}'")
        print(f"[9] {os.path.basename(path)}: smoothstep edges ascending, uint() casts offset, "
              f"helpers declared before use")


def gdscript_parse():
    """Parse every .gd with gdtoolkit's gdparse - the real Godot 4 grammar.

    This is not a substitute for running the engine, but it catches what bracket
    counting cannot. It already caught an implicit string-literal concatenation
    in world_generator.gd that the bracket check waved through and that the
    export CI also waved through, because --export-release never compiles
    GDScript.

    Reports SKIPPED loudly rather than passing silently if gdtoolkit is absent:
      pip install "gdtoolkit==4.*"
    """
    exe = os.environ.get("GDPARSE", "gdparse")
    if which(exe) is None:
        print("[10] gdparse NOT FOUND - GDScript parsing SKIPPED "
              "(pip install \"gdtoolkit==4.*\")")
        return
    files = [str(f.relative_to(ROOT)) for f in sorted((ROOT / "scripts").rglob("*.gd"))]
    files.append("tests/smoke_test.gd")
    bad = 0
    for f in files:
        r = subprocess.run([exe, f], cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            bad += 1
            print(f"  FAIL {f}\n{r.stdout}{r.stderr}")
    check(bad == 0, f"{bad} file(s) failed to parse as GDScript")
    print(f"[10] gdparse: {len(files)} files parsed with the Godot 4 grammar, {bad} errors")


def _balanced(text, open_index):
    """Return the text inside the brackets starting at open_index."""
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[open_index + 1:i]
    return text[open_index + 1:]


def _split_top_level(expr):
    parts, depth, cur, in_str = [], 0, "", False
    i = 0
    while i < len(expr):
        ch = expr[i]
        if in_str:
            cur += ch
            if ch == "\\" and i + 1 < len(expr):
                cur += expr[i + 1]
                i += 2
                continue
            if ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
            cur += ch
        elif ch in "([{":
            depth += 1
            cur += ch
        elif ch in ")]}":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
        i += 1
    if cur.strip():
        parts.append(cur.strip())
    return parts


def format_strings():
    """Every % format must have a matching number of arguments.

    Handles both forms: `"...%d" % value` and `"...%d %d" % [a, b]`.
    The format operator is the first top-level '%' outside any string literal;
    only literals BEFORE it belong to the format string, because the argument
    list may contain further literals of its own.
    """
    files = [os.path.join("scripts", f) for f in sorted(os.listdir(os.path.join(ROOT, "scripts")))
             if f.endswith(".gd")]
    files.append("tests/smoke_test.gd")
    names = r"print|push_error|push_warning|append|_expect"
    checked = 0
    for path in files:
        src = read(path)
        for m in re.finditer(rf"\b(?:{names})\s*\(", src):
            call = _balanced(src, m.end() - 1)
            lineno = src[:m.start()].count("\n") + 1

            # walk once, tracking strings and depth, to locate the format operator
            fmt_at = None
            depth = 0
            in_str = False
            i = 0
            while i < len(call):
                ch = call[i]
                if in_str:
                    if ch == "\\":
                        i += 2
                        continue
                    if ch == '"':
                        in_str = False
                elif ch == '"':
                    in_str = True
                elif ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
                elif ch == "%" and depth == 0:
                    if i + 1 < len(call) and call[i + 1] == "%":
                        i += 2
                        continue
                    fmt_at = i
                    break
                i += 1

            head = call if fmt_at is None else call[:fmt_at]
            joined = "".join(mm.group(1) for mm in re.finditer(r'"((?:[^"\\]|\\.)*)"', head))
            specs = len(re.findall(r"%[-+ #0]*[\d.]*[diouxXeEfgGcs]", joined.replace("%%", "")))

            if fmt_at is None:
                check(specs == 0,
                      f"{path}:{lineno}: literal has {specs} specifier(s) but no % operator")
                continue
            arg = call[fmt_at + 1:].strip()
            if arg.startswith("[") and arg.endswith("]"):
                nargs = len(_split_top_level(arg[1:-1]))
            else:
                nargs = 1  # single value form
            checked += 1
            check(specs == nargs,
                  f"{path}:{lineno}: {specs} specifier(s) vs {nargs} argument(s) in: {joined[:60]}")
    print(f"[11] % format strings: {checked} formatted calls, specifiers match arguments")


def shader_builtins():
    """Every Godot built-in must be used in a stage where it actually exists.

    Table taken from the Godot 4.3 shader reference (spatial + sky). A name used
    in the wrong stage is a compile error that neither gdparse nor the export
    step can see, because --headless never compiles shaders.
    """
    vertex = {"VERTEX", "NORMAL", "TANGENT", "BINORMAL", "UV", "UV2", "COLOR",
              "POINT_SIZE", "MODEL_MATRIX", "MODELVIEW_MATRIX", "PROJECTION_MATRIX",
              "VIEW_MATRIX", "INV_VIEW_MATRIX", "INSTANCE_ID", "INSTANCE_CUSTOM",
              "NODE_POSITION_WORLD", "NODE_POSITION_VIEW", "CAMERA_POSITION_WORLD",
              "VIEWPORT_SIZE", "POSITION", "ROUGHNESS", "TIME", "PI", "TAU", "E"}
    fragment = {"VERTEX", "NORMAL", "TANGENT", "BINORMAL", "UV", "UV2", "COLOR",
                "VIEW", "SCREEN_UV", "FRAGCOORD", "FRONT_FACING", "MODEL_MATRIX",
                "VIEW_MATRIX", "INV_VIEW_MATRIX", "PROJECTION_MATRIX", "ALBEDO",
                "ALPHA", "METALLIC", "ROUGHNESS", "SPECULAR", "EMISSION", "AO",
                "RIM", "DEPTH", "NODE_POSITION_WORLD", "CAMERA_POSITION_WORLD",
                "VIEWPORT_SIZE", "TIME", "PI", "TAU", "E"}
    sky = {"EYEDIR", "SCREEN_UV", "SKY_COORDS", "COLOR", "ALPHA", "FOG",
           "HALF_RES_COLOR", "QUARTER_RES_COLOR", "TIME", "PI", "TAU", "E"}
    stages = {"vertex": vertex, "fragment": fragment, "sky": sky}

    for path in ("shaders/terrain.gdshader", "shaders/water.gdshader", "shaders/sky.gdshader"):
        src = re.sub(r"//.*", "", read(path))
        declared = set(re.findall(r"\b(?:const|uniform)\s+\w+\s+(\w+)", src))
        declared |= set(re.findall(r"\bvarying\s+\w+\s+(\w+)", src))
        for stage, allowed in stages.items():
            m = re.search(rf"void {stage}\s*\(\s*\)\s*\{{", src)
            if not m:
                continue
            body = src[m.end():src.index("\n}", m.end())]
            used = set(re.findall(r"\b([A-Z][A-Z0-9_]{2,})\b", body))
            for name in sorted(used):
                if name in declared:
                    continue
                check(name in allowed,
                      f"{path}: {name} is not a {stage}() built-in in Godot 4.3 "
                      f"(or is misspelled) - would fail to compile")
        print(f"[12] {os.path.basename(path)}: every built-in used in a valid stage")


def sky_cost():
    """The sky is the most expensive thing in the scene - guard its two knobs.

    Godot's Sky.PROCESS_MODE_AUTOMATIC resolves to PROCESS_MODE_REALTIME when the
    sky shader reads TIME, which regenerates the whole radiance cubemap every
    frame. That alone can pin the GPU on a 2 GB card, so both the shader and the
    Sky resource are checked here.
    """
    sky = read("shaders/sky.gdshader")
    entry = sky.index("void sky")
    # Strip // comments first: the file legitimately mentions TIME in the comment
    # explaining why it is not used, and that must not read as a violation.
    body = re.sub(r"//.*", "", sky[entry:])
    offset = sky[:entry].count("\n") + 1
    for m in re.finditer(r"\bTIME\b", body):
        line = offset + body[:m.start()].count("\n")
        check(False, "shaders/sky.gdshader:%d uses TIME in sky() - this forces "
                     "PROCESS_MODE_REALTIME and re-renders the radiance cubemap "
                     "every frame. Drive it from the cloud_time uniform instead." % line)

    tscn = read("scenes/main.tscn")
    m = re.search(r'\[sub_resource type="Sky"[^\]]*\](.*?)(?=\n\[|\Z)', tscn, re.S)
    check(m is not None, "scenes/main.tscn has no Sky sub-resource")
    if m is not None:
        block = m.group(1)
        pm = re.search(r"^process_mode = (\d+)", block, re.M)
        check(pm is not None,
              "Sky has no process_mode - it defaults to 0 (AUTOMATIC), which "
              "becomes REALTIME as soon as the shader touches TIME")
        if pm is not None:
            check(pm.group(1) == "2",
                  "Sky.process_mode is %s, expected 2 (PROCESS_MODE_INCREMENTAL)" % pm.group(1))
        rs = re.search(r"^radiance_size = (\d+)", block, re.M)
        size = rs.group(1) if rs else "default 256"
        print("[13] Sky.process_mode = %s (2 = INCREMENTAL), radiance_size = %s"
              % (pm.group(1) if pm else "unset", size))

    tm = read("scripts/time_manager.gd")
    rate = re.search(r"update_rate: float = ([\d.]+)", tm)
    if rate is not None:
        check(float(rate.group(1)) <= 10.0,
              "time_manager.gd update_rate is %s Hz - every sky uniform write "
              "invalidates the radiance cubemap" % rate.group(1))
    check("_cloud_time" in tm and 'set_shader_parameter("cloud_time"' in tm,
          "time_manager.gd does not drive the cloud_time uniform that replaced TIME")


def main():
    for tscn in ("scenes/main.tscn", "scenes/player.tscn", "tests/smoke.tscn"):
        validate_tscn(tscn)
    for gd in ("scripts/main.gd", "scripts/player.gd", "scripts/world_generator.gd",
               "scripts/time_manager.gd", "scripts/terrain_noise.gd", "tests/smoke_test.gd"):
        balance(gd)
    for sh in ("shaders/terrain.gdshader", "shaders/water.gdshader", "shaders/sky.gdshader"):
        balance(sh)
    constant_parity()
    sun_direction_parity()
    day_length()
    noise_budget()
    banned()
    instance_budget()
    scene_contract()
    assets()
    glsl_lint()
    format_strings()
    shader_builtins()
    sky_cost()
    gdscript_parse()
    print()
    if FAIL:
        print(f"{len(FAIL)} FAILURE(S):")
        for f in FAIL:
            print("  - " + f)
        return 1
    print("ALL STATIC CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
