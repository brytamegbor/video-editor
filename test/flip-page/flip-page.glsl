// ---------------------------------------------------------------------------
// Flip Page (GLSL) — mirrors flip-page.metal. A page sweeps across the frame
// wrapping around a rolling cylinder, peeling the current frame off to reveal
// the frame underneath (a continuous page-turn loop).
//
// Adapted from "Flip Page" by Lucian Stanculescu (2019), free to use.
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

#define PAGE_R   0.3   // radius of rolling cylinder (fraction of width)
#define PAGE_REP 3.0   // seconds per page-turn loop

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  res = iResolution.xy;
    float k   = iIntensity;

    float R    = PAGE_R * res.x;          // radius of rolling cylinder (px)
    float v    = 1.5 * res.x / PAGE_REP;  // sweep speed
    float time = fract(iTime / PAGE_REP); // 0..1 progress through the loop

    vec2 s = fragCoord;                       // pixel coordinates
    vec2 u = normalize(vec2(5.0, 1.0));       // direction of movement
    vec2 o = vec2(time * PAGE_REP * v, 0.0);  // origin of cylinder

    float d = dot(s - o, u); // signed distance to generator of cylinder
    vec2  h = s - u * d;     // projection on generator

    bool  onCylinder = abs(d) < R;
    float angle      = onCylinder ? asin(d / R) : 0.0;
    bool  neg        = d < 0.0;

    float a0 = 3.141592653 + angle;
    float a  = onCylinder ? (neg ? -angle : (3.141592653 + angle)) : 0.0; // angle

    float l = R * a;     // length of arc
    vec2  p = h - u * l; // unwrapped point from cylinder to plane
    bool  outside = any(lessThan(p, vec2(0.0))) || any(greaterThan(p, res));

    bool previous = (!onCylinder || outside) && neg;
    bool page     = !onCylinder || outside;

    vec4 color;
    if (page) color = texture(iChannel0, fragCoord / res);
    else      color = texture(iChannel0, p / res);
    color *= (previous ? mix(0.1, 1.0, time) : 1.0);

    l = R * a0;     // length of arc (back face of the curl)
    p = h - u * l;  // unwrapped point from cylinder to plane
    outside = any(lessThan(p, vec2(0.0))) || any(greaterThan(p, res));
    color = (outside || !onCylinder) ? color : texture(iChannel0, p / res);

    vec4 srcN = texture(iChannel0, fragCoord / res);
    vec3 outc = mix(srcN.rgb, color.rgb, k);
    fragColor = vec4(outc, srcN.a);
}
