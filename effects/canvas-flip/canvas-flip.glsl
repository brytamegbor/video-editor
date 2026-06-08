// ---------------------------------------------------------------------------
// Canvas Flip (GLSL) — mirrors canvas-flip.metal. The frame rotates in 3D about
// its vertical axis like a card with perspective; back face is mirrored, gaps
// show a dim mirrored copy behind.
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

    vec2 p = uv - 0.5;

    float a  = t * 1.2;
    float ca = cos(a), sa = sin(a);
    float kp = 0.8;

    float denom = ca - p.x * sa * kp;
    float lx    = p.x / denom;
    float Z     = lx * sa;
    float ly    = p.y * (1.0 + Z * kp);

    bool onCard = (abs(lx) <= 0.5) && (abs(ly) <= 0.5);
    bool back   = ca < 0.0;

    float texU = lx + 0.5;
    float texV = ly + 0.5;
    if (back) { texU = 1.0 - texU; }

    vec3 card = texture(iChannel0, vec2(texU, texV)).rgb;
    vec3 bg   = texture(iChannel0, vec2(1.0 - uv.x, uv.y)).rgb * 0.25;
    vec3 flip = onCard ? card : bg;

    vec4 srcN = texture(iChannel0, uv);
    vec3 outc = mix(srcN.rgb, flip, k);
    fragColor = vec4(outc, srcN.a);
}
