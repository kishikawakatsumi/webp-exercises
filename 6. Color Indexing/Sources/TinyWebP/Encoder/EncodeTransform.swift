public enum PaletteError: Error {
  case exceeds256Colors
}

@discardableResult
func applyPaletteTransform(
  pixels: inout [NRGBA],
  width: Int,
  height: Int
) throws -> (palette: [NRGBA], packedWidth: Int) {
  var pal: [NRGBA] = []
  pal.reserveCapacity(256)
  for p in pixels {
    if !pal.contains(p) {
      pal.append(p)
    }
    if pal.count > 256 {
      throw PaletteError.exceeds256Colors
    }
  }

  var size = 1
  if pal.count <= 2 {
    size = 8
  } else if pal.count <= 4 {
    size = 4
  } else if pal.count <= 16 {
    size = 2
  }

  let pw = (width + size - 1) / size
  var packed = Array(repeating: NRGBA(), count: pw * height)
  let step = 8 / size

  for y in 0..<height {
    for x in 0..<pw {
      var pack = 0
      for i in 0..<size {
        let px = x * size + i
        if px >= width { break }
        if let idx = pal.firstIndex(of: pixels[y * width + px]) {
          pack |= (idx << (i * step))
        }
      }

      packed[y * pw + x] = NRGBA(r: 0, g: UInt8(truncatingIfNeeded: pack), b: 0, a: 255)
    }
  }

  pixels = packed

  if pal.count > 1 {
    for i in stride(from: pal.count - 1, through: 1, by: -1) {
      pal[i] = NRGBA(
        r: pal[i].r &- pal[i - 1].r,
        g: pal[i].g &- pal[i - 1].g,
        b: pal[i].b &- pal[i - 1].b,
        a: pal[i].a &- pal[i - 1].a
      )
    }
  }

  return (pal, pw)
}
