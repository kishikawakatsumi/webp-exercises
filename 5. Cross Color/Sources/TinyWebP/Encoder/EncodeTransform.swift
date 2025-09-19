@discardableResult
func applyColorTransform(
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

  let cte = NRGBA(r: 1, g: 2, b: 3, a: 255) // R→B, G→B, G→R の係数

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

          var r = Int(r8), g = Int(g8), b = Int(b8)

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
