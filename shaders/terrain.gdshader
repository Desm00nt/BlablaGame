shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// ---------------------------------------------------------------------------
// Terrain: procedural vertex displacement + height/slope based colouring.
// No textures, no external assets.
//
// PERF BUDGET (hard project constraint: 2 GB VRAM):
//   * fbm() below performs exactly 4 value-noise iterations. Never raise it.
//   * The normal is derived in fragment() from screen-space derivatives
//     (dFdx/dFdy), which costs ZERO extra noise samples. Sampling the height
//     4 more times for a finite-difference normal would quadruple the noise
//     cost, so it is deliberately avoided.
//
// IMPORTANT: the noise + terrain_height() code is duplicated verbatim in
// water.gdshader and mirrored in GDScript by scripts/terrain_noise.gd.
// The integer hash is used (instead of a float hash) so the CPU and the GPU
// agree bit-for-bit - object placement and collision are sampled on the CPU.
// Change one, change all three.
// ---------------------------------------------------------------------------

const int TERRAIN_OCTAVES = 4;
const float TERRAIN_FREQ = 0.016;
const float NOISE_OFFSET = 8192.0;
const vec2 LAKE_CENTER = vec2(42.0, -30.0);
const float LAKE_DEPTH = -6.5;
const float SPAWN_HEIGHT = 1.0;
// Measured output range of fbm() above over the whole 200x200 world is
// [0.099, 0.699] with a median of 0.515 - NOT [0, 0.9375]. Normalising against
// the measured range is what makes the height bands below predictable.
const float NOISE_MIN = 0.10;
const float NOISE_INV_RANGE = 1.0 / 0.60;

// Construction pads (mirrors scripts/terrain_noise.gd PADS): flattened ground
// under every landmark so buildings sit flush with the terrain. Targets are
// the measured raw fbm heights at each centre - constants, because GLSL has
// no lazy evaluation.
const vec2 PAD0_C = vec2(3.0, -2.5);    const float PAD0_R = 10.0; const float PAD0_H = 1.0;
const vec2 PAD1_C = vec2(36.0, 58.0);   const float PAD1_R = 18.0; const float PAD1_H = 8.3;
const vec2 PAD2_C = vec2(-72.0, 78.0);  const float PAD2_R = 15.0; const float PAD2_H = 14.8;
const vec2 PAD3_C = vec2(-40.0, -72.0); const float PAD3_R = 24.0; const float PAD3_H = 11.3;
// Sunken dungeon courtyard carved into PAD3 (walkable 9 m ramp).
const float PIT_INNER = 9.0;
const float PIT_OUTER = 18.0;
const float PIT_FLOOR = 6.5;

uniform float grass_line : hint_range(0.0, 20.0) = 8.0;
uniform float rock_line : hint_range(4.0, 30.0) = 13.0;
uniform float snow_line : hint_range(6.0, 30.0) = 16.0;

uniform vec3 color_grass = vec3(0.20, 0.40, 0.15);
uniform vec3 color_dirt = vec3(0.36, 0.27, 0.18);
uniform vec3 color_rock = vec3(0.40, 0.39, 0.38);
uniform vec3 color_snow = vec3(0.90, 0.93, 0.96);
uniform vec3 color_sand = vec3(0.66, 0.60, 0.44);

varying float v_height;
varying vec2 v_xz;

// --- reproducible value noise ----------------------------------------------

uint hash2u(uint x, uint y) {
        uint h = x * 374761393u + y * 668265263u + 1013904223u;
        h = (h ^ (h >> 13u)) * 1274126177u;
        h = h ^ (h >> 16u);
        return h;
}

float hash2f(uint x, uint y) {
        return float(hash2u(x, y) & 0x7FFFFFu) * (1.0 / 8388608.0);
}

float value_noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = p - i;
        vec2 u = f * f * (3.0 - 2.0 * f);
        // Offset into positive range before the uint cast: uint(negative) is
        // undefined in GLSL.
        uint ix = uint(i.x + NOISE_OFFSET);
        uint iy = uint(i.y + NOISE_OFFSET);
        float a = hash2f(ix, iy);
        float b = hash2f(ix + 1u, iy);
        float c = hash2f(ix, iy + 1u);
        float d = hash2f(ix + 1u, iy + 1u);
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
        float sum = 0.0;
        float amp = 0.5;
        float freq = 1.0;
        for (int i = 0; i < TERRAIN_OCTAVES; i++) {
                sum += amp * value_noise(p * freq);
                freq *= 2.0;
                amp *= 0.5;
        }
        return sum;
}

// Shared height field. Must stay identical to TerrainNoise.terrain_height().
float terrain_height(vec2 p) {
        float n = fbm(p * TERRAIN_FREQ);
        float t = clamp((n - NOISE_MIN) * NOISE_INV_RANGE, 0.0, 1.0);
        float h = t * 12.0 + pow(t, 3.0) * 10.0 - 3.0;
        // Flatten a spawn plateau around the world origin.
        float s = smoothstep(5.0, 24.0, length(p));
        h = mix(SPAWN_HEIGHT, h, s);
        // Construction pads (see the constants above).
        float w0 = 1.0 - smoothstep(PAD0_R * 0.55, PAD0_R, length(p - PAD0_C));
        h = mix(h, PAD0_H, w0);
        float w1 = 1.0 - smoothstep(PAD1_R * 0.55, PAD1_R, length(p - PAD1_C));
        h = mix(h, PAD1_H, w1);
        float w2 = 1.0 - smoothstep(PAD2_R * 0.55, PAD2_R, length(p - PAD2_C));
        h = mix(h, PAD2_H, w2);
        float w3 = 1.0 - smoothstep(PAD3_R * 0.55, PAD3_R, length(p - PAD3_C));
        h = mix(h, PAD3_H, w3);
        // Sunken dungeon courtyard inside the dungeon pad.
        float pd = length(p - PAD3_C);
        if (pd < PIT_OUTER) {
                float bowl = 1.0 - smoothstep(PIT_INNER, PIT_OUTER, pd);
                h = mix(h, PIT_FLOOR, bowl);
        }
        // Carve a lake basin so the water plane at y = -1.5 is visible.
        float lake = 1.0 - smoothstep(13.0, 34.0, length(p - LAKE_CENTER));
        return mix(h, LAKE_DEPTH, lake);
}

// --- shading ----------------------------------------------------------------

void vertex() {
        v_xz = VERTEX.xz;
        v_height = terrain_height(VERTEX.xz);
        VERTEX.y = v_height;
}

void fragment() {
        // Facet normal of the displaced triangle. VERTEX is view space here, so
        // this yields a view-space normal, which is what NORMAL expects.
        vec3 facet = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
        NORMAL = faceforward(facet, normalize(VERTEX), facet);

        vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
        float slope = clamp((1.0 - dot(NORMAL, up_view)) * 2.6, 0.0, 1.0);
        float h = v_height;

        vec3 col = color_grass;
        // Shoreline / beach. smoothstep() is undefined for edge0 >= edge1, so the
        // descending ramps are written as 1.0 - smoothstep(low, high, x).
        col = mix(col, color_sand, 1.0 - smoothstep(-0.9, 0.6, h));
        // Highland turns to bare earth before it turns to rock.
        col = mix(col, color_dirt, smoothstep(grass_line, grass_line + 4.0, h) * 0.75);
        // Cliffs are rock regardless of altitude.
        col = mix(col, color_rock, smoothstep(0.30, 0.62, slope));
        // Alpine rock.
        col = mix(col, color_rock, smoothstep(rock_line, rock_line + 3.0, h));
        // Snow caps - only where it is flat enough to hold.
        float snow = smoothstep(snow_line, snow_line + 3.5, h) * (1.0 - smoothstep(0.22, 0.65, slope));
        col = mix(col, color_snow, snow);

        // Free mottling (no extra noise samples - pure trig).
        float mottle = 0.94 + 0.06 * sin(v_xz.x * 1.7) * cos(v_xz.y * 1.3);
        ALBEDO = col * mottle;
        ROUGHNESS = mix(0.95, 0.75, snow);
}
