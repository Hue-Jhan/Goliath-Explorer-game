// ============================================================================
// GoliathSky.gdshader -- the unlensed backdrop, drawn everywhere outside
// Goliath's influence volume.
//
// Shares starfield.gdshaderinc with Goliath.gdshader, which samples the exact
// same functions along each photon's *lensed* exit direction. Because the
// volume's deflection falloff has decayed to ~1e-5 by its boundary, the two
// agree there and the boundary is invisible.
//
// Emits linear HDR; WorldEnvironment tonemaps.
// ============================================================================

shader_type sky;

#include "res://environment/starfield.gdshaderinc"

uniform float exposure = 1.3;

void sky() {
	COLOR = deep_space(EYEDIR, TIME) * exposure;
}
