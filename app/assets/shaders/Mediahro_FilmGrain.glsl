// Mediahro film grain (VID-038).
// Copyright (c) 2026 the Mediahro authors. Part of Mediahro, licensed
// like the app under the GNU AGPL v3.0 or later (see About → Licences).
//
// Adds fine, moving, luma-only grain at screen resolution, strongest in
// the mid-tones and faint in deep shadows and highlights, like film.

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC Mediahro film grain

// Grain strength (0.0 to 0.2).
#define INTENSITY 0.045

// Hash without sine (Dave Hoskins, public domain technique).
float grain_hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec4 hook() {
    vec4 color = HOOKED_texOff(0);
    vec2 pixel = floor(HOOKED_pos * HOOKED_size);
    // A new pattern every frame; two hashes summed give a softer,
    // roughly triangular distribution.
    vec2 seed = pixel + vec2(random * 4096.0, random * 2731.0);
    float noise = grain_hash(seed) + grain_hash(seed + 17.0) - 1.0;
    float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    float weight = 0.35 + 2.6 * luma * (1.0 - luma);
    color.rgb += noise * INTENSITY * weight;
    return color;
}
