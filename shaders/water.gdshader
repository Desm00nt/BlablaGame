shader_type spatial;
render_mode cull_back, blend_mix, diffuse_lambert, specular_schlick_ggx;

// ---------------------------------------------------------------------------
// Water: analytic sine waves in vertex, Fresnel + depth tint in fragment.
// No refraction, no screen-texture reads, no depth-texture reads.
//
// PERF BUDGET (hard project constraint: 2 GB VRAM):
//   * 0 noise samples for the waves (they are plain sines, so their normals
//     are analytic and free).
//   * 4 value-noise iterations, used only in vertex() to look up the terrain
//     height so the depth tint and shoreline match the real lake bed. Never
//     move this into fragment() - it would run per pixel.
//
// IMPORTANT: the noise + terrain_height() code is duplicated verbatim from
// terrain.gdshader and mirrored in scripts/terrain_noise.gd.
// Change one, change all three.
// ---------------------------------------------------------------------------

const int TERRAIN_OCTAVES = 4;
const float TERRAIN_FREQ = 0.016;
const float NOISE_OFFSET = 8192.0;
const vec2 LAKE_CENTER = vec2(42.0, -30.0);
const float LAKE_DEPTH = -6.5;
const float SPAWN_HEIGHT = 1.0;
const float NOISE_MIN = 0.10;
const float NOISE_INV_RANGE = 1.0 / 0.60;

// Construction pads - verbatim mirror of terrain.gdshader / terrain_noise.gd.
const vec2 PAD0_C = vec2(3.0, -2.5);    const float PAD0_R = 10.0; const float PAD0_H = 1.0;
const vec2 PAD1_C = vec2(36.0, 58.0);   const float PAD1_R = 18.0; const float PAD1_H = 8.3;
const vec2 PAD2_C = vec2(-72.0, 78.0);  const float PAD2_R = 15.0; const float PAD2_H = 14.8;
const vec2 PAD3_C = vec2(-40.0, -72.0); const float PAD3_R = 24.0; const float PAD3_H = 11.3;
const float PIT_INNER = 9.0;
const float PIT_OUTER = 18.0;
const float PIT_FLOOR = 6.5;

uniform float wave_height : hint_range(0.0, 1.0) = 0.16;
uniform float depth_fade : hint_range(0.5, 20.0) = 3.5;
uniform float fresnel_power : hint_range(0.5, 8.0) = 4.0;
uniform vec3 shallow_color = vec3(0.30, 0.58, 0.58);
uniform vec3 deep_color = vec3(0.02, 0.10, 0.20);
uniform vec3 sky_tint = vec3(0.55, 0.72, 0.92);
uniform vec3 foam_color = vec3(0.88, 0.94, 0.97);

varying float v_depth;

// --- reproducible value noise (identical to terrain.gdshader) ---------------

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

float terrain_height(vec2 p) {
        float n = fbm(p * TERRAIN_FREQ);
        float t = clamp((n - NOISE_MIN) * NOISE_INV_RANGE, 0.0, 1.0);
        float h = t * 12.0 + pow(t, 3.0) * 10.0 - 3.0;
        float s = smoothstep(5.0, 24.0, length(p));
        h = mix(SPAWN_HEIGHT, h, s);
        float w0 = 1.0 - smoothstep(PAD0_R * 0.55, PAD0_R, length(p - PAD0_C));
        h = mix(h, PAD0_H, w0);
        float w1 = 1.0 - smoothstep(PAD1_R * 0.55, PAD1_R, length(p - PAD1_C));
        h = mix(h, PAD1_H, w1);
        float w2 = 1.0 - smoothstep(PAD2_R * 0.55, PAD2_R, length(p - PAD2_C));
        h = mix(h, PAD2_H, w2);
        float w3 = 1.0 - smoothstep(PAD3_R * 0.55, PAD3_R, length(p - PAD3_C));
        h = mix(h, PAD3_H, w3);
        float pd = length(p - PAD3_C);
        if (pd < PIT_OUTER) {
                float bowl = 1.0 - smoothstep(PIT_INNER, PIT_OUTER, pd);
                h = mix(h, PIT_FLOOR, bowl);
        }
        float lake = 1.0 - smoothstep(13.0, 34.0, length(p - LAKE_CENTER));
        return mix(h, LAKE_DEPTH, lake);
}

// --- waves -------------------------------------------------------------------

// Directions / frequencies are shared between the displacement and its
// analytic derivative so the normal always matches the surface.
const vec2 W1_DIR = vec2(0.35, 0.21);
const float W1_FREQ = 1.0;
const float W1_SPEED = 1.15;
const vec2 W2_DIR = vec2(-0.19, 0.44);
const float W2_FREQ = 1.31;
const float W2_SPEED = 1.73;
const vec2 W3_DIR = vec2(0.53, -0.37);
const float W3_FREQ = 1.77;
const float W3_SPEED = 2.41;
const float W2_AMP = 0.6;
const float W3_AMP = 0.35;

void vertex() {
        // Depth against the real lake bed, evaluated in world space so the node's
        // own transform (it sits at y = -1.5) is taken into account automatically.
        vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        v_depth = wp.y - terrain_height(wp.xz);

        vec2 p = VERTEX.xz;
        float a1 = dot(p, W1_DIR) * W1_FREQ + TIME * W1_SPEED;
        float a2 = dot(p, W2_DIR) * W2_FREQ + TIME * W2_SPEED;
        float a3 = dot(p, W3_DIR) * W3_FREQ + TIME * W3_SPEED;

        float k = wave_height * 0.5;
        VERTEX.y += (sin(a1) + W2_AMP * sin(a2) + W3_AMP * sin(a3)) * k;

        // d/dp of the sum above.
        vec2 grad = W1_DIR * W1_FREQ * cos(a1)
                        + W2_DIR * W2_FREQ * W2_AMP * cos(a2)
                        + W3_DIR * W3_FREQ * W3_AMP * cos(a3);
        NORMAL = normalize(vec3(-grad.x * k, 1.0, -grad.y * k));
}

void fragment() {
        float d = clamp(v_depth / depth_fade, 0.0, 1.0);
        vec3 base = mix(shallow_color, deep_color, d);

        // VERTEX is view space in fragment(), so -VERTEX points at the camera.
        vec3 view_dir = normalize(-VERTEX);
        float facing = clamp(dot(normalize(NORMAL), view_dir), 0.0, 1.0);
        float fresnel = pow(1.0 - facing, fresnel_power);

        ALBEDO = mix(base, sky_tint, clamp(fresnel * 0.85, 0.0, 1.0));

        // Foam where the water gets thin (smoothstep written ascending: GLSL leaves
        // edge0 >= edge1 undefined).
        float foam = 1.0 - smoothstep(0.02, 0.45, v_depth);
        ALBEDO = mix(ALBEDO, foam_color, foam * 0.7);

        ROUGHNESS = mix(0.16, 0.02, fresnel);
        METALLIC = 0.0;
        SPECULAR = 0.6;
        ALPHA = clamp(max(0.42 + d * 0.53, foam * 0.8), 0.0, 1.0);
}
