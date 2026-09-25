// ============================================================================
// volume.gdshaderinc -- the plumbing every raymarched landmark needs.
//
// Same skeleton Goliath.gdshader uses: a spatial shader on an inverted bounding
// sphere, drawn in the transparent pass, with each pixel's ray rebuilt from the
// inverse projection rather than from the mesh's own geometry -- so it stays
// correct when the camera is inside the volume and the near plane is slicing
// through it.
//
// Built-ins like INV_PROJECTION_MATRIX are only valid inside the stage
// function, which is why they are passed in as arguments here rather than read
// directly. That is the whole reason this is a set of helpers taking a long
// argument list instead of one setup() call.
// ============================================================================

// Rebuilds the world-space ray for a pixel and reports how far away the nearest
// thing already drawn into the depth buffer is.
void volume_ray(
		vec2 screen_uv, mat4 inv_proj, mat4 inv_view, vec3 cam_pos,
		sampler2D depth_tex,
		out vec3 ro, out vec3 rd, out float scene_dist) {
	vec4 near_h = inv_proj * vec4(screen_uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 rd_view = normalize(near_h.xyz / near_h.w);
	ro = cam_pos;
	rd = normalize((inv_view * vec4(rd_view, 0.0)).xyz);

	// Reverse-Z: a raw depth of 0.0 is the far plane, i.e. nothing there.
	float raw_depth = texture(depth_tex, screen_uv).r;
	scene_dist = 1e20;
	if (raw_depth > 0.0) {
		vec4 sv = inv_proj * vec4(screen_uv * 2.0 - 1.0, raw_depth, 1.0);
		scene_dist = length(sv.xyz / sv.w); // the camera is the view-space origin
	}
}

// Entry and exit distances along the ray for a sphere. False if it misses.
bool sphere_span(vec3 ro, vec3 rd, vec3 centre, float radius, out float t0, out float t1) {
	vec3 oc = ro - centre;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - radius * radius;
	float disc = b * b - c;
	if (disc < 0.0) {
		t0 = 0.0;
		t1 = 0.0;
		return false;
	}
	float root = sqrt(disc);
	t0 = max(0.0, -b - root);
	t1 = -b + root;
	return t1 > 0.0;
}

// How much of this pixel Goliath has already taken, 0..1.
//
// Goliath does not write depth -- nothing drawn in the transparent pass does --
// so two such volumes cannot sort against each other through the depth buffer,
// and whichever is drawn second wins whatever the geometry says. Since
// Goliath's march returns opaque for every pixel it does not find scene
// geometry on, everything else that skips the depth buffer has to yield to it.
//
// [b]Both of the things Goliath draws opaquely count.[/b] An earlier version
// tested only the shadow, on the reasoning that the disk is translucent and a
// landmark showing faintly through its outer edge was a minor error. In
// practice it is not minor at all: the disk is the brightest object in the
// scene and covers far more of the sky than the shadow does, so a nebula
// painted across it reads as a bug immediately. Both are handled here.
//
//   * [b]Shadow[/b] -- a straight-line impact parameter under the critical
//     3*sqrt(3)/2 rs is captured and never comes out. Feathered over the last
//     tenth of a radius so the edge is not a stair.
//   * [b]Disk[/b] -- solved as a ray/plane crossing in the hole's own frame
//     rather than marched. One divide and a length: where the ray crosses
//     y = 0, and whether that lands between the disk's inner and outer radii.
//     Grazing crossings pass through more gas, so the coverage is weighted by
//     the inverse of the ray's inclination to the plane, exactly as the disk's
//     own integration weights its emission.
//
// Returned as a fraction rather than a yes/no because a hard discard at the
// disk's rim would replace a compositing error with a visible cut-out.
float goliath_cover(
		vec3 ro, vec3 rd, float t_self,
		mat4 bh_inv, float rs, float disk_inner, float disk_outer) {
	if (rs <= 0.0) {
		return 0.0;
	}
	// Into the hole's frame, in Schwarzschild radii.
	vec3 lo = (bh_inv * vec4(ro, 1.0)).xyz / rs;
	vec3 ld = normalize((bh_inv * vec4(rd, 0.0)).xyz);
	float t_limit = t_self / rs;

	float b = dot(lo, ld);
	if (b > 0.0 && length(lo) > disk_outer) {
		return 0.0; // the whole system is behind the camera
	}

	float cover = 0.0;

	// --- shadow ---------------------------------------------------------------
	float impact = length(lo - ld * b);
	float t_shadow = -b - sqrt(max(2.598 * 2.598 - impact * impact, 0.0));
	if (impact < 2.85 && t_shadow > 0.0 && t_shadow < t_limit) {
		cover = max(cover, smoothstep(2.85, 2.45, impact));
	}

	// --- disk -----------------------------------------------------------------
	if (abs(ld.y) > 0.00001) {
		float t_plane = -lo.y / ld.y;
		if (t_plane > 0.0 && t_plane < t_limit) {
			vec3 hit = lo + ld * t_plane;
			float r = length(hit.xz);
			if (r > disk_inner * 0.85 && r < disk_outer * 1.08) {
				float band = smoothstep(disk_inner * 0.85, disk_inner * 1.05, r)
					* (1.0 - smoothstep(disk_outer * 0.88, disk_outer * 1.08, r));
				// 1/sin(inclination): a grazing ray crosses far more gas. Floored
				// so a face-on crossing still counts for something.
				float grazing = clamp(0.55 / max(abs(ld.y), 0.08), 0.0, 1.0);
				cover = max(cover, band * grazing);
			}
		}
	}

	return clamp(cover, 0.0, 1.0);
}

// Closest approach of a ray to a point: the distance, and how far along the ray
// it happens. Used for the star at the middle of a landmark, which is far too
// small for the march to reliably land a step on -- a 110-unit core inside a
// 3400-unit volume marched in 28 steps is missed more often than not. Drawing
// it analytically also gives it a clean bloom for free.
void closest_approach(vec3 ro, vec3 rd, vec3 point, out float distance_to, out float t_at) {
	vec3 oc = point - ro;
	t_at = dot(oc, rd);
	distance_to = length(oc - rd * t_at);
}
