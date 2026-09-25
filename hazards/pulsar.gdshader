// ============================================================================
// pulsar.gdshader -- the twin radiation beams and the neutron star at their
// apex, raymarched.
//
// Replaces two nested cone meshes per beam. A cone at any opacity has a hard
// straight silhouette and reads as a wedge of coloured plastic, and no amount
// of vertex-alpha fading fixes the edge -- the edge is the mesh. A density
// field has no edge.
//
// [b]What is deliberately still geometry:[/b] the magnetosphere. The field
// lines are lines, a line mesh draws lines exactly, and marching a volume to
// recover something that is already a curve would be both slower and worse. It
// would also be much worse *here* specifically: a field line is a few hundred
// units thick inside an eleven-kilometre volume, so a march coarse enough to
// afford would step straight over it. See CelestialMesh.dipole_lines().
//
// The march runs in the magnetic frame, where the axis is +Y. Rotating the
// node is therefore all it takes to sweep the beams -- no per-frame maths in
// here, one mat4 upload a frame.
// ============================================================================

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled,
	blend_premul_alpha, shadows_disabled, fog_disabled, specular_disabled;

#include "res://hazards/volume.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform mat4 mag_inv_xform;             // world -> magnetic-local (rigid, no scale)
uniform vec3 centre_world = vec3(0.0);
uniform float volume_radius = 11600.0;  // world units; the mesh's own radius
uniform float beam_reach = 11000.0;     // world units; 1.0 in beam units
uniform float core_radius = 46.0;

// Half-angle of the beam, radians. The same number the hull damage is gated
// on, so what you can see and what burns you cannot drift apart. At exactly
// this angle the beam is at 1/e of its axial brightness: the damaging cone is
// the bright core of what is drawn, not its full visible extent.
uniform float beam_half_angle = 0.14;

// Goliath, so this volume can stand aside where the hole has already claimed
// the pixel. See goliath_cover() in volume.gdshaderinc.
uniform mat4 bh_inv_xform;
uniform float bh_rs = 0.0;
uniform float bh_disk_inner = 3.0;
uniform float bh_disk_outer = 17.0;

uniform float exposure = 1.0;
uniform float brightness = 1.0;

const int MAX_STEPS = 72;
uniform int steps = 44;

// Opacity per unit density per beam unit of path, and emission per unit
// opacity.
//
// These two are a ratio, and getting the ratio wrong is not a brightness
// problem -- it is a *sign* problem. Premultiplied alpha composites as
// src.rgb + dst * (1 - src.a), so a volume that accumulates more opacity than
// it deposits colour subtracts from whatever is behind it. At an extinction of
// 1.8 the beams reached about 0.9 opacity down the axis while depositing well
// under that in light, and the visible result was a searchlight that cut a grey
// band *out* of the nebula behind it. A beam is not a wall: it should tint what
// it crosses, not hide it. Opacity down the axis now lands near 0.3.
const float EXTINCTION = 0.55;
const float BEAM_GAIN = 3.0;
const float HAZE_GAIN = 1.2;

// Step bounds, in beam units. See the note in the march for why the step is
// proportional to radius rather than uniform across the span.
const float STEP_MIN = 0.006;
const float STEP_MAX = 0.085;


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
		discard;
	}
	float hole = goliath_cover(ro, rd, t_enter, bh_inv_xform, bh_rs, bh_disk_inner, bh_disk_outer);
	if (hole > 0.995) {
		discard;
	}
	float t_end = min(t_exit, scene_dist);
	if (t_end <= t_enter) {
		discard;
	}

	// Cheap rejection for the vast majority of samples: outside 2.2 half-angles
	// the cone term is already under 0.002, so the acos never has to be taken.
	float cone_cut = cos(min(beam_half_angle * 2.2, 1.55));
	float inv_half = 1.0 / max(beam_half_angle, 0.001);

	float inv_reach = 1.0 / max(beam_reach, 1.0);
	// Dithered entry: uniform steps through a smooth field band, and the bands
	// read far worse than the noise that replaces them.
	float jitter = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);
	float travelled = t_enter + STEP_MIN * beam_reach * jitter;

	vec3 accum = vec3(0.0);
	float alpha = 0.0;

	for (int i = 0; i < MAX_STEPS; i++) {
		if (i >= steps || alpha > 0.99 || travelled >= t_end) { break; }
		vec3 world = ro + rd * travelled;
		vec3 p = (mag_inv_xform * vec4(world, 1.0)).xyz * inv_reach;
		float r = length(p);
		float ax = r > 1e-5 ? abs(p.y) / r : 1.0;

		// Step proportional to distance from the star, which is exactly the
		// right invariant for a cone: the beam's width grows with r, so a step
		// of r * k always lands the same number of samples across it -- about
		// three here, at every radius. Uniform steps do not have that property,
		// and near the star the beam is narrower than one of them: measured,
		// that dropped whole samples and turned the beam into grey speckle,
		// which is what the dither was then making worse rather than hiding.
		float dt_n = clamp(r * 0.12, STEP_MIN, STEP_MAX);
		float dt = min(dt_n * beam_reach, t_end - travelled);
		float seg = dt * inv_reach;
		travelled += dt;
		if (r > 1.06) { continue; }

		// Magnetospheric haze: a soft glow hugging the star, which is what
		// gives the field lines something to sit inside instead of hanging in
		// vacuum.
		float haze = exp(-pow(r / 0.045, 2.0)) * 0.7;

		float beam = 0.0;
		if (ax > cone_cut) {
			float ang = acos(clamp(ax, 0.0, 1.0));
			float cone = exp(-pow(ang * inv_half, 2.3));
			// Fades along its length, and is choked off right at the surface so
			// the two cones read as leaving the star rather than passing
			// through it.
			float reach = exp(-pow(r / 0.80, 2.0)) * smoothstep(0.0, 0.025, r);
			// Striations running outward: the beam needs motion in it.
			float ripple = 0.80 + 0.20 * sin(r * 38.0 - TIME * 7.0);
			beam = cone * reach * ripple;
		}

		float density = beam + haze;
		if (density > 0.002) {
			// Whitens hard on the axis, so the beam has a hot core inside a
			// cooler sheath rather than being one flat blue.
			// Tight white core inside a blue sheath. The exponent is high so the
			// white is confined to the axis -- at 8 it whitened most of the
			// visible cone and the beam came out a neutral grey searchlight.
			vec3 col = mix(vec3(0.28, 0.56, 1.0), vec3(0.88, 0.94, 1.0), pow(ax, 24.0));
			float a = 1.0 - exp(-density * EXTINCTION * seg);
			accum += (1.0 - alpha)
				* (col * beam * BEAM_GAIN + vec3(0.42, 0.60, 1.0) * haze * HAZE_GAIN)
				* brightness * a / max(density, 0.001);
			alpha += (1.0 - alpha) * a;
		}
	}

	// The neutron star. Analytic, for the same reason the white dwarf is: a
	// 46-unit core inside an eleven-kilometre volume is not something a 26-step
	// march is ever going to land a sample on.
	float core_dist;
	float core_t;
	closest_approach(ro, rd, centre_world, core_dist, core_t);
	if (core_t > t_enter && core_t < t_end) {
		float cr = max(core_radius, 1.0);
		float disc = smoothstep(cr * 1.3, cr * 0.6, core_dist);
		// See the note on the same term in remnant.gdshader: above the scene's
		// glow threshold a shallow bloom tail is what washes the frame out, not
		// the volume it sits in.
		float bloom = 1.0 / (1.0 + pow(core_dist / (cr * 2.8), 3.4));
		vec3 star = vec3(0.80, 0.88, 1.0) * (disc * 5.0 + bloom * 0.9);
		accum += (1.0 - alpha) * star;
		alpha = max(alpha, disc);
	}

	float visible = 1.0 - hole;
	ALBEDO = accum * exposure * visible;
	ALPHA = clamp(alpha, 0.0, 1.0) * visible;
}
