# Downloadable transitions — hosting layout

This folder is the **downloadable shader-transition catalog** for the native iOS
editor. Upload it to the static host so its files resolve under:

```
https://brytamegbor.github.io/video-editor/transitions/
```

That base must match `TransitionCatalog.defaultManifestURL` /
`TransitionCatalog.assetBaseURL` in
`ios/Runner/Editor/Services/TransitionDownloadService.swift`. If you move it,
update those two constants.

## Layout

```
test/
├── transitions.json                         ← the manifest (array of descriptors)
├── <id>/<id>.metal                          ← full wrapped Metal kernel
└── <id>/<id>.gif                            ← looping square preview (add these)
```

One folder per transition, named by its `id`. Inside, two files named by the
same `id`: `<id>.metal` (required) and `<id>.gif` (preview).

## Porting a new transition (the easy way)

`port_transition.py` automates the whole flow below — paste a gl-transitions
GLSL snippet into a file and run:

```sh
python3 transitions/port_transition.py new-transition.md --accent "#FF6B2C"
```

It translates the GLSL to a wrapped Metal kernel (`<id>/<id>.metal`), packs the
shader's `uniform`s onto `params.x…w`, upserts the manifest entry (default
`params` come from the uniforms' `// = …` defaults), **compile-checks** with
`xcrun metal -c`, and renders the preview GIF via `make_gifs.swift`. The `id`
defaults to the `<!-- name: x -->` comment (or the filename); override anything
with `--id`, `--name`, `--accent`, `--duration`, `--clips A B`, `--no-gif`,
`--force`.

It covers the common gl-transitions subset. Two things to know:

- **Paste the GLSL inside a <code>```glsl</code> fence** if the source is
  markdown — otherwise markdown mangles `*` operators (the script de-mangles
  heuristically and warns, but a fence is reliable).
- The GLSL→Metal translation can't express *every* shader (builtins like `mod`
  semantics or a scalar `distance()` have no direct Metal equivalent — see the
  hand-written workaround in `cube/cube.metal`). When that happens the **compile
  step fails with a line number**; fix that spot by hand and re-run with
  `--force`. Always eyeball the generated `.metal` and GIF before committing.

The sections below document what the script produces, for manual ports or fixups.

## Manifest entry (one `EditorTransitionDescriptor`)

| field               | required | notes                                                                   |
| ------------------- | -------- | ----------------------------------------------------------------------- |
| `id`                | ✅       | folder name + cache key; filesystem-safe                                |
| `name`              | ✅       | picker label                                                            |
| `kernel`            | ✅       | **must equal** the `kernel void <name>` in the `.metal`; use `trx_<id>` |
| `metalUrl`          | ✅       | absolute URL of the `.metal`                                            |
| `gifUrl`            | ⬜       | absolute URL of the preview GIF; falls back to a tinted tile            |
| `category`          | ⬜       | defaults `"downloadable"`                                               |
| `defaultDurationMs` | ⬜       | suggested duration when first applied                                   |
| `params`            | ⬜       | up to 4 floats → kernel `params.x…w`                                    |
| `accentHex`         | ⬜       | `"#RRGGBB"` card tint + the placeholder/fallback color                  |
| `jsonUrl`           | ⬜       | optional; ignored once installed                                        |

The client ignores unknown keys, so extra fields are harmless — but only the
columns above are read.

## The `.metal` file

It is the **whole** kernel (preamble + `TransitionUniforms` struct +
`getFromColor`/`getToColor` macros + `kernel void trx_<id>(…)`), not just the
gl-transition body — the app compiles the entire file and looks up `kernel`.
It's the output of `TransitionMetal.kernelSource(name:body:)`; the gl-transition
`transition(uv)` body drops in almost verbatim with custom uniforms mapped onto
`params.x…w`. Coordinates are **y-up** (uv.y = 1 at the top).

Validate before uploading:

```sh
xcrun -sdk macosx metal -c <id>/<id>.metal -o /tmp/<id>.air
```

## The `.gif` preview

- Square (1:1), looping, ideally ~480×480, kept small (the current built-in
  previews are ~50–100 KB).
- Show the transition over two distinct clips so the motion reads at thumbnail
  size, matching the built-in cards under `ios/Runner/Resources/transitions/`.
- Name it `<id>.gif` and place it at `<id>/<id>.gif`. Missing GIFs are fine —
  the card shows the `accentHex` placeholder until the file exists.

## Keep in sync with the offline fallback

These four (`crosswarp`, `directional_warp`, `wind`, `ripple`) mirror
`TransitionCatalog.bundledSamples` in the app, which is the fallback when this
manifest is unreachable. When you **add** a transition here, also add it to
`bundledSamples` (or accept that it's online-only); when you change a sample's
id / kernel / params, change it in both places.
