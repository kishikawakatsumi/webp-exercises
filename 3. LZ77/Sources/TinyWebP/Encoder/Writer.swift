import Foundation
import CoreGraphics

public enum WebPEncoder {
  public static func encode(image: CGImage) throws -> Data {
    let (stream, _) = try writeBitStream(image)

    var payload = Data()

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
}

private extension Data {
  mutating func appendFourCC(_ fourcc: String) {
    precondition(fourcc.utf8.count == 4, "FourCC must be 4 ASCII bytes")
    self.append(contentsOf: fourcc.utf8)
  }

  mutating func appendUInt32LE<T: FixedWidthInteger>(_ value: T) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { rawBuf in
      guard let base = rawBuf.baseAddress else {
        return
      }
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

  let pixels = try flatten(img)
  let opaque = pixels.allSatisfy { $0.a == 255 }
  let hasAlpha = !opaque

  var bw = BitWriter()

  writeBitStreamHeader(&bw, width: width, height: height, hasAlpha: hasAlpha)
  try writeBitStreamData(&bw, image: img)

  bw.alignByte()

  if bw.buffer.count % 2 != 0 {
    bw.buffer.append(0)
  }

  return (Data(bw.buffer), hasAlpha)
}

func writeBitStreamHeader(_ writer: inout BitWriter, width: Int, height: Int, hasAlpha: Bool) {
  writer.writeBits(0x2f, 8)

  writer.writeBits(UInt64(width - 1), 14)
  writer.writeBits(UInt64(height - 1), 14)

  writer.writeBits(hasAlpha ? 1 : 0, 1)
  writer.writeBits(0, 3)
}

func writeBitStreamData(_ writer: inout BitWriter, image: CGImage) throws {
  let pixels = try flatten(image)
  let width = image.width
  let height = image.height

  writer.writeBits(0, 1)

  writeImageData(&writer, pixels: pixels, width: width, height: height, isRecursive: true)
}

func writeImageData(
  _ writer: inout BitWriter,
  pixels: [NRGBA],
  width: Int,
  height: Int,
  isRecursive: Bool
) {
  writer.writeBits(0, 1)

  if isRecursive {
    writer.writeBits(0, 1)
  }

  let encoded = encodeImageData(pixels: pixels, width: width, height: height)
  let histos = computeHistograms(encoded)
  debugDumpHistogramsGRBAD(histos, colorCacheBits: 0, topN: 24)
  
  var codes: [[HuffmanCode]] = []
  for i in 0..<5 {
    // WebP specs requires Huffman codes with maximum depth of 15
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
    }
  }
}

func encodeImageData(
  pixels: [NRGBA],
  width: Int,
  height: Int
) -> [Int] {
  var head = Array(repeating: 0, count: 1 << 14)
  var prev = Array(repeating: 0, count: pixels.count)

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
      var bestLen  = 0

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

        if l > bestLen {
          bestLen  = l
          bestDist = i - cur
        }

        cur = prev[cur] - 1
        probe += 1
      }

      if bestLen >= 3 {
        let y = bestDist / width
        let x = bestDist - y * width
        var distCode = bestDist + 120
        if x <= 8 && y < 8 {
          distCode = distances[y * 16 + (8 - x)] + 1
        } else if x > (width - 8) && y < 7 {
          distCode = distances[(y + 1) * 16 + 8 + (width - x)] + 1
        }

        var sym: Int, extra: Int
        (sym, extra) = prefixEncodeCode(bestLen)
        encoded[count + 0] = sym + 256
        encoded[count + 1] = extra

        (sym, extra) = prefixEncodeCode(distCode)
        encoded[count + 2] = sym
        encoded[count + 3] = extra
        count += 4

        i += bestLen
        continue
      }
    }

    let p = pixels[i]
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

func computeHistograms(_ pixels: [Int]) -> [[Int]] {
  var histos: [[Int]] = [
    Array(repeating: 0, count: 256 + 24),
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
    }
  }

  return histos
}

func flatten(_ image: CGImage) throws -> [NRGBA] {
  let width = image.width
  let height = image.height
  guard width > 0, height > 0 else {
    throw FlattenError.unsupportedImage
  }

  let bytesPerPixel = 4
  let bytesPerRow = width * bytesPerPixel
  let countBytes = height * bytesPerRow

  var raw = [UInt8](repeating: 0, count: countBytes)

  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

  raw.withUnsafeMutableBytes { (ptr) in
    if let ctx = CGContext(
      data: ptr.baseAddress,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) {
      ctx.interpolationQuality = .none
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
  }

  var out = [NRGBA](repeating: NRGBA(), count: width * height)
  raw.withUnsafeBytes { (src) in
    let p = src.bindMemory(to: UInt8.self).baseAddress!
    for y in 0..<height {
      let row = p.advanced(by: y * bytesPerRow)
      for x in 0..<width {
        let px = row.advanced(by: x * 4)
        let r = px[0], g = px[1], b = px[2], a = px[3]
        if a == 0 {
          out[y * width + x] = NRGBA(r: 0, g: 0, b: 0, a: 0)
        } else {
          let rr = UInt8(min(255, Int(r) * 255 / Int(a)))
          let gg = UInt8(min(255, Int(g) * 255 / Int(a)))
          let bb = UInt8(min(255, Int(b) * 255 / Int(a)))
          out[y * width + x] = NRGBA(r: rr, g: gg, b: bb, a: a)
        }
      }
    }
  }

  return out
}
