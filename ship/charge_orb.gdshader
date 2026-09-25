shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// The Q-ability charging sphere.
//
// Unshaded and additive: this is contained plasma, not a lit surface, and the
// only thing behind it is the player's own nose cone. Everything animates off
// TIME and a single `charge` uniform, so the whole build-up -- colour, density,
// rim flare -- is one number the game code already has to track anyway.

uniform float charge : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;

void vertex() {
	v_local = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(v_local);
	// Two bands of detail turning against each other. Cheap, and at the size
	// this is ever drawn at (a sphere a couple of units across, right under the
	// camera) it reads as convection without costing a noise lookup.
	float a = sin(n.x * 7.0 + TIME * 2.7) * cos(n.y * 6.0 - TIME * 2.1);
	float b = sin(n.z * 9.0 - TIME * 3.3) * cos(n.x * 5.0 + TIME * 1.7);
	float swirl = 0.5 + 0.5 * (a * 0.6 + b * 0.4);

	// Blue while it spins up, green as it fills, white-hot at full charge: the
	// pilot should be able to read the state off the colour without the gauge.
	vec3 tone = mix(vec3(0.14, 0.42, 1.0), vec3(0.24, 1.0, 0.62), charge);
	tone = mix(tone, vec3(1.0), pow(charge, 2.5) * 0.8);

	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
	float energy = (0.30 + swirl * 0.95) * (0.22 + charge * 1.85);

	ALBEDO = tone * energy;
	EMISSION = tone * (energy * 3.4 + fres * 2.6 * charge);
	ALPHA = clamp(energy * 0.8 + fres * 0.45 * charge, 0.0, 1.0);
}
