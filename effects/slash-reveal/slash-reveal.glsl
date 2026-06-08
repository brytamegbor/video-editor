// ---------------------------------------------------------------------------
// Slash Reveal (GLSL) — mirrors slash-reveal.metal. A bright blade slashes along
// the bottom-left -> top-right "/" diagonal, cutting the top layer open to
// reveal an offset mirror beneath, with a hot streak on the cut.
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
    vec2  uv = fragCoord / iResolution.xy;
    float t  = iTime;
    float k  = iIntensity;

    // Seam runs bottom-left -> top-right ("/"); `n` is its normal. GLSL is
    // y-up (fragCoord.y = 0 at the bottom), so that diagonal's normal is (-1,1).
    vec2  n = normalize(vec2(-1.0, 1.0));
    float d = dot(uv - 0.5, n);

    float tri = abs(fract(t * 0.5) * 2.0 - 1.0); // 1 -> 0 -> 1
    float sp  = (tri * 2.0 - 1.0) * 0.72;        // +0.72 (closed) .. -0.72 (open)

    float px = 1.0 / iResolution.y;
    float aa = 1.5 * px;

    vec4  srcN   = texture(iChannel0, uv);
    float reveal = smoothstep(sp - aa, sp + aa, d);

    vec2  bUV     = clamp(vec2(1.0 - uv.x, uv.y) - n * 0.015, 0.0, 1.0);
    vec3  beneath = texture(iChannel0, bUV).rgb;

    vec3 col = mix(srcN.rgb, beneath, reveal);

    float streak = smoothstep(0.02, 0.0, abs(d - sp));
    col += vec3(1.0, 0.96, 0.9) * streak * (0.75 + 0.25 * sin(t * 22.0));

    vec3 outc = mix(srcN.rgb, col, k);
    fragColor = vec4(outc, srcN.a);
}
