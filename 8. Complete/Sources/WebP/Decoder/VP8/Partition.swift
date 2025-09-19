let lutShift: [UInt8] = [
  7,6,6,5,5,5,5,4,4,4,4,4,4,4,4,
  3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,
  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
]

let lutRangeM1: [UInt8] = [
  127,
  127,191,
  127,159,191,223,
  127,143,159,175,191,207,223,239,
  127,135,143,151,159,167,175,183,191,199,207,215,223,231,239,247,
  127,131,135,139,143,147,151,155,159,163,167,171,175,179,183,187,
  191,195,199,203,207,211,215,219,223,227,231,235,239,243,247,251,
  127,129,131,133,135,137,139,141,143,145,147,149,151,153,155,157,
  159,161,163,165,167,169,171,173,175,177,179,181,183,185,187,189,
  191,193,195,197,199,201,203,205,207,209,211,213,215,217,219,221,
  223,225,227,229,231,233,235,237,239,241,243,245,247,249,251,253,
]

let uniformProb: UInt8 = 128

class Partition {
  var buf: [UInt8] = []
  var r = 0

  var rangeM1: UInt32 = 254
  var bits:    UInt32 = 0
  var nBits:   UInt8  = 0

  var unexpectedEOF = false

  init(with buffer: [UInt8]) {
    buf = buffer
    r = 0
    rangeM1 = 254
    bits = 0
    nBits = 0
    unexpectedEOF = false
  }

  func reset(with buffer: [UInt8]) {
    buf = buffer
    r = 0
    rangeM1 = 254
    bits = 0
    nBits = 0
    unexpectedEOF = false
  }
}

extension Partition {
  @inline(__always)
  func readBit(prob: UInt8) -> Bool {
    if nBits < 8 {
      guard r < buf.count else {
        unexpectedEOF = true
        return false
      }

      let byte = UInt32(buf[r])
      bits |= byte << (8 - nBits)
      r += 1
      nBits += 8
    }

    let split = ((rangeM1 &* UInt32(prob)) >> 8) &+ 1

    let bitIsOne = bits >= (split << 8)

    if bitIsOne {
      rangeM1 &-= split
      bits &-= split << 8
    } else {
      rangeM1 = split &- 1
    }

    if rangeM1 < 127 {
      let shift = UInt32(lutShift[Int(rangeM1)])
      rangeM1 = UInt32(lutRangeM1[Int(rangeM1)])
      bits <<= shift
      nBits &-= UInt8(shift)
    }

    return bitIsOne
  }
}

extension Partition {
  @inline(__always)
  func readUInt(prob: UInt8, bits n: UInt8) -> UInt32 {
    var value: UInt32 = 0
    var remaining = n

    while remaining > 0 {
      remaining &-= 1
      if readBit(prob: prob) {
        value |= 1 << remaining
      }
    }
    return value
  }

  @inline(__always)
  func readInt(prob: UInt8, bits n: UInt8) -> Int32 {
    let magnitude = readUInt(prob: prob, bits: n)
    let signBit = readBit(prob: prob)
    return signBit ? -Int32(magnitude) : Int32(magnitude)
  }

  @inline(__always)
  func readOptionalInt(prob: UInt8, bits n: UInt8) -> Int32 {
    guard readBit(prob: prob) else {
      return 0
    }
    return readInt(prob: prob, bits: n)
  }
}
