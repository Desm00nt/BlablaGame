shader_type sky;

// ---------------------------------------------------------------------------
// Sky: gradient + sun/moon discs + simple drifting clouds + stars at night.
// Driven by the single uniform `time_of_day` (0..1) written by
// scripts/time_manager.gd.
//
// PERF BUDGET (hard project constraint: 2 GB VRAM):
//   * 3 value-noise iterations for the clouds + 1 hash for the stars = 4
//     noise evaluations total. Do not raise CLOUD_OCTAVES.
//   * No textures, no PanoramaSkyMaterial, no cubemap asset.
//
// The sun direction formula is duplicated from scripts/time_manager.gd
// (SUN_TILT must match) so the rendered sun and the DirectionalLight3D that
// lights the scene always point the same way.
// ---------------------------------------------------------------------------

const float SUN_TILT = 0.40;
const float NOISE_OFFSET = 8192.0;
const int CLOUD_OCTAVES = 3;

uniform float time_of_day : hint_range(0.0, 1.0) = 0.30;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.012;
uniform float star_density : hint_range(0.0, 1.0) = 0.55;
uniform vec3 sun_tint = vec3(1.00, 0.86, 0.66);

uniform vec3 zenith_day = vec3(0.20, 0.40, 0.78);
uniform vec3 horizon_day = vec3(0.66, 0.79, 0.92);
uniform vec3 zenith_night = vec3(0.012, 0.018, 0.045);
uniform vec3 horizon_night = vec3(0.045, 0.065, 0.115);
uniform vec3 zenith_dusk = vec3(0.15, 0.13, 0.30);
uniform vec3 horizon_dusk = vec3(0.86, 0.42, 0.22);
uniform vec3 ground_haze = vec3(0.09, 0.10, 0.12);

// --- reproducible value noise (integer hash, see terrain.gdshader) ----------

uint hash2u(uint x, uint y) {
	uint h = x * 374761393u + y * 668265263u + 1013904223u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return h;
}

float hash2f(uint x, uint y) {
	return float(hash2u(x, y) & 0x7FFFFFu) * (1.0 / 8388608.0);
}

float hash3f(vec3 p) {
	uint x = uint(p.x + NOISE_OFFSET);
	uint y = uint(p.y + NOISE_OFFSET);
	uint z = uint(p.z + NOISE_OFFSET);
	uint h = x * 374761393u + y * 668265263u + z * 144665u + 1013904223u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return float(h & 0x7FFFFFu) * (1.0 / 8388608.0);
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
	for (int i = 0; i < CLOUD_OCTAVES; i++) {
		sum += amp * value_noise(p * freq);
		freq *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

// --- sun ---------------------------------------------------------------------

// Identical formula to TimeManager.sun_direction().
vec3 sun_direction(float t) {
	float a = (t - 0.25) * 2.0 * PI;
	float horiz = cos(a);
	return normalize(vec3(horiz * cos(SUN_TILT), sin(a), horiz * sin(SUN_TILT)));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sdir = sun_direction(time_of_day);

	float elev = sdir.y;
	// 1.0 in full daylight, 0.0 at night, with a fast transition near sunrise.
	float day = clamp(elev * 2.6 + 0.24, 0.0, 1.0);
	// Peaks when the sun sits on the horizon.
	float dusk = 1.0 - clamp(abs(elev) * 4.5, 0.0, 1.0);

	// --- gradient ---
	vec3 zen = mix(zenith_night, zenith_day, day);
	vec3 hor = mix(horizon_night, horizon_day, day);
	zen = mix(zen, zenith_dusk, dusk * 0.65);
	hor = mix(hor, horizon_dusk, dusk * 0.90);

	float up = dir.y;
	vec3 col = mix(hor, zen, pow(clamp(up, 0.0, 1.0), 0.55));
	// Below the horizon, fade to a neutral haze so the world edge is not black.
	col = mix(ground_haze, col, smoothstep(-0.10, 0.02, up));

	// --- clouds (3 noise iterations, hemisphere only) ---
	float cloud_mask = 0.0;
	if (up > 0.02) {
		vec2 cuv = dir.xz / max(up, 0.06) * 0.30;
		cuv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.63);
		float n = fbm(cuv);
		float edge = 1.0 - cloud_cover;
		cloud_mask = smoothstep(edge, edge + 0.22, n) * smoothstep(0.02, 0.16, up);

		vec3 cloud_col = mix(vec3(0.07, 0.09, 0.15), vec3(1.0, 0.98, 0.95), day);
		cloud_col = mix(cloud_col, vec3(1.0, 0.52, 0.33), dusk * 0.65);
		// Cheap self shading: clouds facing away from the sun are darker.
		cloud_col *= mix(0.55, 1.0, clamp(dot(dir, sdir) * 0.5 + 0.5, 0.0, 1.0));
		col = mix(col, cloud_col, cloud_mask * 0.85);
	}

	// --- sun ---
	float sd = max(dot(dir, sdir), 0.0);
	float disc = smoothstep(0.99925, 0.99965, sd);
	vec3 sun_col = sun_tint * (disc * 7.0 + pow(sd, 64.0) * 0.30 + pow(sd, 8.0) * 0.10) * day;

	// --- moon (opposite the sun, only at night) ---
	float md = max(dot(dir, -sdir), 0.0);
	float mdisc = smoothstep(0.99935, 0.99965, md);
	vec3 moon_col = vec3(0.82, 0.88, 1.0) * (mdisc * 2.2 + pow(md, 128.0) * 0.08) * (1.0 - day);

	// --- stars (1 hash, blocked by clouds and daylight) ---
	// Grid radius 90 puts ~100k cells on the sphere, so a 0.5% hit rate lands at
	// roughly 500 stars - a readable night sky without turning into noise.
	if (up > -0.02 && day < 0.98 && cloud_mask < 0.99) {
		vec3 grid = dir * 90.0;
		float h = hash3f(floor(grid));
		float threshold = mix(0.9995, 0.990, star_density);
		if (h > threshold) {
			float d = length(fract(grid) - 0.5);
			float star = (1.0 - smoothstep(0.02, 0.40, d)) * ((h - threshold) / (1.0 - threshold));
			col += vec3(0.85, 0.90, 1.0) * star * (1.0 - day) * (1.0 - cloud_mask) * 1.6;
		}
	}

	COLOR = col + sun_col + moon_col;
}
