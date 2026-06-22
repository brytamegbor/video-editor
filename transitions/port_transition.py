#!/usr/bin/env python3
"""
port_transition.py — turn a gl-transitions GLSL snippet into a wrapped Metal
kernel for the downloadable catalog, register it in transitions.json, and
(optionally) render its preview GIF.

It automates exactly what was done by hand for the existing transitions:

  1. Read the GLSL (a .md/.glsl/.frag file, or a fenced ```glsl block inside it).
  2. Translate the body to Metal: type renames, `uniform`s packed onto
     params.x..w, helper functions made `static inline`, common builtins remapped.
  3. Emit transitions/<id>/<id>.metal as the FULL wrapped kernel (same template
     as crosswarp/wind/cube/…), with `kernel void trx_<id>`.
  4. Upsert the descriptor in transitions.json (default params come from the
     uniforms' `// = ...` defaults).
  5. Compile-check with `xcrun metal -c` — the honesty gate. If the auto
     translation can't express something in Metal, this fails with a line number.
  6. Unless --no-gif, run make_gifs.swift for this id to produce <id>/<id>.gif.

Usage:

    python3 transitions/port_transition.py <input.md> [options]

    --id <slug>          transition id / folder name (default: from `<!-- name: x -->`
                         comment, else the input filename)
    --name "<label>"     picker label (default: Title Case of id)
    --accent "#RRGGBB"   card tint (default: derived from a color uniform, else #888888)
    --duration <ms>      defaultDurationMs (default: 800)
    --no-gif             skip GIF rendering
    --clips A B          clip images for the GIF (default: ../clip 1.jpeg, ../clip 2.jpeg)
    --force              overwrite an existing <id>/<id>.metal

CAVEATS (see README "The .metal file"): the GLSL→Metal translation covers the
gl-transitions subset. Shaders that call getFromColor/getToColor from a helper,
or use builtins with no Metal equivalent, will be flagged and may need a manual
touch-up. The compile step is the backstop — fix what it reports and re-run.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MANIFEST = os.path.join(HERE, "transitions.json")

warnings = []


def warn(msg):
    warnings.append(msg)


# ── Input extraction & markdown de-mangling ──────────────────────────────────
def extract_glsl(raw):
    """Pull GLSL out of the input. Prefer a fenced code block (markdown leaves
    its contents untouched); otherwise use the whole file minus HTML comments."""
    fence = re.search(r"```(?:glsl|c|cpp|frag)?\s*\n(.*?)```", raw, re.S | re.I)
    body = fence.group(1) if fence else raw
    if not fence:
        # Strip a leading `<!-- name: x -->` style HTML comment line.
        body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    return body


def demangle(src, fenced):
    """Undo markdown's mangling of operators. A fenced block is already clean, so
    only the backslash-escapes are reversed there; raw markdown also turns a
    standalone `*` into `_` (italic markers), which we heuristically restore."""
    src = src.replace(r"\*", "*").replace(r"\_", "_").replace(r"\.", ".")
    if not fenced:
        # ` _ ` and ` _= ` were almost certainly ` * ` / ` *= ` before markdown
        # italicised them. Identifier underscores (foo_bar) are never space-bounded.
        src = re.sub(r" _= ", " *= ", src)
        src = re.sub(r" _ ", " * ", src)
        if re.search(r"(^|\n)\s*_|_\s*($|\n)", src):
            warn("Input looks like rendered markdown (mangled operators). For "
                 "reliable ports, paste the GLSL inside a ```glsl code fence.")
    return src


# ── Uniform parsing → params mapping ──────────────────────────────────────────
COMPONENTS = {"float": 1, "int": 1, "bool": 1,
              "vec2": 2, "vec3": 3, "vec4": 4,
              "ivec2": 2, "ivec3": 3, "ivec4": 4}
SLOT = ["x", "y", "z", "w"]


def parse_uniforms(src):
    """Return (uniforms, defaults). Each uniform = (type, name, [slot_letters]).
    `defaults` is the flat params list parsed from `// = ...` comments."""
    uniforms = []
    defaults = []
    next_slot = 0
    for m in re.finditer(r"uniform\s+(\w+)\s+(\w+)\s*;([^\n]*)", src):
        gtype, name, rest = m.group(1), m.group(2), m.group(3)
        n = COMPONENTS.get(gtype)
        if n is None:
            warn("uniform '%s %s' has an unsupported type; map it onto params "
                 "manually." % (gtype, name))
            continue
        if next_slot + n > 4:
            warn("uniform '%s' overflows params (only 4 floats available)." % name)
        slots = [SLOT[next_slot + i] for i in range(n) if next_slot + i < 4]
        uniforms.append((gtype, name, slots))
        next_slot += n
        # Numbers from the `// = vec3(1.0, 0.5, 0.0)` default. The lookbehind keeps
        # the `3` in `vec3` (a type name) out of the parsed values.
        val = rest.split("=", 1)[1] if "=" in rest else ""
        nums = re.findall(r"(?<![A-Za-z_])-?\d*\.?\d+", val)
        vals = [float(x) for x in nums[:n]]
        vals += [0.0] * (n - len(vals))   # fill missing defaults with 0
        defaults += vals
    defaults = (defaults + [0.0, 0.0, 0.0, 0.0])[:4]
    return uniforms, defaults


def uniform_decls(uniforms):
    """Metal declarations that re-create each uniform from params, injected at the
    top of _trBody. e.g. `float3 burnColor = float3(params.x, params.y, params.z);`"""
    lines = []
    for gtype, name, slots in uniforms:
        mtype = translate_types(gtype)
        if len(slots) == 1:
            lines.append("    %s %s = params.%s;" % (mtype, name, slots[0]))
        else:
            args = ", ".join("params.%s" % s for s in slots)
            lines.append("    %s %s = %s(%s);" % (mtype, name, mtype, args))
    return lines


# ── GLSL → Metal source translation ───────────────────────────────────────────
TYPE_MAP = {
    "vec2": "float2", "vec3": "float3", "vec4": "float4",
    "ivec2": "int2", "ivec3": "int3", "ivec4": "int4",
    "bvec2": "bool2", "bvec3": "bool3", "bvec4": "bool4",
    "mat2": "float2x2", "mat3": "float3x3", "mat4": "float4x4",
}
# Builtins with a different Metal spelling.
FUNC_RENAME = {"inversesqrt": "rsqrt", "fract": "fract", "mod": "fmod"}


def translate_types(s):
    for g, m in TYPE_MAP.items():
        s = re.sub(r"\b%s\b" % g, m, s)
    return s


def reindent(code, base=0):
    """Normalise indentation by brace depth (4 spaces/level). The translated
    GLSL inherits the source's haphazard whitespace; this gives output that reads
    like the hand-written kernels without reflowing expressions the way
    clang-format would (which diverges from the template style)."""
    out = []
    depth = base
    for raw in code.split("\n"):
        line = raw.strip()
        if line == "":
            out.append("")
            continue
        if line.startswith("#"):            # preprocessor sits at column 0
            out.append(line)
            continue
        code_part = re.sub(r"//.*", "", line)   # ignore braces inside line comments
        shown = depth - 1 if line[0] == "}" else depth
        out.append("    " * max(base, shown) + line)
        depth += code_part.count("{") - code_part.count("}")
    return "\n".join(out)


def translate_builtins(s):
    # atan(y, x) -> atan2(y, x); single-arg atan(x) is left alone.
    s = re.sub(r"\batan\s*\(([^,()]*),", r"atan2(\1,", s)
    if re.search(r"\bmod\s*\(", s):
        warn("`mod()` was mapped to fmod(); GLSL mod differs from fmod for "
             "negative operands — verify if your shader relies on that.")
    for g, m in FUNC_RENAME.items():
        if g != m:
            s = re.sub(r"\b%s\s*\(" % g, m + "(", s)
    return s


def split_functions(src):
    """Split the GLSL into (helpers_source, transition_body). Brace-matches each
    top-level `type name(args){...}` so nested braces don't confuse it."""
    helpers = []
    transition_body = None
    i = 0
    n = len(src)
    func_re = re.compile(r"(\w+)\s+(\w+)\s*\(([^)]*)\)\s*\{")
    while i < n:
        m = func_re.search(src, i)
        if not m:
            break
        # match the balanced body starting at the opening brace
        depth = 0
        j = m.end() - 1
        while j < n:
            if src[j] == "{":
                depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        ret, name, args, inner = m.group(1), m.group(2), m.group(3), src[m.end():j]
        if name == "transition":
            transition_body = inner
        else:
            helpers.append((ret, name, args, inner))
        i = j + 1
    return helpers, transition_body


def translate_helper(ret, name, args, inner):
    """A non-transition GLSL function → a `static inline` Metal function."""
    args = re.sub(r"\b(in|out|inout)\b\s+", "", args)   # drop GLSL qualifiers
    args = translate_types(args)
    sig = "static inline %s %s(%s) {" % (translate_types(ret), name, args.strip())
    body = translate_builtins(translate_types(inner))
    if re.search(r"getFromColor|getToColor", inner):
        warn("helper '%s' samples getFromColor/getToColor; those macros need "
             "fromTex/toTex/_s in scope — pass them in manually." % name)
    return reindent(sig + "\n" + body.strip("\n") + "\n}", base=0)


def translate_transition(inner, uniforms):
    body = translate_builtins(translate_types(inner))
    decls = [d.strip() for d in uniform_decls(uniforms)]
    raw = "\n".join(decls)
    if decls:
        raw += "\n"
    return reindent(raw + body.strip("\n"), base=1)


# ── Metadata helpers ──────────────────────────────────────────────────────────
def title_case(slug):
    return " ".join(w.capitalize() for w in re.split(r"[_\-\s]+", slug) if w)


def derive_accent(uniforms, defaults):
    for gtype, name, slots in uniforms:
        if gtype == "vec3" and ("color" in name.lower()):
            r, g, b = (defaults[SLOT.index(s)] for s in slots[:3])
            return "#%02X%02X%02X" % (int(round(r * 255)),
                                      int(round(g * 255)), int(round(b * 255)))
    return None


def param_doc(uniforms):
    if not uniforms:
        return "no params"
    parts = []
    for _t, name, slots in uniforms:
        parts.append("%s = (%s)" % (name, ", ".join("params." + s for s in slots))
                     if len(slots) > 1 else "%s = params.%s" % (name, slots[0]))
    return "params: " + ", ".join(parts)


def author_of(raw):
    m = re.search(r"Author:\s*(.+)", raw)
    if not m:
        return None
    a = m.group(1).strip()
    return a.split("@")[0].rstrip(" <") if "@" in a else a


# ── Emit the wrapped kernel ────────────────────────────────────────────────────
def build_metal(tid, name, author, uniforms, helpers_src, trbody):
    by = (", by %s" % author) if author else ""
    sentence = ("%s (gl-transitions%s) — %s. Full wrapped kernel; the kernel "
                "name MUST match the descriptor's `kernel` field." % (
                    name, by, param_doc(uniforms)))
    head = "\n".join("// " + ln for ln in textwrap.wrap(sentence, width=76))
    helpers_block = ("\n\n" + helpers_src) if helpers_src.strip() else ""
    return '''#include <metal_stdlib>
using namespace metal;

{head}

struct TransitionUniforms {{
    float progress; float ratio; float width; float height;
    float4 params;
}};

// gl-transitions sample with a y-up uv (origin bottom-left). Metal textures are
// top-left origin, so these helpers flip v.
#define getFromColor(p) fromTex.sample(_s, float2((p).x, 1.0 - (p).y))
#define getToColor(p)   toTex.sample(_s, float2((p).x, 1.0 - (p).y)){helpers}

static inline float4 _trBody(
    float2 uv, float progress, float ratio, float4 params, float2 resolution,
    texture2d<float, access::sample> fromTex,
    texture2d<float, access::sample> toTex,
    sampler _s)
{{
{trbody}
}}

kernel void trx_{tid}(
    texture2d<float, access::sample> fromTex [[texture(0)]],
    texture2d<float, access::sample> toTex   [[texture(1)]],
    texture2d<float, access::write>  outTex  [[texture(2)]],
    constant TransitionUniforms&     u       [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{{
    uint w = outTex.get_width();
    uint h = outTex.get_height();
    if (gid.x >= w || gid.y >= h) {{ return; }}
    constexpr sampler _s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = float2((float(gid.x) + 0.5) / float(w),
                       1.0 - (float(gid.y) + 0.5) / float(h));
    float4 c = _trBody(uv, u.progress, u.ratio, u.params,
                       float2(float(w), float(h)), fromTex, toTex, _s);
    outTex.write(c, gid);
}}
'''.format(head=head, helpers=helpers_block, trbody=trbody, tid=tid)


# ── Manifest upsert ─────────────────────────────────────────────────────────────
BASE = "https://brytamegbor.github.io/video-editor/transitions"


def upsert_manifest(tid, name, defaults, accent, duration, has_params):
    with open(MANIFEST) as f:
        entries = json.load(f)
    entry = {
        "id": tid, "name": name, "kernel": "trx_" + tid,
        "category": "downloadable", "defaultDurationMs": duration,
    }
    if has_params:
        entry["params"] = [int(x) if x == int(x) else x for x in defaults]
    entry["accentHex"] = accent
    entry["gifUrl"] = "%s/%s/%s.gif" % (BASE, tid, tid)
    entry["metalUrl"] = "%s/%s/%s.metal" % (BASE, tid, tid)
    for i, e in enumerate(entries):
        if e.get("id") == tid:
            entries[i] = entry
            break
    else:
        entries.append(entry)
    with open(MANIFEST, "w") as f:
        json.dump(entries, f, indent=2)
        f.write("\n")


# ── Main ────────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Port a gl-transition to the Metal catalog.")
    ap.add_argument("input")
    ap.add_argument("--id")
    ap.add_argument("--name")
    ap.add_argument("--accent")
    ap.add_argument("--duration", type=int, default=800)
    ap.add_argument("--no-gif", action="store_true")
    ap.add_argument("--clips", nargs=2, metavar=("A", "B"))
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    with open(args.input) as f:
        raw = f.read()

    name_comment = re.search(r"name:\s*([\w\-]+)", raw)
    tid = (args.id or (name_comment.group(1) if name_comment else None)
           or os.path.splitext(os.path.basename(args.input))[0])
    tid = re.sub(r"[^a-z0-9_]+", "_", tid.lower()).strip("_")

    fenced = bool(re.search(r"```", raw))
    glsl = demangle(extract_glsl(raw), fenced)

    uniforms, defaults = parse_uniforms(glsl)
    glsl = re.sub(r"uniform\s+\w+\s+\w+\s*;[^\n]*\n?", "", glsl)  # strip uniform decls

    helpers, trans_inner = split_functions(glsl)
    if trans_inner is None:
        sys.exit("error: no `transition(...)` function found in %s" % args.input)

    # Reproduce #define lines (valid Metal) ahead of the helpers that use them.
    defines = "\n".join(re.findall(r"^[ \t]*#define[^\n]*", glsl, re.M))
    helper_src = "\n\n".join(translate_helper(*h) for h in helpers)
    helper_src = (defines + ("\n" if defines and helper_src else "") + helper_src).strip()

    trbody = translate_transition(trans_inner, uniforms)

    name = args.name or title_case(tid)
    accent = args.accent or derive_accent(uniforms, defaults) or "#888888"
    if not args.accent and accent == "#888888":
        warn("No --accent given and no color uniform to derive from; used "
             "#888888. Pass --accent \"#RRGGBB\" for a nicer card tint.")

    metal = build_metal(tid, name, author_of(raw), uniforms, helper_src, trbody)

    outdir = os.path.join(HERE, tid)
    outpath = os.path.join(outdir, tid + ".metal")
    if os.path.exists(outpath) and not args.force:
        sys.exit("error: %s exists (use --force to overwrite)" % outpath)
    os.makedirs(outdir, exist_ok=True)
    with open(outpath, "w") as f:
        f.write(metal)
    print("wrote %s" % os.path.relpath(outpath, REPO))

    # Compile gate — the honesty backstop.
    air = "/tmp/%s.air" % tid
    r = subprocess.run(["xcrun", "-sdk", "macosx", "metal", "-c", outpath, "-o", air],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("\n✗ Metal compile FAILED — the auto-translation needs a manual fix:\n",
              file=sys.stderr)
        print(r.stderr, file=sys.stderr)
        for w in warnings:
            print("  ! " + w, file=sys.stderr)
        sys.exit(1)
    print("✓ compiles (xcrun metal -c)")

    upsert_manifest(tid, name, defaults, accent, args.duration, bool(uniforms))
    print("✓ registered in transitions.json  (params=%s, accent=%s)" % (
        defaults if uniforms else "none", accent))

    if not args.no_gif:
        cmd = ["swift", os.path.join(HERE, "make_gifs.swift")]
        if args.clips:
            cmd += list(args.clips)
        elif True:
            cmd += [os.path.join(REPO, "clip 1.jpeg"), os.path.join(REPO, "clip 2.jpeg")]
        cmd.append(tid)
        print("\nrendering preview GIF…")
        g = subprocess.run(cmd)
        if g.returncode != 0:
            warn("GIF render failed; run make_gifs.swift manually.")

    if warnings:
        print("\nReview notes:")
        for w in warnings:
            print("  ! " + w)
    print("\nDone. Review the .metal and the GIF, then commit. (If this is a new "
          "transition you also want offline, mirror it into the app's "
          "TransitionCatalog.bundledSamples — see README.)")


if __name__ == "__main__":
    main()
