// ============================================================================
// remnant.gdshader -- a planetary nebula around a white dwarf, raymarched.
//
// Replaces a pile of additive meshes: braided tori for the rings, a MultiMesh
// of instanced darts for the cometary knots, and nested spheres for the gas.
// That approach could be made to read as gas from one distance and one angle
// at a time, and never from all of them -- a torus has a silhouette, an
// instanced dart has a silhouette, and a shell of gas has none. Marching a
// density field has no silhouettes anywhere, which is the entire point.
//
// Structured after Goliath.gdshader and sharing its conventions: inverted
// bounding sphere, ray from the inverse projection, depth-buffer clamping so
// ships occlude it, linear HDR out for the scene's ACES tonemapper, and
// premultiplied alpha.
// ============================================================================

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled,
	blend_premul_alpha, shadows_disabled, fog_disabled, specular_disabled;

// For noise3/fbm and the sky_detail octave budget, so the graphics slider
// reaches in here without a second control.
#include "res://environment/starfield.gdshaderinc"
#include "res://hazards/volume.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform mat4 inv_xform;             // world -> remnant-local (rigid, no scale)
uniform vec3 centre_world = vec3(0.0);
uniform float volume_radius = 3900.0;   // world units; the mesh's own radius
uniform float gas_radius = 3400.0;      // world units; 1.0 in shell units
uniform float core_radius = 110.0;      // world units; the white dwarf

// Goliath, so this volume can stand aside where the hole has already claimed
// the pixel. See goliath_cover() in volume.gdshaderinc.
uniform mat4 bh_inv_xform;
uniform float bh_rs = 0.0;
uniform float bh_disk_inner = 3.0;
uniform float bh_disk_outer = 17.0;

uniform float exposure = 1.0;
uniform float brightness = 1.0;

const int MAX_STEPS = 48;
uniform int steps = 20;

// Octaves for the gas noise, separate from the sky's. Measured: sitting inside
// this volume cost +25.7 ms of a 31 ms frame, essentially all of it the two fBm
// evaluations per step. Fewer octaves, fewer steps and an early-out before any
// noise is sampled at all brought that down without changing what it looks
// like -- see fbm_gas() for why the octave count does not alter the look.
uniform int gas_octaves : hint_range(2, 4) = 3;


// fBm normalised by its own amplitude sum, so its mean and variance do not move
// when the octave count does.
//
// The unnormalised version in starfield.gdshaderinc has a mean of 0.469 at four
// octaves and 0.437 at three, and the filament threshold below subtracts 0.95
// from 2.06x that -- a 0.03 shift in the mean moves the amount of gas that
// clears the threshold by a factor of several. Without this, turning the
// graphics slider down would not make the nebula coarser, it would make it
// vanish.
float fbm_gas(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= octaves) { break; }
		v += a * noise3(p);
		norm += a;
		p *= 2.02;
		a *= 0.5;
	}
	return v / max(norm, 0.0001);
}

// Opacity per unit density per shell unit of path, and emission per unit
// opacity before the ramp.
//
// Both were solved numerically rather than guessed, because guessing produced a
// full-screen white-out on the first attempt: the density function was
// reimplemented in Python -- same hash, same value noise, same fBm -- and rays
// were integrated across the image at three camera distances. What that
// measures that eyeballing a single ray does not is *screen-space* contrast.
// The filament term is sampled on direction only, so it barely varies along any
// one ray; the variation the eye reads as structure is between neighbouring
// pixels, and the metric has to be the spread of brightness across rays.
//
// Solved profile at 4.3 km out: peak brightness at the 10th/50th/90th
// percentile of 0.12 / 0.47 / 1.03, opacity 0.04 / 0.17 / 0.35. Better than
// eight times the contrast of the first version at a sixth of its brightness,
// and translucent enough that stars read through most of it. The 2.06 and 1.50
// multipliers in gas_density() are those solved constants rescaled for the
// normalised fBm below; the ratios they encode are unchanged.
const float EXTINCTION = 4.8;
const float GAIN = 2.40;

// The ionisation gradient: hot blue-white oxygen at the inside edge, green
// through the body, shocked hydrogen rust at the rim. It is also the only cue
// the player has for which way is out.
vec3 gas_ramp(float r) {
	vec3 c = mix(vec3(0.30, 0.92, 1.05), vec3(0.34, 1.00, 0.58), smoothstep(0.30, 0.60, r));
	c = mix(c, vec3(1.00, 0.52, 0.24), smoothstep(0.60, 0.92, r));
	return c;
}

// Density at a point, in shell units where 1.0 is the gas radius.
float gas_density(vec3 p, float t) {
	float r = length(p);
	if (r > 1.10 || r < 0.04) {
		return 0.0;
	}
	vec3 u = p / r;

	// Two radial shells: the bright inner rim and a broader, fainter halo.
	float inner = exp(-pow((r - 0.54) / 0.17, 2.0));
	float outer = exp(-pow((r - 0.87) / 0.23, 2.0));
	float shell = inner + outer * 0.66;

	// The bright annulus. Flattened toward the equatorial plane, which is what
	// makes a planetary nebula read as a ring seen at an angle rather than as a
	// ball -- the Helix is exactly this.
	float ring = exp(-pow((r - 0.60) / 0.13, 2.0)) * exp(-pow(p.y / 0.36, 2.0)) * 0.80;

	// Everything below multiplies these two, so if there is no envelope here
	// there is no gas, and the two noise evaluations -- which are the whole cost
	// of this shader -- never have to happen. Pays for itself on the empty
	// middle of the shell and on everything past its rim.
	if (shell + ring < 0.02) {
		return 0.0;
	}

	// Cometary knots. The trick here is sampling the noise on the *direction*
	// only: a feature then stays constant all the way along a radius, so it
	// reads as a finger of gas pointing at the star instead of as a blob
	// floating in it. This is what the instanced darts were trying to be.
	//
	// The threshold is high on purpose. fBm has a mean near 0.47 and a standard
	// deviation near 0.12, so subtracting 0.95 from 2.2x it leaves most
	// directions at zero and lets a minority through -- which is the difference
	// between filaments and fog, and it is the single parameter that decided
	// whether this looked like gas.
	// Twisted with radius before sampling, so the fingers *curve* outward
	// instead of converging on the centre in perfectly straight spokes. Without
	// it the direction-only sampling renders a flawless starburst, which reads
	// as a lens flare rather than as gas. A rigid rotation of the sample point
	// changes none of the statistics the extinction and gain were solved
	// against, only where the features land.
	float twist = r * 1.7;
	float cs = cos(twist);
	float sn = sin(twist);
	vec3 ut = vec3(u.x * cs - u.z * sn, u.y, u.x * sn + u.z * cs);
	float fingers = fbm_gas(ut * 7.4 + vec3(0.0, t * 0.008, 0.0), gas_octaves);
	fingers = pow(clamp(fingers * 2.06 - 0.95, 0.0, 1.0), 1.6);

	// Volumetric turbulence on top, drifting slowly, and gated so it can reach
	// *zero*. That gate is not decoration. Because the finger term is sampled on
	// direction alone it is constant all the way along a radius, and a field
	// that never breaks along its length renders as a perfect starburst -- which
	// is what cometary knots physically are and what a lens flare looks like.
	// Letting a positional term switch each finger off in places breaks it into
	// clumps without touching the direction it points.
	// One octave fewer than the filaments: this only has to break them up at a
	// coarse scale, and it is the cheaper half of the two to give up.
	float turb = fbm_gas(p * 4.2 + vec3(t * 0.011, 0.0, -t * 0.008), max(gas_octaves - 1, 2));
	float gate = clamp(1.50 * turb - 0.35, 0.0, 1.5);

	// The shell contributes almost nothing on its own: between the fingers there
	// is meant to be nothing to see.
	float d = (shell * (0.02 + fingers) + ring * (0.20 + fingers)) * gate;
	return max(d - 0.02, 0.0);
}

void fragment() {
	vec3 ro;
	vec3 rd;
	float scene_dist;
	volume_ray(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, CAMERA_POSITION_WORLD,
		depth_tex, ro, rd, scene_dist);

	float t_enter;
	float t_exit;
	if (!sphere_span(ro, rd, centre_world, volume_radius, t_enter, t_exit)) {
		discard;
	}
	if (t_enter >= scene_dist) {
		discard; // something opaque is in front of the whole volume
	}
	float hole = goliath_cover(ro, rd, t_enter, bh_inv_xform, bh_rs, bh_disk_inner, bh_disk_outer);
	if (hole > 0.995) {
		discard;
	}
	float t_end = min(t_exit, scene_dist);
	if (t_end <= t_enter) {
		discard;
	}

	// --- march the gas -------------------------------------------------------
	float span = t_end - t_enter;
	float dt = span / float(steps);
	// Dither the entry point by a per-pixel hash. Uniform steps across a smooth
	// density field band cleanly, and the bands are far more visible than the
	// noise that replaces them.
	float jitter = hash13(vec3(SCREEN_UV * 1024.0, 1.0));
	float travelled = t_enter + dt * jitter;

	vec3 accum = vec3(0.0);
	float alpha = 0.0;
	float inv_gas = 1.0 / max(gas_radius, 1.0);
	// Step length in shell units. Everything below integrates against this
	// rather than against the step index, so turning the graphics slider
	// changes how finely the gas is sampled and not how bright it is.
	float seg = dt * inv_gas;

	for (int i = 0; i < MAX_STEPS; i++) {
		if (i >= steps || alpha > 0.992) { break; }
		vec3 world = ro + rd * travelled;
		vec3 local = (inv_xform * vec4(world, 1.0)).xyz * inv_gas;
		float d = gas_density(local, TIME);
		if (d > 0.001) {
			// Textbook emission-absorption: opacity is 1 - exp(-tau) over the
			// segment, and emission is deposited in proportion to it.
			float a = 1.0 - exp(-d * EXTINCTION * seg);
			vec3 emit = gas_ramp(length(local)) * GAIN * brightness;
			accum += (1.0 - alpha) * emit * a;
			alpha += (1.0 - alpha) * a;
		}
		travelled += dt;
	}

	// --- the white dwarf, drawn analytically ---------------------------------
	float core_dist;
	float core_t;
	closest_approach(ro, rd, centre_world, core_dist, core_t);
	if (core_t > t_enter && core_t < t_end) {
		float cr = max(core_radius, 1.0);
		// A hard disc for the star itself, and a wide inverse-square bloom for
		// the glare around it.
		float disc = smoothstep(cr * 1.25, cr * 0.55, core_dist);
		// Steep, and deliberately dim for a star. Everything above the scene's
		// glow threshold of 1.1 blooms, and a bright core with a shallow falloff
		// puts a kilometre-wide glare tail over that threshold -- which the glow
		// pass then smears across the whole frame. The white-out that produced
		// was the star, not the gas. The disc itself still clips to white; what
		// changed is how far its halo carries.
		float bloom = 1.0 / (1.0 + pow(core_dist / (cr * 2.2), 3.4));
		vec3 star = vec3(0.86, 0.94, 1.0) * (disc * 4.0 + bloom * 0.8);
		accum += (1.0 - alpha) * star;
		alpha = max(alpha, disc);
	}

	float visible = 1.0 - hole;
	ALBEDO = accum * exposure * visible;
	ALPHA = clamp(alpha, 0.0, 1.0) * visible;
}
