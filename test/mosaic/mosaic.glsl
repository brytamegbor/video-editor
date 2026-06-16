// ---------------------------------------------------------------------------
// Mosaic (GLSL) — mirrors mosaic.metal. Ported from the GL-transitions "Mosaic"
// shader (Xaychru, MIT, https://gist.github.com/Xaychru/130bb7b7affedbda9df5).
//
// The original is a clip-to-clip transition (getFromColor/getToColor + progress).
// We only have one live frame, so both ends sample the same clip and `progress`
// is looped from iTime. The transition is the identity at progress 0 and 1, so a
// plain sawtooth loops seamlessly.
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

#define MPI 3.14159265358979323
const int END_X = 2;
const int END_Y = -1;

float rand2(vec2 v) {
    return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}
vec2 rot2(vec2 v, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * v.x + s * v.y, -s * v.x + c * v.y);
}
float cosInterp(float x) {
    return -cos(x * MPI) / 2.0 + 0.5;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv = fragCoord / iResolution.xy;
    float progress = fract(iTime * 0.32);

    vec2  p   = uv - 0.5;
    vec2  rp  = p;
    float rpr = progress * 2.0 - 1.0;
    float z   = -(rpr * rpr * 2.0) + 3.0;
    float az  = abs(z);
    rp *= az;
    float ci = cosInterp(progress);
    rp += mix(vec2(0.5),
              vec2(float(END_X) + 0.5, float(END_Y) + 0.5),
              ci * ci);

    vec2 mrp = fract(rp);                      // mod(rp, 1.0)
    vec2 crp = rp;
    bool onEnd = int(floor(crp.x)) == END_X && int(floor(crp.y)) == END_Y;
    if (!onEnd) {
        float ang = float(int(rand2(floor(crp)) * 4.0)) * 0.5 * MPI;
        mrp = vec2(0.5) + rot2(mrp - vec2(0.5), ang);
    }

    vec4 tileCol = texture(iChannel0, mrp);    // from == to == the single live clip

    vec4 clean = texture(iChannel0, uv);
    vec3 outc  = mix(clean.rgb, tileCol.rgb, iIntensity);
    fragColor = vec4(outc, clean.a);
}
