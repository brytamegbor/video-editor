// ---------------------------------------------------------------------------
// Octgrams — Shadertoy-style GLSL port that mirrors octgrams.metal 1:1 and fits
// magic_edit's GL effect contract. Host THIS file at the descriptor's `glslUrl`.
//
// Host-provided uniforms (the GL analogue of the Metal EffectUniforms):
//   uniform sampler2D iChannel0;   // input video frame (the live clip)
//   uniform vec3      iResolution; // viewport size in px (.xy used, .z unused)
//   uniform float     iTime;       // elapsed seconds (drives the loop)
//   uniform float     iIntensity;  // 0..1 effect strength slider
// Entry point: void mainImage(out vec4 fragColor, in vec2 fragCoord)
//
// These are declared injected by the host (Shadertoy convention). Only the
// non-standard `iIntensity` is declared below; delete that line if your host
// already injects it.
// ---------------------------------------------------------------------------
uniform float iIntensity;

// GLSL's mod() is already the floor-based x - y*floor(x/y), so the negative
// domain repetition `mod(pos-2,4)-2` works directly (no gmod helper needed).
mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, s, -s, c);
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float box(vec3 pos, float scale) {
    pos *= scale;
    float base = sdBox(pos, vec3(0.4, 0.4, 0.1)) / 1.5;
    return -base;
}

float box_set(vec3 pos, float gTime) {
    vec3 o = pos;
    float k = 2.0 - abs(sin(gTime * 0.4)) * 1.5;
    float wob = sin(gTime * 0.4) * 2.5;

    pos = o; pos.y += wob; pos.xy = pos.xy * rot(0.8);
    float box1 = box(pos, k);
    pos = o; pos.y -= wob; pos.xy = pos.xy * rot(0.8);
    float box2 = box(pos, k);
    pos = o; pos.x += wob; pos.xy = pos.xy * rot(0.8);
    float box3 = box(pos, k);
    pos = o; pos.x -= wob; pos.xy = pos.xy * rot(0.8);
    float box4 = box(pos, k);
    pos = o; pos.xy = pos.xy * rot(0.8);
    float box5 = box(pos, 0.5) * 6.0;
    pos = o;
    float box6 = box(pos, 0.5) * 6.0;

    return max(max(max(max(max(box1, box2), box3), box4), box5), box6);
}

float map(vec3 pos, float gTime) {
    return box_set(pos, gTime);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 iRes = iResolution.xy;
    vec2 p = (fragCoord * 2.0 - iRes) / min(iRes.x, iRes.y);
    vec3 ro = vec3(0.0, -0.2, iTime * 4.0);
    vec3 ray = normalize(vec3(p, 1.5));
    ray.xy = ray.xy * rot(sin(iTime * 0.03) * 5.0);
    ray.yz = ray.yz * rot(sin(iTime * 0.05) * 0.2);

    float t = 0.1;
    float ac = 0.0;
    for (int i = 0; i < 99; i++) {
        vec3 pos = ro + ray * t;
        pos = mod(pos - 2.0, 4.0) - 2.0;
        float gTime = iTime - float(i) * 0.01;
        float d = map(pos, gTime);
        d = max(abs(d), 0.01);
        ac += exp(-d * 23.0);
        t += d * 0.55;
    }

    vec3 col = vec3(ac * 0.02);
    col += vec3(0.0, 0.2 * abs(sin(iTime)), 0.5 + sin(iTime) * 0.2);

    // Blend the generated pattern over the actual video frame by intensity.
    vec4 src = texture(iChannel0, fragCoord / iResolution.xy);
    vec3 outc = mix(src.rgb, col, iIntensity);
    fragColor = vec4(outc, src.a);
}
