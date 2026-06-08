// ---------------------------------------------------------------------------
// Spin & Shake (GLSL) — mirrors spin-shake.metal. The frame whips back and forth
// in rotation while a high-frequency camera shake jitters it and a scale punch
// pumps in and out.
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
    vec2  uv     = fragCoord / iResolution.xy;
    float t      = iTime;
    float k      = iIntensity;
    float aspect = iResolution.x / iResolution.y;

    vec2 p = uv - 0.5;
    p.x *= aspect;

    float ang = sin(t * 4.0) * 0.35 * k + sin(t * 1.3) * 0.10 * k;
    float ca  = cos(ang), sa = sin(ang);
    p = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

    float punch    = 1.0 - (0.5 + 0.5 * sin(t * 8.0)) * 0.08 * k;
    float overscan = 1.0 + 0.08 * k;
    p = p / overscan * punch;

    p.x /= aspect;

    vec2 shake = vec2(
        sin(t * 43.0) + 0.5 * sin(t * 27.0),
        cos(t * 39.0) + 0.5 * sin(t * 23.0)
    ) * 0.01 * k;

    vec2 suv = p + 0.5 + shake;
    fragColor = texture(iChannel0, suv);
}
