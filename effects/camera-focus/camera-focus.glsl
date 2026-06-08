// ---------------------------------------------------------------------------
// Camera Focus (GLSL) — mirrors camera-focus.metal. Draws a phone-camera
// autofocus reticle (four corner brackets + a centre dot) that snaps in with a
// brief "lock" zoom animation on a loop.
//
// Host-provided uniforms (GL analogue of the Metal EffectUniforms):
//   uniform sampler2D iChannel0;   // input video frame (the live clip)
//   uniform vec3      iResolution; // viewport px (.xy used)
//   uniform float     iTime;       // elapsed seconds (drives the loop)
//   uniform float     iIntensity;  // 0..1 reticle opacity; 0 == untouched frame
// Entry point: void mainImage(out vec4 fragColor, in vec2 fragCoord)
// (Delete the iIntensity line below if your host already injects it.)
// ---------------------------------------------------------------------------
uniform float iIntensity;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv = fragCoord / iResolution.xy;
    float t  = iTime;
    float k  = iIntensity;

    vec4 base = texture(iChannel0, uv);

    float aspect = iResolution.x / iResolution.y;
    vec2  p = (uv - 0.5);
    p.x *= aspect;

    float px = 1.0 / iResolution.y;
    float aa = 1.2 * px;

    float ph    = fract(t / 2.2);
    float lock  = pow(1.0 - clamp(ph / 0.35, 0.0, 1.0), 2.0);
    float scale = 1.0 + 0.26 * lock;

    float h        = 0.16 * scale;
    float legLen   = h * 0.32;
    float lineHalf = 1.6 * px;

    float dV = abs(abs(p.x) - h);
    float dH = abs(abs(p.y) - h);
    float lineV = 1.0 - smoothstep(lineHalf, lineHalf + aa, dV);
    float lineH = 1.0 - smoothstep(lineHalf, lineHalf + aa, dH);

    float legY = smoothstep(h - legLen - aa, h - legLen + aa, abs(p.y)) *
                 (1.0 - smoothstep(h + lineHalf, h + lineHalf + aa, abs(p.y)));
    float legX = smoothstep(h - legLen - aa, h - legLen + aa, abs(p.x)) *
                 (1.0 - smoothstep(h + lineHalf, h + lineHalf + aa, abs(p.x)));

    float bracket = max(lineV * legY, lineH * legX);

    float dotR = 0.012;
    float dotM = 1.0 - smoothstep(dotR, dotR + aa, length(p));

    float reticle = max(bracket, dotM);

    float glow      = 0.65 + 0.35 * lock;
    vec3  lineColor = vec3(1.0, 0.97, 0.85);

    vec3 col  = mix(base.rgb, lineColor, reticle * glow);
    vec3 outc = mix(base.rgb, col, k);
    fragColor = vec4(outc, base.a);
}
