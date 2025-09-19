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
  try writeBitStreamData(&bw, image: img, colorCacheBits: 4)

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

func writeBitStreamData(
  _ writer: inout BitWriter,
  image: CGImage,
  colorCacheBits: Int
) throws {
  let pixels = try flatten(image)
  let width = image.width
  let height = image.height

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
  debugDumpHistogramsGRBAD(histos, colorCacheBits: 0, topN: 24)
  
  var codes: [[HuffmanCode]] = []
  for i in 0..<5 {
    // WebP specs requires Huffman codes with maximum depth of 15
    print("\n[\(["G", "R", "B", "A", "D"][i])]")
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
    } else {
      i += 1
    }
  }
}

func encodeImageData(
  pixels: [NRGBA],
  width: Int,
  height: Int,
  colorCacheBits: Int
) -> [Int] {
  let cacheSize = (colorCacheBits > 0) ? (1 << colorCacheBits) : 0
  var cache = (cacheSize > 0) ? Array(repeating: NRGBA(r: 0, g: 0, b: 0, a: 0), count: cacheSize) : []

  var encoded = Array(repeating: 0, count: pixels.count * 4)
  var count = 0

  var i = 0
  while i < pixels.count {
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
    } else {
      i += 1
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
