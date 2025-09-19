import Foundation
import CoreGraphics

public struct WebPOptions {
  public var useExtendedFormat: Bool

  public init(useExtendedFormat: Bool = false) {
    self.useExtendedFormat = useExtendedFormat
  }
}

public struct WebPAnimation {
  public var images: [CGImage]
  public var durations: [UInt]
  public var disposals: [UInt]
  public var loopCount: UInt16
  public var backgroundColor: UInt32

  public init(
    images: [CGImage],
    durations: [UInt],
    disposals: [UInt],
    loopCount: UInt16 = 0,
    backgroundColor: UInt32 = 0
  ) {
    self.images = images
    self.durations = durations
    self.disposals = disposals
    self.loopCount = loopCount
    self.backgroundColor = backgroundColor
  }
}

public enum WebPEncoder {
  public static func encode(image: CGImage, options: WebPOptions? = nil) throws -> Data {
    let (stream, hasAlpha) = try writeBitStream(image)

    var payload = Data()

    if options?.useExtendedFormat == true {
      writeChunkVP8X(&payload, width: image.width, height: image.height, flagAlpha: hasAlpha, flagAni: false)
    }

    payload.appendFourCC("VP8L")
    payload.appendUInt32LE(UInt32(stream.count))
    payload.append(stream)

    var out = Data()
    out.appendFourCC("RIFF")
    out.appendUInt32LE(UInt32(4 + payload.count))
    out.appendFourCC("WEBP")
    out.append(payload)

    return out
  }

  public static func encodeAll(_ ani: WebPAnimation, options: WebPOptions? = nil) throws -> Data {
    let (framesData, hasAlpha) = try writeFrames(ani)

    var maxW = 0
    var maxH = 0
    for img in ani.images {
      maxW = max(maxW, img.width)
      maxH = max(maxH, img.height)
    }

    var payload = Data()

    writeChunkVP8X(&payload, width: maxW, height: maxH, flagAlpha: hasAlpha, flagAni: true)

    payload.append(contentsOf: "ANIM".utf8)
    payload.appendUInt32LE(UInt32(6))
    payload.appendUInt32LE(UInt32(ani.backgroundColor))
    payload.appendUInt32LE(UInt16(ani.loopCount))

    payload.append(framesData)

    var riff = Data()
    riff.append(contentsOf: "RIFF".utf8)
    riff.appendUInt32LE(UInt32(4 + payload.count))
    riff.append(contentsOf: "WEBP".utf8)
    riff.append(payload)

    return riff
  }
}

func writeChunkVP8X(_ buf: inout Data, width: Int, height: Int, flagAlpha: Bool, flagAni: Bool) {
  buf.appendFourCC("VP8X")
  buf.appendUInt32LE(UInt32(10))

  var flags: UInt8 = 0
  if flagAni {
    flags |= 1 << 1
  }
  if flagAlpha {
    flags |= 1 << 4
  }
  buf.append(contentsOf: [flags, 0x00, 0x00, 0x00]) // 3 bytes reserved

  let dx = max(0, width - 1)
  let dy = max(0, height - 1)

  buf.append(contentsOf: [
    UInt8(dx & 0xff), UInt8((dx >> 8) & 0xff), UInt8((dx >> 16) & 0xff),
    UInt8(dy & 0xff), UInt8((dy >> 8) & 0xff), UInt8((dy >> 16) & 0xff)
  ])
}

func writeFrames(_ ani: WebPAnimation) throws -> (Data, Bool) {
  guard !ani.images.isEmpty else {
    throw WebPEncodeError.noImages
  }
  guard ani.images.count == ani.durations.count else {
    throw WebPEncodeError.durationsMismatch
  }
  guard ani.images.count == ani.disposals.count else {
    throw WebPEncodeError.disposalsMismatch
  }

  var durations = ani.durations
  var disposals = ani.disposals
  for i in 0..<ani.images.count {
    durations[i] = min(durations[i], UInt((1 << 24) - 1))
    disposals[i] = min(disposals[i], 1)
  }

  var buf = Data()
  var hasAlpha = false

  for i in 0..<ani.images.count {
    let img = ani.images[i]

    let (stream, alpha) = try writeBitStream(img)
    hasAlpha = hasAlpha || alpha

    var writer = BitWriter()
    writer.writeBytes(Array("ANMF".utf8))

    let payloadLen = 16 + 8 + stream.count
    writer.writeBits(UInt64(payloadLen), 32)

    let xOffDiv2: Int = 0
    let yOffDiv2: Int = 0
    writer.writeBits(UInt64(xOffDiv2), 24)
    writer.writeBits(UInt64(yOffDiv2), 24)

    writer.writeBits(UInt64(img.width - 1), 24)
    writer.writeBits(UInt64(img.height - 1), 24)

    writer.writeBits(UInt64(durations[i]), 24)
    writer.writeBits(UInt64(disposals[i]), 1)
    writer.writeBits(0, 1)
    writer.writeBits(0, 6)

    writer.writeBytes(Array("VP8L".utf8))
    writer.writeBits(UInt64(stream.count), 32)

    writer.buffer.append(contentsOf: stream)

    buf.append(contentsOf: writer.buffer)
  }

  return (buf, hasAlpha)
}

private extension Data {
  mutating func appendFourCC(_ fourcc: String) {
    precondition(fourcc.utf8.count == 4, "FourCC must be 4 ASCII bytes")
    self.append(contentsOf: fourcc.utf8)
  }

  mutating func appendUInt32LE<T: FixedWidthInteger>(_ value: T) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { rawBuf in
      guard let base = rawBuf.baseAddress else { return }
      self.append(base.assumingMemoryBound(to: UInt8.self), count: rawBuf.count)
    }
  }
}

func writeBitStream(_ img: CGImage) throws -> (data: Data, hasAlpha: Bool) {
  let width  = img.width
  let height = img.height

  guard width >= 1, height >= 1 else {
    throw WebPEncodeError.invalidImageSize
  }
  let maxDim = 1 << 14
  guard width <= maxDim, height <= maxDim else {
    throw WebPEncodeError.invalidImageSize
  }

  let isIndexed = (img.colorSpace?.model == .indexed)

  let pixels = try flatten(img)
  let opaque = pixels.allSatisfy { $0.a == 255 }
  let hasAlpha = !opaque

  var writer = BitWriter()

  writeBitStreamHeader(&writer, width: width, height: height, hasAlpha: hasAlpha)

  var transforms = [Bool](repeating: false, count: 4)
  transforms[0] = !isIndexed
  transforms[1] = false
  transforms[2] = !isIndexed
  transforms[3] = isIndexed

  try writeBitStreamData(&writer, image: img, colorCacheBits: 4, transforms: transforms)

  writer.alignByte()

  if writer.buffer.count % 2 != 0 {
    writer.buffer.append(0)
  }

  return (Data(writer.buffer), hasAlpha)
}

func writeBitStreamHeader(_ writer: inout BitWriter, width: Int, height: Int, hasAlpha: Bool) {
  writer.writeBits(0x2f, 8)

  writer.writeBits(UInt64(width - 1), 14)
  writer.writeBits(UInt64(height - 1), 14)

  writer.writeBits(hasAlpha ? 1 : 0, 1)
  writer.writeBits(0, 3)
}

func writeBitStreamData(
  _ writer: inout BitWriter,
  image: CGImage,
  colorCacheBits: Int,
  transforms: [Bool]
) throws {
  var pixels = try flatten(image)
  var width = image.width
  let height = image.height

  if transforms.count > TransformType.colorIndexing.rawValue, transforms[Int(TransformType.colorIndexing.rawValue)] {
    writer.writeBits(1, 1)
    writer.writeBits(3, 2)

    let (palette, packedWidth) = try applyPaletteTransform(pixels: &pixels, width: width, height: height)
    width = packedWidth

    writer.writeBits(UInt64(palette.count - 1), 8)

    writeImageData(&writer, pixels: palette, width: palette.count, height: 1, isRecursive: false, colorCacheBits: colorCacheBits)
  }

  if transforms.count > TransformType.subtractGreen.rawValue, transforms[Int(TransformType.subtractGreen.rawValue)] {
    writer.writeBits(1, 1)
    writer.writeBits(2, 2)

    applySubtractGreenTransform(pixels: &pixels)
  }

  if transforms.count > TransformType.crossColor.rawValue, transforms[Int(TransformType.crossColor.rawValue)] {
    writer.writeBits(1, 1)
    writer.writeBits(1, 2)

    let (bits, bw, bh, blocks) = applyColorTransform(pixels: &pixels, width: width, height: height)

    writer.writeBits(UInt64(bits - 2), 3)
    writeImageData(&writer, pixels: blocks, width: bw, height: bh, isRecursive: false, colorCacheBits: colorCacheBits)
  }

  if transforms.count > TransformType.predictor.rawValue, transforms[Int(TransformType.predictor.rawValue)] {
    writer.writeBits(1, 1) 
    writer.writeBits(0, 2) 

    let (bits, bw, bh, blocks) = applyPredictTransform(pixels: &pixels, width: width, height: height)

    writer.writeBits(UInt64(bits - 2), 3)
    writeImageData(&writer, pixels: blocks, width: bw, height: bh, isRecursive: false, colorCacheBits: colorCacheBits)
  }

  writer.writeBits(0, 1)

  writeImageData(&writer, pixels: pixels, width: width, height: height, isRecursive: true, colorCacheBits: colorCacheBits)
}

func writeImageData(
  _ writer: inout BitWriter,
  pixels: [NRGBA],
  width: Int,
  height: Int,
  isRecursive: Bool,
  colorCacheBits: Int
) {
  if colorCacheBits > 0 {
    writer.writeBits(1, 1)
    writer.writeBits(UInt64(colorCacheBits), 4)
  } else {
    writer.writeBits(0, 1)
  }

  if isRecursive {
    writer.writeBits(0, 1)
  }

  let encoded = encodeImageData(pixels: pixels, width: width, height: height, colorCacheBits: colorCacheBits)
  let histos = computeHistograms(encoded, colorCacheBits: colorCacheBits)

  var codes: [[HuffmanCode]] = []
  for i in 0..<5 {
    let c = buildHuffmanCodes(histos[i], maxDepth: 15)
    codes.append(c)
    writeHuffmanCodes(&writer, c)
  }

  var i = 0
  while i < encoded.count {
    let s0 = encoded[i]
    writer.writeCode(codes[0][s0])

    if s0 < 256 {
      precondition(i + 3 < encoded.count)
      writer.writeCode(codes[1][encoded[i + 1]])
      writer.writeCode(codes[2][encoded[i + 2]])
      writer.writeCode(codes[3][encoded[i + 3]])
      i += 4
    } else if s0 < 256 + 24 {
      precondition(i + 3 < encoded.count)
      var cnt = prefixEncodeBits(s0 - 256)
      writer.writeBits(UInt64(encoded[i + 1]), cnt)

      writer.writeCode(codes[4][encoded[i + 2]])

      cnt = prefixEncodeBits(encoded[i + 2])
      writer.writeBits(UInt64(encoded[i + 3]), cnt)

      i += 4
    } else {
      i += 1
    }
  }
}

func encodeImageData(pixels: [NRGBA], width: Int, height: Int, colorCacheBits: Int) -> [Int] {
  var head = Array(repeating: 0, count: 1 << 14)
  var prev = Array(repeating: 0, count: pixels.count)
  let cacheSize = 1 << colorCacheBits
  var cache = Array(repeating: NRGBA(r: 0, g: 0, b: 0, a: 0), count: cacheSize)

  var encoded = Array(repeating: 0, count: pixels.count * 4)
  var count = 0

  let distances: [Int] = [
     96,  73,  55,  39,  23,  13,   5,   1, 255, 255, 255, 255, 255, 255, 255, 255,
    101,  78,  58,  42,  26,  16,   8,   2,   0,   3,   9,  17,  27,  43,  59,  79,
    102,  86,  62,  46,  32,  20,  10,   6,   4,   7,  11,  21,  33,  47,  63,  87,
    105,  90,  70,  52,  37,  28,  18,  14,  12,  15,  19,  29,  38,  53,  71,  91,
    110,  99,  82,  66,  48,  35,  30,  24,  22,  25,  31,  36,  49,  67,  83, 100,
    115, 108,  94,  76,  64,  50,  44,  40,  34,  41,  45,  51,  65,  77,  95, 109,
    118, 113, 103,  92,  80,  68,  60,  56,  54,  57,  61,  69,  81,  93, 104, 114,
    119, 116, 111, 106,  97,  88,  84,  74,  72,  75,  85,  89,  98, 107, 112, 117,
  ]

  var i = 0
  while i < pixels.count {
    if i + 2 < pixels.count {
      var h0 = hash(pixels[i + 0], shifts: 14)
      let h1 = hash(pixels[i + 1], shifts: 14)
      let h2 = hash(pixels[i + 2], shifts: 14)
      h0 ^= h1 &* 0x9E3779B9
      h0 ^= h2 &* 0x85EBCA6B
      let hIdx = Int(h0 & UInt32((1 << 14) - 1))

      var cur = head[hIdx] - 1
      prev[i] = head[hIdx]
      head[hIdx] = i + 1

      var bestDist = 0
      var streak = 0

      var probe = 0
      while probe < 8 {
        if cur == -1 || (i - cur) >= ((1 << 20) - 120) {
          break
        }

        var l = 0
        while (i + l) < pixels.count, (cur + l) < pixels.count, l < 4096 {
          if pixels[i + l] != pixels[cur + l] {
            break
          }
          l += 1
        }

        if l > streak {
          streak = l
          bestDist = i - cur
        }

        cur = prev[cur] - 1
        probe += 1
      }

      if streak >= 3 {
        if colorCacheBits > 0 {
          let mask = cacheSize - 1
          var j = 0
          while j < streak {
            let hh = Int(hash(pixels[i + j], shifts: colorCacheBits)) & mask
            cache[hh] = pixels[i + j]
            j += 1
          }
        }

        let y = bestDist / width
        let x = bestDist - y * width
        var code = bestDist + 120
        if x <= 8 && y < 8 {
          code = distances[y * 16 + (8 - x)] + 1
        } else if x > (width - 8) && y < 7 {
          code = distances[(y + 1) * 16 + 8 + (width - x)] + 1
        }

        var symbol: Int
        var extra: Int
        (symbol, extra) = prefixEncodeCode(streak)
        encoded[count + 0] = symbol + 256
        encoded[count + 1] = extra

        (symbol, extra) = prefixEncodeCode(code)
        encoded[count + 2] = symbol
        encoded[count + 3] = extra
        count += 4

        i += streak
        continue
      }
    }

    let p = pixels[i]
    if colorCacheBits > 0 {
      let mask = cacheSize - 1
      let hh = Int(hash(p, shifts: colorCacheBits)) & mask
      if i > 0 && cache[hh] == p {
        encoded[count] = hh + 256 + 24
        count += 1
        i += 1
        continue
      }
      cache[hh] = p
    }

    encoded[count + 0] = Int(p.g)
    encoded[count + 1] = Int(p.r)
    encoded[count + 2] = Int(p.b)
    encoded[count + 3] = Int(p.a)
    count += 4

    i += 1
  }

  return Array(encoded[..<count])
}

@inline(__always)
func prefixEncodeCode(_ n: Int) -> (Int, Int) {
  if n <= 5 {
    return (max(0, n - 1), 0)
  }
  var shift = 0
  var rem = n - 1
  while rem > 3 {
    rem >>= 1
    shift += 1
  }
  if rem == 2 {
    return (2 + 2 * shift, n - (2 << shift) - 1)
  }
  return (3 + 2 * shift, n - (3 << shift) - 1)
}

@inline(__always)
func prefixEncodeBits(_ prefix: Int) -> Int {
  if prefix < 4 {
    return 0
  }
  return (prefix - 2) >> 1
}

@inline(__always)
func hash(_ c: NRGBA, shifts: Int) -> UInt32 {
  let x = (UInt32(c.a) << 24) | (UInt32(c.r) << 16) | (UInt32(c.g) << 8) | UInt32(c.b)
  let s = min(shifts, 32)
  return (x &* 0x1e35a7bd) >> (32 - s)
}

func computeHistograms(_ pixels: [Int], colorCacheBits: Int) -> [[Int]] {
  let c: Int
  if colorCacheBits > 0 {
    c = 1 << colorCacheBits
  } else {
    c = 0
  }

  var histos: [[Int]] = [
    Array(repeating: 0, count: 256 + 24 + c),
    Array(repeating: 0, count: 256),
    Array(repeating: 0, count: 256),
    Array(repeating: 0, count: 256),
    Array(repeating: 0, count: 40),
  ]

  var i = 0
  while i < pixels.count {
    let v0 = pixels[i]
    histos[0][v0] += 1

    if v0 < 256 {
      if i + 3 < pixels.count {
        histos[1][pixels[i + 1]] += 1
        histos[2][pixels[i + 2]] += 1
        histos[3][pixels[i + 3]] += 1
      }
      i += 4
    } else if v0 < 256 + 24 {
      if i + 3 < pixels.count {
        histos[4][pixels[i + 2]] += 1
      }
      i += 4
    } else {
      i += 1
    }
  }

  return histos
}

public func flatten(_ image: CGImage) throws -> [NRGBA] {
  let w = image.width
  let h = image.height
  guard w > 0, h > 0 else {
    throw FlattenError.unsupportedImage
  }

  let bytesPerPixel = 4
  let bytesPerRow = w * bytesPerPixel
  let countBytes = h * bytesPerRow

  var raw = [UInt8](repeating: 0, count: countBytes)

  let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

  raw.withUnsafeMutableBytes { (ptr) in
    if let ctx = CGContext(
      data: ptr.baseAddress,
      width: w,
      height: h,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: cs,
      bitmapInfo: bitmapInfo
    ) {
      ctx.interpolationQuality = .none
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
  }

  var out = [NRGBA](repeating: NRGBA(), count: w * h)
  raw.withUnsafeBytes { (src) in
    let p = src.bindMemory(to: UInt8.self).baseAddress!
    for y in 0..<h {
      let row = p.advanced(by: y * bytesPerRow)
      for x in 0..<w {
        let px = row.advanced(by: x * 4)
        let r = px[0], g = px[1], b = px[2], a = px[3]
        if a == 0 {
          out[y * w + x] = NRGBA(r: 0, g: 0, b: 0, a: 0)
        } else {
          let rr = UInt8(min(255, Int(r) * 255 / Int(a)))
          let gg = UInt8(min(255, Int(g) * 255 / Int(a)))
          let bb = UInt8(min(255, Int(b) * 255 / Int(a)))
          out[y * w + x] = NRGBA(r: rr, g: gg, b: bb, a: a)
        }
      }
    }
  }

  return out
}
