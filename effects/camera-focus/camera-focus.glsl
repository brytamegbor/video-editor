// ---------------------------------------------------------------------------
// Camera Focus (GLSL) — mirrors camera-focus.metal. A rack-focus that drifts
// out of focus and back with a disc-bokeh blur that blooms highlights, plus a
// touch of focus breathing.
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

const int kTaps = 24;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float t = iTime;
    float k = iIntensity;

    float focus = 0.5 - 0.5 * cos(t * 1.3);
    float blur  = focus * 0.025 * k;

    float breath = 1.0 - focus * 0.03 * k;
    vec2  cuv    = (uv - 0.5) * breath + 0.5;

    float bokeh = step(0.0001, blur);
    vec3  col   = vec3(0.0);
    float total = 0.0;
    for (int i = 0; i < kTaps; i++) {
        float fi  = float(i);
        float ang = fi * 2.399963229;
        float rad = sqrt((fi + 0.5) / float(kTaps)) * blur;
        vec2  off = vec2(cos(ang), sin(ang)) * rad;

        vec3  tcol = texture(iChannel0, cuv + off).rgb;
        float luma = max(tcol.r, max(tcol.g, tcol.b));
        float w    = 1.0 + smoothstep(0.6, 1.0, luma) * 3.0 * bokeh;
        col   += tcol * w;
        total += w;
    }
    col /= total;

    float a = texture(iChannel0, uv).a;
    fragColor = vec4(col, a);
}
