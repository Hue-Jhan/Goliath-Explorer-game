// ============================================================================
// Goliath.gdshader -- Schwarzschild black hole, raymarched in world space.
//
// Ported from ga2/index2.html (Three.js + one GLSL fragment shader). The
// physics is unchanged; what differs is how it meets a 3D scene:
//
//   * WebGL version: one fullscreen quad, the hole IS the whole image.
//   * Here: a spatial shader on an inverted bounding sphere centred on the
//     hole, drawn in the transparent pass. Rays are rebuilt from the inverse
//     projection/view matrices (not from mesh vertices, so it survives the
//     near plane clipping the volume), marched in hole-local natural units,
//     and clamped against the depth buffer so ships and asteroids occlude the
//     disk correctly. You can fly into it.
//
//   * No tonemapping here. The WebGL original ended with acesFilm() and a
//     1/2.2 gamma; this emits linear HDR and lets WorldEnvironment's global
//     ACES tonemapper handle it, so the hole is graded like everything else
//     in the scene instead of being tonemapped twice.
//
// Known limitation: only the procedural backdrop is lensed. Scene geometry
// composites by depth but is not bent -- doing that needs a screen-space
// fallback that falls apart at large deflection angles. Standard tradeoff.
// ============================================================================

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled,
	blend_premul_alpha, shadows_disabled, fog_disabled, specular_disabled;

#include "res://environment/starfield.gdshaderinc"

// --- world <-> natural units --------------------------------------------------
// Everything below the transform is in Schwarzschild radii (rs = 1), exactly
// as in the WebGL original. rs_world is the single place the two scales meet.

uniform mat4 bh_inv_xform;                  // world -> hole-local (no scale)
uniform float rs_world = 500.0;             // Godot units per Schwarzschild radius
uniform float influence_radius = 15300.0;   // world units; radius of this mesh

// --- disk geometry ------------------------------------------------------------

uniform float disk_inner = 3.0;   // rs. 3.0 is the real ISCO for a non-spinning hole
uniform float disk_outer = 17.0;  // rs
uniform float disk_rot_speed = 1.0;
uniform float disk_spin = 1.0;    // +1 / -1: flips which side is beamed toward you
// Half-thickness of the slab at the rim, in rs. The disk flares outward. At 0
// this collapses back to the infinitely thin plane the first version used.
uniform float disk_thickness = 0.42;

// --- look ---------------------------------------------------------------------

uniform float lens_strength = 1.0;                          // Globals.bh_strength
uniform vec4 disk_tint : source_color = vec4(1.0);          // Globals.bh_color_tint
uniform float axis_tilt = 0.0;                              // radians, Globals.bh_axis_tilt
uniform float exposure = 1.3;
// Floor colour inside the shadow. Pure black is physically right but leaves the
// player with no depth cue at all once the horizon fills the view, so the
// shadow is given a barely-there cold tint to keep its edge readable.
uniform vec3 horizon_floor = vec3(0.004, 0.006, 0.011);

// --- scene compositing --------------------------------------------------------

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

// Hard ceiling for the loop (GLSL wants a constant bound); the live budget is
// the uniform, which the graphics slider drives.
const int MAX_STEPS = 260;
uniform int max_steps = 170;
// Disk turbulence octaves, 0..3. disk_color() is by far the most expensive
// thing in the march -- five octaves of anisotropic fBm plus a dust-lane
// sample, well over a hundred hashes per call -- so this is the second lever
// after resolution.
uniform int disk_detail : hint_range(0, 3) = 3;


// Half-thickness of the disk at radius r, in rs. Flares outward: thin near the
// ISCO where the gas is hottest and most tightly bound, thickest at the rim.
float disk_half_thickness(float r) {
	float t = clamp((r - disk_inner) / max(disk_outer - disk_inner, 0.001), 0.0, 1.0);
	return max(disk_thickness * (0.30 + 0.70 * t), 0.012);
}

// ---- accretion disk ----------------------------------------------------------
// Thin equatorial disk in the hole's local XZ plane, starting strictly at the
// ISCO so there is a clean black gap between it and the horizon. Density from
// tangentially-stretched fbm turbulence advected by Keplerian shear; colour
// from a deep fire ramp; brightness and hue from relativistic Doppler beaming.

// Anisotropic fbm: divides the .x sample coordinate by stretch before each
// octave, elongating features along whichever axis is fed in as .x. Used with
// the tangential (flow) coordinate as .x, so turbulence reads as fibrous
// filaments dragged around the orbit rather than an isotropic airbrushed blob.
float fbm_flow(vec3 p, float stretch) {
	float v = 0.0;
	float a = 0.5;
	int octaves = disk_detail <= 1 ? 3 : (disk_detail == 2 ? 4 : 5);
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) { break; }
		vec3 q = vec3(p.x / stretch, p.y, p.z);
		v += a * noise3(q);
		p *= 2.3;
		a *= 0.55;
	}
	return v;
}

// Cinematic Interstellar-reference palette: white-hot only right at the ISCO
// (this is what feeds the bright ring), then almost immediately into deep
// red-orange for the bulk of the disk, darkening to near-black embers at the
// fringe.
vec3 disk_ramp(float t) {
	vec3 white = vec3(1.0, 1.0, 1.0) * 2.8;         // hottest -- core + ring
	vec3 pale_gold = vec3(1.0, 0.85, 0.65) * 2.0;   // brief warm-white transition
	vec3 red_orange = vec3(0.95, 0.30, 0.06) * 1.35; // dominant through the disk
	vec3 deep_red = vec3(0.55, 0.09, 0.02) * 0.95;  // outer disk
	vec3 ember = vec3(0.12, 0.02, 0.0) * 0.55;      // fringe

	vec3 c = mix(white, pale_gold, smoothstep(0.0, 0.06, t));
	c = mix(c, red_orange, smoothstep(0.04, 0.24, t));
	c = mix(c, deep_red, smoothstep(0.22, 0.65, t));
	c = mix(c, ember, smoothstep(0.55, 1.0, t));
	c = mix(c, vec3(0.0), smoothstep(0.95, 1.2, t)); // softly dissolve to black
	return c;
}

vec3 disk_color(vec3 p, vec3 ray_dir, float time) {
	float r = length(p.xz);
	float phi = atan(p.z, p.x);

	// Unclamped above 1: lets the wispy outer tendrils below extend past the
	// nominal outer radius instead of hard-clipping at it.
	float t = max((r - disk_inner) / (disk_outer - disk_inner), 0.0);

	float omega = 1.15 / pow(r / disk_inner, 1.5); // Keplerian shear, omega ~ r^-1.5
	// Large fixed offset on the winding clock only (not the other animation
	// timers) so differential shear between radii is already fully wound up on
	// the first frame -- without it, swirl starts equal to phi everywhere (zero
	// shear) and visibly takes seconds to twist into tight bands.
	float wind_time = 12.0 + time;
	float swirl = phi - omega * wind_time * disk_rot_speed * disk_spin;

	// cos/sin embedding, NOT the raw angle -- swirl wraps by 2*PI at phi = +-PI,
	// so using it directly as a linear coordinate tears a visible seam straight
	// across the disk. cos/sin are continuous everywhere; stretching .x in
	// fbm_flow still elongates features into spiralling filaments, seamlessly.
	// Slow radial frequency (0.035, not 0.09): faster rates make the pattern
	// read as thin concentric rings instead of a soft textured gradient.
	vec2 flow_xy = vec2(cos(swirl), sin(swirl)) * r;
	vec3 flow_p = vec3(flow_xy.x * 0.22, flow_xy.y * 0.22, r * 0.035 - time * 0.05);
	float n = fbm_flow(flow_p, 2.6);
	n = clamp(n, 0.0, 1.0); // no extra contrast curve -- keep it soft

	// Faint, soft dust lanes -- wide transition, mild darkening.
	float lanes = noise3(vec3(flow_xy.x * 0.5, flow_xy.y * 0.5, time * 0.08));
	float dust = smoothstep(0.2, 0.8, lanes);

	// Mild perturbation of the ramp's radius input with local turbulence, so
	// colour bands wobble gently instead of forming perfect concentric rings.
	vec3 base_color = disk_ramp(t + (n - 0.5) * 0.07) * disk_tint.rgb;

	// Ragged, per-angle noise-varied outer edge -- wispy tendrils fading into
	// space. The inner edge stays tight so the ISCO gap reads as a clean cutoff.
	float edge_noise = fbm(vec3(cos(phi) * 2.4, sin(phi) * 2.4, time * 0.025));
	float outer_edge = 0.88 + edge_noise * 0.4;
	float density = smoothstep(0.0, 0.045, t) * (1.0 - smoothstep(0.55, outer_edge, t));
	density *= (0.65 + 0.45 * n) * mix(0.7, 1.0, dust);

	// ---- relativistic Doppler beaming ----------------------------------------
	// The disk orbits, so one side always moves toward the viewer and the other
	// away. Special relativity brightens and blues the approaching side and
	// dims and reddens the receding one:
	//     D = 1 / (1 - v*mu),  mu = cos(angle between velocity and line of sight)
	// with observed intensity I_obs = D^3 * I_emit. The exponent is softened to
	// 1.8 here so the bright limb keeps its filament detail on screen instead of
	// blowing out. v(r) = sqrt(rs / 2r) is the Keplerian orbital speed, capped
	// below c. This asymmetry is the single most recognisable feature of the
	// render -- it is why one edge of the disk is a blazing blade.
	vec3 tangent = normalize(vec3(-p.z, 0.0, p.x)) * disk_spin;
	float v_orb = clamp(sqrt(1.0 / (2.0 * r)), 0.0, 0.95); // rs = 1 in natural units
	float mu = dot(tangent, -ray_dir);
	float doppler = 1.0 / max(0.15, (1.0 - v_orb * mu));
	float beaming = pow(doppler, 1.8);

	vec3 col = base_color * density * beaming;
	col.b *= clamp(doppler, 0.5, 1.8);
	col.r *= clamp(2.0 - doppler, 0.4, 1.5);

	// Local compression (stronger than a plain HDR clamp) so the brightened
	// side keeps its filament detail instead of flattening to white.
	col = col / (1.0 + 0.6 * col);

	return max(col, vec3(0.0));
}

// Rotates v by angle a around the X axis. Tilts the hole's own spin axis away
// from local +Y -- applied to the incoming ray once, up front, which is
// equivalent to tilting the whole hole+disk system rather than the camera.
vec3 rotate_x(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
}

// ---- geodesic raymarch -------------------------------------------------------
// Approximates the Schwarzschild null-geodesic equation
//     d2u/dphi2 + u = (3/2) rs u^2,   u = 1/r
// with the equivalent Cartesian central-force form
//     a(pos) = -1.5 * rs * |h|^2 / r^5 * pos,   h = pos0 x dir0
// where h is the photon's angular momentum, fixed at the ray's start. Because
// the force is purely radial, h is exactly conserved (d/dt[pos x vel] =
// vel x vel + pos x accel = 0), so the photon provably stays in a single plane
// and bends the way light really does near a Schwarzschild hole to leading
// order. The Einstein ring falls straight out of this -- there is no
// special-case code for it anywhere.
//
// Real gravity has infinite range; for a compact cinematic silhouette the force
// is windowed with atten = 1 / (1 + (r/lens_r)^8). Artistic, non-physical, but
// C-infinity smooth -- a hard cutoff (tried in the original) leaves a visible
// ring-shaped seam in the starfield where bending stops dead.
//
// Returns premultiplied colour in .rgb and coverage in .a.
vec4 trace_ray(vec3 ro, vec3 rd, float start_dist, float max_dist, float time) {
	vec3 pos = rotate_x(ro, -axis_tilt);
	vec3 dir = rotate_x(rd, -axis_tilt);
	vec3 h = cross(pos, dir);
	float h2 = dot(h, h);

	float escape_r = (influence_radius / rs_world) * 1.05;
	bool hit_horizon = false;
	bool occluded = false;

	// Deflection falloff reference. Sits well inside the disk's own radius: at
	// lens_r itself only the inner disk is still full-strength, and by the
	// disk's outer edge bending is already faint, so distant objects whose
	// direction merely grazes the disk stay essentially unbent.
	float lens_r = disk_outer * 0.5;

	// Secondary lensed photon ring, in the gap between horizon and ISCO, near
	// the photon-sphere scale where light can orbit several times before
	// escaping. Detected via closest approach (min_r) rather than per-step
	// proximity: a ray plunging in radially crosses r = photon_r once and keeps
	// falling, so it stays dark; only a ray that actually turns around near the
	// photon sphere bottoms out close to photon_r and lights up. (A per-step
	// version washes the entire shadow interior with glow.)
	float photon_r = 2.2;
	float ring_width = 0.055; // razor-thin
	vec3 ring_glow_col = vec3(2.0, 1.9, 1.7);
	float min_r = escape_r;

	vec3 accum_color = vec3(0.0);
	float accum_alpha = 0.0;

	// Distance travelled along the ray so far, in world units. Starts at the
	// bounding sphere's entry point -- outside the volume the path is straight,
	// so there is nothing to integrate there.
	float travelled = start_dist;

	for (int i = 0; i < MAX_STEPS; i++) {
		if (i >= max_steps) { break; }
		float r = length(pos);
		min_r = min(min_r, r);
		if (r < 1.02) { hit_horizon = true; break; } // rs = 1 in natural units
		if (r > escape_r || accum_alpha > 0.995) { break; }
		if (travelled >= max_dist) { occluded = true; break; }

		float dt = clamp(r * 0.12, 0.015, 1.4);

		// --- volumetric disk ---------------------------------------------------
		// The disk is a slab, not a plane. Two things follow. First, the step
		// size has to shrink near the midplane or a coarse step jumps clean
		// through the slab and the disk vanishes at grazing angles; the limiter
		// keys off distance to the plane, so it costs nothing out in open space.
		// Second, emission is integrated along the segment instead of sampled
		// once at a crossing -- which is what makes flying *through* the disk
		// fog the view rather than flick past a sheet of paper.
		float r_xz = length(pos.xz);
		bool in_band = (r_xz > disk_inner * 0.6) && (r_xz < disk_outer * 1.45);
		float half_h = disk_half_thickness(r_xz);
		// Gate the limiter on actually being near the slab. The Gaussian is
		// already dead past ~3 half-heights, so limiting further out only buys
		// smaller steps through empty space -- which is most of the volume, and
		// was costing roughly half the frame.
		// --- landing on the slab, not stepping over it -----------------------
		// The step limiter used to engage only once a sample was already inside
		// the slab. A ray that happened to sit just outside it took a full
		// coarse step and could cross the whole disk in one go, contributing
		// nothing. Whether that happened depended on where the sampling lattice
		// fell relative to y = 0, and the lattice spacing is dt = r * 0.12 --
		// which, viewed down the spin axis, is very nearly constant along each
		// ray and varies with image radius. The result was concentric rings of
		// missed disk, and matching rings in the background behind it, since the
		// background is attenuated by whatever alpha the disk accumulated.
		//
		// So: when the ray is outside the slab and closing on it, clamp the step
		// to land exactly on its surface. Inside, sample finely. No ray can skip
		// the disk at any camera angle now, and the emission is continuous
		// because the sampling always starts from the same surface.
		float slab_edge = half_h * 3.0;
		if (in_band) {
			float y_abs = abs(pos.y);
			if (y_abs > slab_edge) {
				float dy = abs(dir.y);
				if (dy > 1e-5 && sign(dir.y) != sign(pos.y)) {
					dt = min(dt, max((y_abs - slab_edge) / dy, 0.01));
				}
			} else {
				// 0.9 / 0.85 lands about three samples per crossing, enough for
				// a smooth Gaussian falloff.
				dt = min(dt, max(y_abs * 0.9, half_h * 0.85));
			}
		}
		// Never step past scene geometry; that pixel belongs to the ship, not
		// to the hole.
		dt = min(dt, max((max_dist - travelled) / rs_world, 0.001));

		if (in_band && r_xz > disk_inner && r_xz < disk_outer * 1.35) {
			float vert = exp(-(pos.y * pos.y) / (half_h * half_h));
			if (vert > 0.003) {
				// Path length through the slab goes as 1/sin(inclination), so a
				// grazing ray would accumulate without bound and wash the whole
				// disk out -- which is exactly what an unweighted integral does.
				// Weighting by the inclination cancels that entirely; a floor on
				// it lets grazing views keep *some* extra glow (up to ~1.7x),
				// which is the volumetric depth cue worth keeping.
				float incline = max(abs(dir.y), 0.6);
				// Tempting to cache this across a slab crossing, since it
				// depends on (radius, angle) and not height. Measured: it is
				// 12% SLOWER. A branch does not skip work for a GPU warp where
				// any lane still needs the recompute, so the cost is paid
				// anyway, plus divergence and the extra live registers.
				vec3 dcol = disk_color(pos, dir, time);
				// Normalised by the Gaussian's vertical integral (H*sqrt(pi)) so
				// a face-on ray lands at the same brightness the thin-plane
				// version produced, whatever disk_thickness is set to. A grazing
				// ray travels further through the slab and is correspondingly
				// brighter, which is exactly the behaviour that was missing.
				float seg = dt * vert * incline / (half_h * 1.7725);
				float a = clamp(max(max(dcol.r, dcol.g), dcol.b) * 0.75 * seg, 0.0, 1.0);
				accum_color += (1.0 - accum_alpha) * dcol * seg;
				accum_alpha += (1.0 - accum_alpha) * a;
			}
		}

		float atten = 1.0 / (1.0 + pow(r / lens_r, 8.0));
		vec3 accel = -1.5 * h2 * pos / pow(r, 5.0) * atten * lens_strength;
		vec3 new_dir = normalize(dir + accel * dt);
		vec3 new_pos = pos + new_dir * dt;

		pos = new_pos;
		dir = new_dir;
		travelled += dt * rs_world;
	}

	if (hit_horizon) {
		// The shadow. Fully opaque: whatever was behind it is gone. Not quite
		// black, though -- see horizon_floor.
		return vec4(accum_color + (1.0 - accum_alpha) * horizon_floor, 1.0);
	}
	if (occluded) {
		// Scene geometry stopped us. Composite what the disk contributed in
		// front of it and let the geometry show through the rest.
		return vec4(accum_color, accum_alpha);
	}
	// Escaped to the sky. The backdrop is sampled with the *lensed* exit
	// direction, which is where the Einstein ring and the sheared arcs of the
	// big marker stars come from.
	float ring_glow = exp(-pow((min_r - photon_r) / ring_width, 2.0));
	vec3 bg = deep_space(dir, time) + ring_glow_col * ring_glow * 2.8;
	return vec4(accum_color + (1.0 - accum_alpha) * bg, 1.0);
}

void fragment() {
	// --- rebuild this pixel's world-space ray ---------------------------------
	// From the inverse projection rather than the mesh's own geometry, so the
	// ray is correct even when the camera is inside the volume and the near
	// plane is slicing through it.
	vec4 near_h = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	vec3 rd_view = normalize(near_h.xyz / near_h.w);
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize((INV_VIEW_MATRIX * vec4(rd_view, 0.0)).xyz);

	// --- how far until we hit something already drawn? ------------------------
	// Reverse-Z: a raw depth of 0.0 is the far plane, i.e. empty sky.
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	float scene_dist = 1e20;
	if (raw_depth > 0.0) {
		vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
		scene_dist = length(sv.xyz / sv.w); // camera sits at the view-space origin
	}

	// --- into hole-local natural units ----------------------------------------
	vec3 lo = (bh_inv_xform * vec4(ro, 1.0)).xyz / rs_world;
	vec3 ld = normalize((bh_inv_xform * vec4(rd, 0.0)).xyz);
	float influence_n = influence_radius / rs_world;

	// Skip straight to the bounding sphere; the path outside it is a line.
	// (cross(pos, dir) is invariant along a line, so advancing here does not
	// change the photon's angular momentum.)
	float b = dot(lo, ld);
	float c = dot(lo, lo) - influence_n * influence_n;
	float disc = b * b - c;
	if (disc < 0.0) {
		discard;
	}
	float t_enter = max(0.0, -b - sqrt(disc));
	float start_dist = t_enter * rs_world;
	if (start_dist >= scene_dist) {
		discard; // something opaque is in front of the whole volume
	}

	vec4 result = trace_ray(lo + ld * t_enter, ld, start_dist, scene_dist, TIME);

	// Linear HDR, premultiplied. WorldEnvironment does the tonemapping.
	ALBEDO = result.rgb * exposure;
	ALPHA = result.a;
}
