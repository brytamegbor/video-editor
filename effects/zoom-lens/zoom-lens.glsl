// ---------------------------------------------------------------------------
// Zoom Lens (GLSL) — mirrors zoom-lens.metal. A breathing lens that magnifies
// the live frame from its centre with barrel distortion + chromatic aberration.
//
// Host-provided uniforms (GL analogue of the Metal EffectUniforms):
//   uniform sampler2D iChannel0;   // input video frame (the live clip)
//   uniform vec3      iResolution; // viewport px (.xy used)
//   uniform float     iTime;       // elapsed seconds (drives the loop)
//   uniform float     iIntensity;  // 0..1 strength; 0 == untouched frame
// Entry point: void mainImage(out vec4 fragColor, in vec2 fragCoord)
// (Delete the iIntensity line below if your host already injects it.)
// ---------------------------------------------------------------------------
uniform float iIntensity;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float t = iTime;
    float k = iIntensity;

    vec2  c = uv - 0.5;
    float r = length(c);

    float pulse = 0.5 - 0.5 * cos(t * 3.0);          // 0..1
    float zoom  = pulse * 0.35 * k;
    float lens  = 1.0 - zoom * (1.0 + r * r * 1.5);

    float ca = zoom * 0.06 * (0.3 + r);

    vec3 col;
    col.r    = texture(iChannel0, 0.5 + c * (lens - ca)).r;
    vec4 g   = texture(iChannel0, 0.5 + c * lens);
    col.g    = g.g;
    col.b    = texture(iChannel0, 0.5 + c * (lens + ca)).b;

    col *= 1.0 - zoom * r * 0.8;

    fragColor = vec4(col, g.a);
}
