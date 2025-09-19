import Foundation

@inline(__always)
private func clip8(_ v: Int32) -> UInt8 {
  if v < 0 {
    return 0
  }
  if v > 255 {
    return 255
  }
  return UInt8(v)
}

extension VP8Decoder {
  mutating func inverseDCT4(y: Int, x: Int, coeffBase: Int) {
    let c1: Int32 = 85627
    let c2: Int32 = 35468

    var m = Array(repeating: Array(repeating: Int32(0), count: 4), count: 4)

    var base = coeffBase
    for i in 0..<4 {
      let a = Int32(coeff[base + 0]) + Int32(coeff[base + 8])
      let b = Int32(coeff[base + 0]) - Int32(coeff[base + 8])
      let c = ((Int32(coeff[base + 4]) * c2) >> 16) - ((Int32(coeff[base + 12]) * c1) >> 16)
      let d = ((Int32(coeff[base + 4]) * c1) >> 16) + ((Int32(coeff[base + 12]) * c2) >> 16)

      m[i][0] = a + d
      m[i][1] = b + c
      m[i][2] = b - c
      m[i][3] = a - d

      base += 1
    }

    for j in 0..<4 {
      let dc = m[0][j] + 4
      let a  = dc + m[2][j]
      let b  = dc - m[2][j]
      let c  = ((m[1][j] * c2) >> 16) - ((m[3][j] * c1) >> 16)
      let d  = ((m[1][j] * c1) >> 16) + ((m[3][j] * c2) >> 16)

      ybr[y + j][x + 0] = clip8(Int32(ybr[y + j][x + 0]) + (a + d) >> 3)
      ybr[y + j][x + 1] = clip8(Int32(ybr[y + j][x + 1]) + (b + c) >> 3)
      ybr[y + j][x + 2] = clip8(Int32(ybr[y + j][x + 2]) + (b - c) >> 3)
      ybr[y + j][x + 3] = clip8(Int32(ybr[y + j][x + 3]) + (a - d) >> 3)
    }
  }

  mutating func inverseDCT4DCOnly(y: Int, x: Int, coeffBase: Int) {
    let dc = (Int32(coeff[coeffBase]) + 4) >> 3
    for j in 0..<4 {
      for i in 0..<4 {
        ybr[y + j][x + i] = clip8(Int32(ybr[y + j][x + i]) + dc)
      }
    }
  }

  mutating func inverseDCT8(y: Int, x: Int, coeffBase: Int) {
    inverseDCT4(y: y + 0, x: x + 0, coeffBase: coeffBase + 0 * 16)
    inverseDCT4(y: y + 0, x: x + 4, coeffBase: coeffBase + 1 * 16)
    inverseDCT4(y: y + 4, x: x + 0, coeffBase: coeffBase + 2 * 16)
    inverseDCT4(y: y + 4, x: x + 4, coeffBase: coeffBase + 3 * 16)
  }

  mutating func inverseDCT8DCOnly(y: Int, x: Int, coeffBase: Int) {
    inverseDCT4DCOnly(y: y + 0, x: x + 0, coeffBase: coeffBase + 0 * 16)
    inverseDCT4DCOnly(y: y + 0, x: x + 4, coeffBase: coeffBase + 1 * 16)
    inverseDCT4DCOnly(y: y + 4, x: x + 0, coeffBase: coeffBase + 2 * 16)
    inverseDCT4DCOnly(y: y + 4, x: x + 4, coeffBase: coeffBase + 3 * 16)
  }

  mutating func inverseWHT16() {
    var m = Array(repeating: Int32(0), count: 16)

    for i in 0..<4 {
      let a0 = Int32(coeff[384 + 0 + i]) + Int32(coeff[384 + 12 + i])
      let a1 = Int32(coeff[384 + 4 + i]) + Int32(coeff[384 + 8  + i])
      let a2 = Int32(coeff[384 + 4 + i]) - Int32(coeff[384 + 8  + i])
      let a3 = Int32(coeff[384 + 0 + i]) - Int32(coeff[384 + 12 + i])

      m[0 + i] = a0 + a1
      m[8 + i] = a0 - a1
      m[4 + i] = a3 + a2
      m[12 + i] = a3 - a2
    }

    var out = 0
    for i in 0..<4 {
      let dc = m[0 + i*4] + 3
      let a0 = dc + m[3 + i*4]
      let a1 = m[1 + i*4] + m[2 + i*4]
      let a2 = m[1 + i*4] - m[2 + i*4]
      let a3 = dc - m[3 + i*4]

      coeff[out +  0] = Int16((a0 + a1) >> 3)
      coeff[out + 16] = Int16((a3 + a2) >> 3)
      coeff[out + 32] = Int16((a0 - a1) >> 3)
      coeff[out + 48] = Int16((a3 - a2) >> 3)

      out += 64
    }
  }
}
