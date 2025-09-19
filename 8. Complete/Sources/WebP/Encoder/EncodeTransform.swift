@discardableResult
public func applyPredictTransform(
  pixels: inout [NRGBA],
  width: Int,
  height: Int
) -> (tileBits: Int, bw: Int, bh: Int, blocks: [NRGBA]) {
  let tileBits = 4
  let tileSize = 1 << tileBits
  let bw = (width + tileSize - 1) / tileSize
  let bh = (height + tileSize - 1) / tileSize

  var blocks = Array(repeating: NRGBA(), count: bw * bh)
  var deltas = Array(repeating: NRGBA(), count: width * height)

  var accum: [[Int]] = [
    Array(repeating: 0, count: 256),
    Array(repeating: 0, count: 256),
    Array(repeating: 0, count: 256),
    Array(repeating: 0, count: 256),
    Array(repeating: 0, count: 40)
  ]
  var histos: [[Int]] = accum.map { Array(repeating: 0, count: $0.count) }

  for y in 0..<bh {
    for x in 0..<bw {
      let mx = min((x + 1) << tileBits, width)
      let my = min((y + 1) << tileBits, height)

      var best = 0
      var bestEntropy = 0.0

      for p in 0..<14 {
        for i in 0..<accum.count {
          histos[i] = accum[i]
        }

        var ty = (y << tileBits)
        while ty < my {
          var tx = (x << tileBits)
          while tx < mx {
            let d = applyFilter(pixels: pixels, width: width, x: tx, y: ty, prediction: p)
            let off = ty * width + tx

            let rDiff = Int(pixels[off].r) &- Int(d.r)
            let gDiff = Int(pixels[off].g) &- Int(d.g)
            let bDiff = Int(pixels[off].b) &- Int(d.b)
            let aDiff = Int(pixels[off].a) &- Int(d.a)

            histos[0][Int(UInt8(truncatingIfNeeded: rDiff))] += 1
            histos[1][Int(UInt8(truncatingIfNeeded: gDiff))] += 1
            histos[2][Int(UInt8(truncatingIfNeeded: bDiff))] += 1
            histos[3][Int(UInt8(truncatingIfNeeded: aDiff))] += 1

            tx += 1
          }
          ty += 1
        }

        var total = 0.0
        for histo in histos {
          var sum = 0
          var sumSq = 0
          for c in histo { sum += c; sumSq += c * c }
          if sum == 0 { continue }
          total += 1.0 - (Double(sumSq) / (Double(sum) * Double(sum)))
        }

        if p == 0 || total < bestEntropy {
          bestEntropy = total
          best = p
        }
      }

      var ty = (y << tileBits)
      while ty < my {
        var tx = (x << tileBits)
        while tx < mx {
          let d = applyFilter(pixels: pixels, width: width, x: tx, y: ty, prediction: best)
          let off = ty * width + tx

          let rDiff = pixels[off].r &- d.r
          let gDiff = pixels[off].g &- d.g
          let bDiff = pixels[off].b &- d.b
          let aDiff = pixels[off].a &- d.a

          deltas[off] = NRGBA(r: rDiff, g: gDiff, b: bDiff, a: aDiff)

          accum[0][Int(rDiff)] += 1
          accum[1][Int(gDiff)] += 1
          accum[2][Int(bDiff)] += 1
          accum[3][Int(aDiff)] += 1

          tx += 1
        }
        ty += 1
      }

      blocks[y * bw + x] = NRGBA(r: 0, g: UInt8(best), b: 0, a: 255)
    }
  }

  pixels = deltas
  return (tileBits, bw, bh, blocks)
}

func applyFilter(
  pixels: [NRGBA], width: Int, x: Int, y: Int, prediction: Int
) -> NRGBA {
  if x == 0 && y == 0 {
    return NRGBA(r: 0, g: 0, b: 0, a: 255)
  }
  if x == 0 {
    return pixels[(y - 1) * width + x]
  }
  if y == 0 {
    return pixels[y * width + (x - 1)]
  }

  let t  = pixels[(y - 1) * width + x]
  let l  = pixels[y * width + (x - 1)]
  let tl = pixels[(y - 1) * width + (x - 1)]

  let tr  = pixels[(y - 1) * width + (x + 1)]

  @inline(__always) func avg2(_ a: NRGBA, _ b: NRGBA) -> NRGBA {
    NRGBA(
      r: UInt8((Int(a.r) + Int(b.r)) / 2),
      g: UInt8((Int(a.g) + Int(b.g)) / 2),
      b: UInt8((Int(a.b) + Int(b.b)) / 2),
      a: UInt8((Int(a.a) + Int(b.a)) / 2)
    )
  }

  typealias F = (NRGBA, NRGBA, NRGBA, NRGBA) -> NRGBA
  let filters: [F] = [
    { _,_,_,_ in NRGBA(r: 0, g: 0, b: 0, a: 255) },     // 0
    { _,l,_,_ in l },                                   // 1
    { t,_,_,_ in t },                                   // 2
    { _,_,_,tr in tr },                                 // 3
    { _,_,tl,_ in tl },                                 // 4
    { t,l,_,tr in avg2(avg2(l, tr), t) },               // 5
    { _,l,tl,_ in avg2(l, tl) },                        // 6
    { t,l,_,_ in avg2(l, t) },                          // 7
    { t,_,tl,_ in avg2(tl, t) },                        // 8
    { t,_,_,tr in avg2(t, tr) },                        // 9
    { t,l,tl,tr in avg2(avg2(l, tl), avg2(t, tr)) },    // 10
    { t,l,tl,_ in                                       // 11 (Manhattan)
      let pr = Double(l.r) + Double(t.r) - Double(tl.r)
      let pg = Double(l.g) + Double(t.g) - Double(tl.g)
      let pb = Double(l.b) + Double(t.b) - Double(tl.b)
      let pa = Double(l.a) + Double(t.a) - Double(tl.a)
      let pl = abs(pa - Double(l.a)) + abs(pr - Double(l.r)) + abs(pg - Double(l.g)) + abs(pb - Double(l.b))
      let pt = abs(pa - Double(t.a)) + abs(pr - Double(t.r)) + abs(pg - Double(t.g)) + abs(pb - Double(t.b))
      return pl < pt ? l : t
    },
    { t,l,tl,_ in // 12 (clamped gradient)
      func clamp(_ v: Int) -> UInt8 { UInt8(max(0, min(255, v))) }
      return NRGBA(
        r: clamp(Int(l.r) + Int(t.r) - Int(tl.r)),
        g: clamp(Int(l.g) + Int(t.g) - Int(tl.g)),
        b: clamp(Int(l.b) + Int(t.b) - Int(tl.b)),
        a: clamp(Int(l.a) + Int(t.a) - Int(tl.a))
      )
    },
    { t,l,tl,_ in // 13
      let a = avg2(l, t)
      func clamp(_ v: Int) -> UInt8 { UInt8(max(0, min(255, v))) }
      return NRGBA(
        r: clamp(Int(a.r) + (Int(a.r) - Int(tl.r)) / 2),
        g: clamp(Int(a.g) + (Int(a.g) - Int(tl.g)) / 2),
        b: clamp(Int(a.b) + (Int(a.b) - Int(tl.b)) / 2),
        a: clamp(Int(a.a) + (Int(a.a) - Int(tl.a)) / 2)
      )
    }
  ]

  return filters[prediction](t, l, tl, tr)
}

@discardableResult
public func applyColorTransform(
  pixels: inout [NRGBA],
  width: Int,
  height: Int
) -> (tileBits: Int, bw: Int, bh: Int, blocks: [NRGBA]) {
  let tileBits = 4
  let tileSize = 1 << tileBits
  let bw = (width  + tileSize - 1) / tileSize
  let bh = (height + tileSize - 1) / tileSize

  var blocks = Array(repeating: NRGBA(), count: bw * bh)
  var deltas = Array(repeating: NRGBA(), count: width * height)

  let cte = NRGBA(r: 1, g: 2, b: 3, a: 255)

  for y in 0..<bh {
    for x in 0..<bw {
      let mx = min((x + 1) << tileBits, width)
      let my = min((y + 1) << tileBits, height)

      var tx = (x << tileBits)
      while tx < mx {
        var ty = (y << tileBits)
        while ty < my {
          let off = ty * width + tx

          let r8 = Int8(bitPattern: pixels[off].r)
          let g8 = Int8(bitPattern: pixels[off].g)
          let b8 = Int8(bitPattern: pixels[off].b)

          var r = Int(r8)
          var b = Int(b8)

          let cG = Int16(Int8(bitPattern: cte.g))
          let cR = Int16(Int8(bitPattern: cte.r))
          let cB = Int16(Int8(bitPattern: cte.b))
          let g16 = Int16(g8)
          let r16 = Int16(r8)

          b -= Int(Int8(truncatingIfNeeded: (cG &* g16) >> 5))
          b -= Int(Int8(truncatingIfNeeded: (cR &* r16) >> 5))
          r -= Int(Int8(truncatingIfNeeded: (cB &* g16) >> 5))

          pixels[off].r = UInt8(truncatingIfNeeded: r)
          pixels[off].b = UInt8(truncatingIfNeeded: b)
          deltas[off] = pixels[off]

          ty += 1
        }
        tx += 1
      }

      blocks[y * bw + x] = cte
    }
  }

  pixels = deltas
  return (tileBits, bw, bh, blocks)
}

public func applySubtractGreenTransform(pixels: inout [NRGBA]) {
  for i in pixels.indices {
    pixels[i].r = pixels[i].r &- pixels[i].g
    pixels[i].b = pixels[i].b &- pixels[i].g
  }
}

public enum PaletteError: Error {
  case exceeds256Colors
}

@discardableResult
public func applyPaletteTransform(
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
  if pal.count <= 2  { size = 8 }
  else if pal.count <= 4  { size = 4 }
  else if pal.count <= 16 { size = 2 }

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
