// ---------------------------------------------------------------------------
// Slash Reveal (GLSL) — mirrors slash-reveal.metal. A bright diagonal slash
// sweeps across; ahead of the cut the frame is mirrored across the slash line,
// behind it the true frame shows, with a hot streak on the edge.
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

    float ang  = -0.5235988;                  // radians(-30)
    vec2  dir  = vec2(cos(ang), sin(ang));
    vec2  nrm  = vec2(-dir.y, dir.x);
    float proj = dot(uv - 0.5, nrm);

    float tri = 1.0 - abs(fract(t * 0.5) * 2.0 - 1.0);   // 0..1..0
    float sp  = (tri * 2.0 - 1.0) * 0.5;                 // -0.5..0.5..-0.5

    float side = step(sp, proj);
    vec2  mir  = clamp(uv - 2.0 * (proj - sp) * nrm, 0.0, 1.0);

    vec4 srcN = texture(iChannel0, uv);
    vec3 mC   = texture(iChannel0, mir).rgb;
    vec3 col  = mix(srcN.rgb, mC, side);

    float streak = smoothstep(0.05, 0.0, abs(proj - sp));
    col += vec3(1.0, 0.95, 0.9) * streak * (0.7 + 0.3 * sin(t * 25.0));

    vec3 outc = mix(srcN.rgb, col, k);
    fragColor = vec4(outc, srcN.a);
}
