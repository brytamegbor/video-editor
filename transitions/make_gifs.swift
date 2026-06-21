#!/usr/bin/env swift
//
// make_gifs.swift — render looping preview GIFs for the downloadable
// transition catalog by running the *actual* Metal kernels on the GPU.
//
// For every transition listed in `transitions.json` it loads <id>/<id>.metal,
// compiles it at runtime, runs it over progress 0→1 on two clips, and writes a
// square looping preview to <id>/<id>.gif — the layout the README asks for.
//
// Usage (run from anywhere):
//
//     swift transitions/make_gifs.swift [clipA clipB [id ...]]
//
//   clipA / clipB  two source images (default: ../clip 1.jpeg, ../clip 2.jpeg)
//   id ...         optional subset of transition ids; default is all of them
//
// No third-party tools required — Metal + ImageIO ship with macOS.

import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ── Tunables ─────────────────────────────────────────────────────────────────
// Tuned for small files (~README's 50–100 KB built-ins). GIF size is driven by
// resolution × ramp-frame count; the holds are near-free because identical
// frames compress to almost nothing under LZW.
let SIZE        = 220      // square preview side in px (README: ~480, kept small)
let START_HOLD  = 2        // frames holding clip A before the transition
let RAMP        = 14       // frames of actual transition (eased 0→1)
let END_HOLD    = 2        // frames holding clip B after the transition
let FRAME_DELAY = 0.07     // seconds per frame (~14fps)

// ── Paths ────────────────────────────────────────────────────────────────────
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let manifestURL = scriptDir.appendingPathComponent("transitions.json")

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
let clipAPath = args.count >= 1 ? args[0]
    : scriptDir.deletingLastPathComponent().appendingPathComponent("clip 1.jpeg").path
let clipBPath = args.count >= 2 ? args[1]
    : scriptDir.deletingLastPathComponent().appendingPathComponent("clip 2.jpeg").path
let onlyIds: Set<String>? = args.count > 2 ? Set(args[2...]) : nil

// ── Image loading: EXIF-correct, center-cropped square, top-left origin ──────
func loadSquareRGBA(_ path: String, _ size: Int) -> [UInt8] {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { fail("cannot open image: \(path)") }
    // Thumbnail decode applies the EXIF orientation transform for us and trims
    // the giant phone-camera originals down before we crop.
    let thumbOpts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: size * 2,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary)
    else { fail("cannot decode image: \(path)") }

    let side = min(cg.width, cg.height)
    let crop = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2,
                      width: side, height: side)
    guard let cropped = cg.cropping(to: crop) else { fail("crop failed: \(path)") }

    var data = [UInt8](repeating: 0, count: size * size * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &data, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: size * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("bitmap context failed") }
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
    return data
}

// ── Metal setup ──────────────────────────────────────────────────────────────
guard let device = MTLCreateSystemDefaultDevice() else { fail("no Metal device") }
guard let queue = device.makeCommandQueue() else { fail("no command queue") }

func makeInputTexture(_ rgba: [UInt8], _ size: Int) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
    d.usage = [.shaderRead]
    d.storageMode = .shared
    guard let tex = device.makeTexture(descriptor: d) else { fail("input texture") }
    rgba.withUnsafeBytes {
        tex.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: size * 4)
    }
    return tex
}

func makeOutputTexture(_ size: Int) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
    d.usage = [.shaderWrite, .shaderRead]
    d.storageMode = .shared
    guard let tex = device.makeTexture(descriptor: d) else { fail("output texture") }
    return tex
}

// ── Frame schedule: hold A, eased transition, hold B; loops forever ──────────
func progressSchedule() -> [Float] {
    var p = [Float](repeating: 0, count: START_HOLD)
    for i in 1...RAMP {
        let t = Float(i) / Float(RAMP + 1)
        p.append(t * t * (3 - 2 * t))   // smoothstep ease-in-out
    }
    p.append(contentsOf: [Float](repeating: 1, count: END_HOLD))
    return p
}

func cgImage(fromRGBA data: [UInt8], _ size: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let provider = CGDataProvider(data: Data(data) as CFData)!
    return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: size * 4, space: cs,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

// ── Render one transition → GIF ──────────────────────────────────────────────
func renderGIF(id: String, kernel: String, params: [Float],
               fromTex: MTLTexture, toTex: MTLTexture) {
    let metalURL = scriptDir.appendingPathComponent("\(id)/\(id).metal")
    guard let source = try? String(contentsOf: metalURL, encoding: .utf8) else {
        fail("missing \(metalURL.path)")
    }
    let library: MTLLibrary
    do { library = try device.makeLibrary(source: source, options: nil) }
    catch { fail("\(id): compile failed: \(error)") }
    guard let fn = library.makeFunction(name: kernel) else {
        fail("\(id): kernel '\(kernel)' not found in \(id).metal")
    }
    let pipeline: MTLComputePipelineState
    do { pipeline = try device.makeComputePipelineState(function: fn) }
    catch { fail("\(id): pipeline failed: \(error)") }

    let outTex = makeOutputTexture(SIZE)
    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let tgCount = MTLSize(width: (SIZE + 15) / 16, height: (SIZE + 15) / 16, depth: 1)

    var p4 = params
    while p4.count < 4 { p4.append(0) }

    var frames: [CGImage] = []
    for progress in progressSchedule() {
        // TransitionUniforms: float progress,ratio,width,height; float4 params;
        // float4 is 16-byte aligned, so 8 contiguous floats map exactly (32B).
        var u: [Float] = [progress, 1.0, Float(SIZE), Float(SIZE),
                          p4[0], p4[1], p4[2], p4[3]]

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeComputeCommandEncoder()!
        enc.setComputePipelineState(pipeline)
        enc.setTexture(fromTex, index: 0)
        enc.setTexture(toTex, index: 1)
        enc.setTexture(outTex, index: 2)
        enc.setBytes(&u, length: MemoryLayout<Float>.stride * 8, index: 0)
        enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        var out = [UInt8](repeating: 0, count: SIZE * SIZE * 4)
        out.withUnsafeMutableBytes {
            outTex.getBytes($0.baseAddress!, bytesPerRow: SIZE * 4,
                            from: MTLRegionMake2D(0, 0, SIZE, SIZE), mipmapLevel: 0)
        }
        frames.append(cgImage(fromRGBA: out, SIZE))
    }

    let gifURL = scriptDir.appendingPathComponent("\(id)/\(id).gif")
    guard let dest = CGImageDestinationCreateWithURL(
        gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
    else { fail("\(id): cannot create gif destination") }
    let gifProps = [kCGImagePropertyGIFDictionary:
                    [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary  // 0 = forever
    CGImageDestinationSetProperties(dest, gifProps)
    let frameProps = [kCGImagePropertyGIFDictionary:
                      [kCGImagePropertyGIFDelayTime: FRAME_DELAY,
                       kCGImagePropertyGIFUnclampedDelayTime: FRAME_DELAY]] as CFDictionary
    for img in frames { CGImageDestinationAddImage(dest, img, frameProps) }
    guard CGImageDestinationFinalize(dest) else { fail("\(id): gif finalize failed") }

    let kb = (try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Int)
        .flatMap { $0 }.map { Double($0) / 1024 } ?? 0
    print(String(format: "  ✓ %@  (%d frames, %.0f KB)  → %@",
                 id, frames.count, kb, "\(id)/\(id).gif"))
}

// ── Drive it from the manifest ───────────────────────────────────────────────
guard let manifestData = try? Data(contentsOf: manifestURL),
      let entries = (try? JSONSerialization.jsonObject(with: manifestData)) as? [[String: Any]]
else { fail("cannot read \(manifestURL.path)") }

print("clip A: \(clipAPath)")
print("clip B: \(clipBPath)")
let fromTex = makeInputTexture(loadSquareRGBA(clipAPath, SIZE), SIZE)
let toTex   = makeInputTexture(loadSquareRGBA(clipBPath, SIZE), SIZE)
print("rendering \(SIZE)×\(SIZE) previews…")

for entry in entries {
    guard let id = entry["id"] as? String,
          let kernel = entry["kernel"] as? String else { continue }
    if let only = onlyIds, !only.contains(id) { continue }
    let params = (entry["params"] as? [NSNumber])?.map { $0.floatValue } ?? []
    renderGIF(id: id, kernel: kernel, params: params, fromTex: fromTex, toTex: toTex)
}
print("done.")
