// ============================================================================
// starfield.gdshaderinc -- the deep-space backdrop, shared verbatim by
// Goliath.gdshader (sampled along the *lensed* exit direction of each photon)
// and GoliathSky.gdshader (sampled along the straight view direction, outside
// the hole's influence volume).
//
// Both must use the same code or the volume boundary would show as a seam:
// inside it you would see one sky, outside it another. Deflection is windowed
// to ~zero by the time a ray reaches the volume's edge, so with a shared
// backdrop the transition is genuinely invisible.
//
// Ported from ga2/index2.html. Godot defines PI as a builtin, so unlike the
// WebGL original this file does not declare it.
// ============================================================================

// Backdrop detail, 0 (stars only) to 3 (everything). Declared here because both
// GoliathSky.gdshader and Goliath.gdshader include this file and both need it:
// the sky is drawn on every background pixel *and* evaluated again for every
// photon that escapes the raymarch, so an octave dropped here is paid twice.
uniform int sky_detail : hint_range(0, 3) = 3;

int fbm_octaves() {
	return sky_detail <= 0 ? 2 : (sky_detail == 1 ? 3 : (sky_detail == 2 ? 4 : 5));
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i + vec3(0.0, 0.0, 0.0)), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	int octaves = fbm_octaves();
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) { break; }
		v += a * noise3(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

// Nebulae.
//
// Rewritten from the original simulator's version, which was a handful of
// gaussian blobs at about a third of the brightness the tonemapper needs to
// show anything -- they were technically present and effectively invisible.
//
// Two changes. The filament structure is now sampled ONCE for the whole sky
// rather than per cloud, so six clouds cost two fBm evaluations where four used
// to cost five; and the structure is a ridged combination of a coarse and a
// fine octave set, which reads as gas rather than as airbrush. Brightness is
// set so the densest filaments land near 1.0 after exposure -- bright enough to
// see, dim enough that stars still read on top of them.
uniform float nebula_gain : hint_range(0.0, 4.0) = 1.0;

vec3 nebula_clouds(vec3 dir) {
	if (nebula_gain <= 0.001) {
		return vec3(0.0);
	}
	// One structure field for the whole sky. Frequencies are set against the
	// cloud sizes below: shrink the clouds without tightening the filaments and
	// each one turns into a smooth blob again.
	float coarse = fbm(dir * 3.6 + 5.0);
	float fine = sky_detail >= 2 ? fbm(dir * 9.2 + 19.0) : 0.5;
	float structure = clamp(coarse * 1.35 + fine * 0.55 - 0.46, 0.0, 1.0);
	structure = pow(structure, 1.35);
	if (structure <= 0.001) {
		return vec3(0.0);
	}

	vec3 dirs[7];
	dirs[0] = normalize(vec3(-0.72, 0.48, 0.30));
	dirs[1] = normalize(vec3(0.58, -0.52, -0.42));
	dirs[2] = normalize(vec3(-0.15, -0.68, 0.58));
	dirs[3] = normalize(vec3(0.35, 0.62, -0.55));
	dirs[4] = normalize(vec3(0.88, 0.22, 0.40));
	// Moved. This one sat 6 degrees off the line from the player's spawn to
	// Goliath -- centred almost exactly behind the hole -- and a gold cloud
	// directly behind a black hole costs you the silhouette, which is the one
	// thing in this scene worth framing. Swung about 38 degrees to screen left
	// of that line, comfortably clear of its own 14-degree half-width.
	dirs[5] = normalize(vec3(-0.876, -0.138, -0.462));
	// The shard's cloud: on the line from the spawn point out to the
	// dreadnought, so the thing is first seen against a wall of its own green
	// rather than against empty sky.
	dirs[6] = normalize(vec3(0.370, 0.083, 0.925));
	vec3 cols[7];
	cols[0] = vec3(1.05, 0.34, 0.12); // rust / ember
	cols[1] = vec3(0.62, 0.14, 0.58); // magenta
	cols[2] = vec3(0.10, 0.34, 0.72); // deep blue
	cols[3] = vec3(0.46, 0.16, 0.76); // violet
	cols[4] = vec3(0.10, 0.52, 0.48); // teal
	cols[5] = vec3(0.70, 0.40, 0.10); // dim gold
	cols[6] = vec3(0.16, 0.86, 0.34); // bioluminescent green
	// Angular half-widths, in radians. Roughly half what they were: at the old
	// sizes two neighbouring clouds overlapped over most of the sky and the
	// backdrop read as one continuous wash rather than as distinct nebulae.
	float sizes[7];
	sizes[0] = 0.33; sizes[1] = 0.26; sizes[2] = 0.37;
	sizes[3] = 0.21; sizes[4] = 0.29; sizes[5] = 0.24;
	sizes[6] = 0.34;
	float gains[7];
	gains[0] = 1.00; gains[1] = 0.78; gains[2] = 0.72;
	gains[3] = 0.62; gains[4] = 0.66; gains[5] = 0.55;
	gains[6] = 0.92;

	vec3 col = vec3(0.0);
	for (int i = 0; i < 7; i++) {
		float ang = acos(clamp(dot(dir, dirs[i]), -1.0, 1.0));
		float falloff = exp(-(ang * ang) / (sizes[i] * sizes[i]));
		col += cols[i] * falloff * gains[i];
	}
	return col * structure * 0.98 * nebula_gain;
}

vec3 starfield(vec3 dir) {
	vec3 col = vec3(0.0);

	vec3 p = dir * 260.0;
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float d = hash13(ip);

	if (d > 0.9994) {
		// Rare blue/orange beacon star -- bright enough that its smearing and
		// duplication through the Einstein ring is easy to spot.
		bool warm = hash13(ip + 9.9) > 0.5;
		vec3 tint = warm ? vec3(1.35, 0.9, 0.55) : vec3(0.6, 0.8, 1.4);
		float dist = length(fp - 0.5);
		float star = smoothstep(0.42, 0.0, dist);
		col += tint * star * 5.5;
	} else if (d > 0.9935) {
		float brightness = hash13(ip + 7.7);
		vec3 star_color = mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.9, 0.75), hash13(ip + 3.3));
		float dist = length(fp - 0.5);
		float star = smoothstep(0.35, 0.0, dist) * brightness;
		col += star_color * star * 3.2;
	}

	return col;
}

vec3 rand_dir(float seed) {
	float a = hash13(vec3(seed, 1.7, 9.2)) * 6.2831853;
	float z = hash13(vec3(seed, 4.4, 2.1)) * 2.0 - 1.0;
	float rr = sqrt(max(0.0, 1.0 - z * z));
	return vec3(rr * cos(a), z, rr * sin(a));
}

// Fixed, large, brightly-coloured marker stars at hardcoded world directions.
// Static in world space -- as the camera moves, their direction relative to the
// view sweeps past the shadow, visibly shearing them into Einstein arcs that
// hug the disk's contour. These are the payoff for raymarching at all.
vec3 big_stars(vec3 dir) {
	vec3 col = vec3(0.0);
	vec3 dirs[7];
	dirs[0] = normalize(vec3(0.42, 0.16, -0.35));
	dirs[1] = normalize(vec3(-0.55, -0.10, 0.30));
	dirs[2] = normalize(vec3(0.10, 0.62, 0.48));
	dirs[3] = normalize(vec3(-0.30, 0.34, -0.62));
	dirs[4] = normalize(vec3(0.68, -0.22, 0.18));
	dirs[5] = normalize(vec3(1.00, 0.03, 0.08)); // near y=0: "horizontal" to the hole
	dirs[6] = normalize(vec3(-0.53, -0.29, -0.77));
	vec3 cols[7];
	cols[0] = vec3(0.55, 0.75, 1.7);  // blue giant
	cols[1] = vec3(1.7, 1.15, 0.55);  // warm amber
	cols[2] = vec3(1.55, 1.55, 1.65); // white
	cols[3] = vec3(0.6, 0.85, 1.6);   // blue giant
	cols[4] = vec3(1.65, 1.2, 0.7);   // amber
	cols[5] = vec3(2.0, 0.32, 0.14);  // huge red giant
	cols[6] = vec3(0.5, 0.85, 2.1);   // huge blue giant
	// 0, 2, 4, 5, 6 are dramatically enlarged into visible radiant discs so
	// their shearing into arcs reads clearly; 1 and 3 stay small for scale.
	float sizes[7];
	sizes[0] = 0.013;
	sizes[1] = 0.0024;
	sizes[2] = 0.015;
	sizes[3] = 0.0020;
	sizes[4] = 0.011;
	sizes[5] = 0.020;
	sizes[6] = 0.022;

	for (int i = 0; i < 7; i++) {
		float ang = acos(clamp(dot(dir, dirs[i]), -1.0, 1.0));
		float core = smoothstep(sizes[i], 0.0, ang);
		float glow = exp(-(ang * ang) / (sizes[i] * sizes[i] * 8.0)) * 0.5;
		col += cols[i] * (core * 2.2 + glow);
	}
	return col;
}

// Cinematic comets: a bright point core plus a soft, exponentially-fading dust
// tail, on an angled great-circle trajectory that loops periodically. Rendered
// analytically in (along-track, cross-track) coordinates rather than as
// discrete dashes, so the tail is smooth and continuous.
vec3 comets(vec3 dir, float time) {
	vec3 col = vec3(0.0);
	for (int i = 0; i < 2; i++) { // rare: at most 2 on screen at once
		float seed = float(i) * 17.13;
		vec3 axis = rand_dir(seed);
		// Perpendicular basis built from a fixed reference vector (switched
		// when axis is near-vertical) rather than a second random direction --
		// a second random vector can land near-parallel with axis, collapsing
		// e1 toward zero and snapping every comet onto the same degenerate
		// path. This construction cannot degenerate.
		vec3 arbitrary = (abs(axis.y) < 0.95) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 e1 = normalize(cross(arbitrary, axis));
		vec3 e2 = cross(axis, e1);
		float polar0 = mix(0.3, PI - 0.3, hash13(vec3(seed, 6.6, 2.9)));

		float period = 18.0 + hash13(vec3(seed, 5.5, 1.1)) * 14.0;
		float speed = 6.2831853 / period;
		float phase = hash13(vec3(seed, 8.8, 3.3)) * 6.2831853;
		float head_ang = time * speed + phase;

		float polar_dir = acos(clamp(dot(dir, axis), -1.0, 1.0));
		float cross_track = polar_dir - polar0;

		float x = dot(dir, e1);
		float y = dot(dir, e2);
		float theta_dir = atan(y, x);

		float along = head_ang - theta_dir;
		along = mod(along + PI, 2.0 * PI) - PI; // > 0 means "behind" the head

		// Per-comet random scale: some are faint micro-streaks, others larger
		// shooting stars. Shrinks core/tail width and brightness together.
		float scale = 0.35 + hash13(vec3(seed, 4.1, 7.7)) * 1.05;
		float inv_scale2 = 1.0 / (scale * scale);

		float cross2 = cross_track * cross_track;
		float core = exp(-(along * along * 700.0 + cross2 * 9000.0) * inv_scale2);

		float s_behind = max(along, 0.0);
		float tail_width = (0.0018 + s_behind * 0.012) * scale;
		float tail = exp(-s_behind * 13.0 / scale) * exp(-cross2 / (tail_width * tail_width)) * step(0.0, along);

		float csel = hash13(vec3(seed, 2.2, 6.6));
		vec3 tint = csel < 0.34 ? vec3(0.5, 1.3, 1.6)     // cyan ionized gas
			: csel < 0.67 ? vec3(0.4, 1.45, 0.65)         // emerald green
			: vec3(1.55, 1.05, 0.45);                     // warm sodium

		col += tint * (core * 2.4 + tail * 0.9) * scale;
	}
	return col;
}

// The complete backdrop for one direction. Everything the raymarch's escaped
// photons see, and everything the sky shader draws.
vec3 deep_space(vec3 dir, float time) {
	// Stars and the big marker stars are cheap and are what the lensing acts
	// on, so they survive at every level; the fBm-driven extras do not.
	vec3 col = starfield(dir) + big_stars(dir);
	// Nebulae survive down to detail 1: they are the cheapest thing in here now
	// (one shared structure field) and the sky looks empty without them.
	if (sky_detail >= 1) {
		col += nebula_clouds(dir);
	}
	if (sky_detail >= 2) {
		col += comets(dir, time);
	}
	return col;
}
