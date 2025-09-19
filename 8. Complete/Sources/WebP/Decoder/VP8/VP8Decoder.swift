import Foundation

enum LimitReaderError: Error {
  case unexpectedEOF
}

struct LimitReader {
  private let stream: RIFFReader // the wrapped source
  var remaining: Int // bytes still allowed to read

  init(stream: RIFFReader, limit: Int) {
    self.stream    = stream
    self.remaining = limit
  }

  mutating func readFull(into buffer: inout [UInt8]) throws {
    guard buffer.count <= remaining else { throw LimitReaderError.unexpectedEOF }

    var offset = 0
    while offset < buffer.count {
      let n = stream.read(&buffer + offset, maxLength: buffer.count - offset)
      if n <= 0 { throw LimitReaderError.unexpectedEOF }
      offset    += n
      remaining -= n
    }
  }
}

struct FrameHeader {
  var keyFrame = false
  var versionNumber: UInt8 = 0
  var showFrame = false
  var firstPartitionLen: UInt32 = 0
  var width = 0
  var height = 0
  var xScale: UInt8 = 0
  var yScale: UInt8 = 0
}

let nSegment = 4
private let nSegmentProb  = 3

struct SegmentHeader {
  var useSegment = false
  var updateMap = false
  var relativeDelta = false
  var quantizer = [Int8] (repeating: 0, count: nSegment)
  var filterStrength = [Int8] (repeating: 0, count: nSegment)
  var prob = [UInt8](repeating: 0, count: nSegmentProb)
}

private let nRefLFDelta  = 4
private let nModeLFDelta = 4

struct FilterHeader {
  var simple = false
  var level: Int8 = 0
  var sharpness: UInt8 = 0
  var useLFDelta = false
  var refLFDelta = [Int8] (repeating: 0, count: nRefLFDelta)
  var modeLFDelta = [Int8] (repeating: 0, count: nModeLFDelta)
  var perSegmentLevel = [Int8] (repeating: 0, count: nSegment)
}

struct MacroblockState {
  var pred  = [UInt8](repeating: 0, count: 4)
  var nzMask: UInt8 = 0
  var nzY16: UInt8 = 0
}

struct VP8Decoder {
  var r: LimitReader = LimitReader(stream: RIFFReader(data: Data(), totalLen: 0), limit: 0)
  private var scratch = [UInt8](repeating: 0, count: 8)

  var img: YCbCrImage!
  var mbw: Int = 0
  var mbh: Int = 0

  var frameHeader  = FrameHeader()
  var segmentHeader = SegmentHeader()
  var filterHeader  = FilterHeader()

  var fp = Partition(with: [])
  var op = [Partition](repeating: Partition(with: []), count: 8)
  var nOP: Int = 0

  var quant = [Quant](repeating: Quant(), count: nSegment)

  var tokenProb = Array(
    repeating: Array(
      repeating: Array(
        repeating: Array(
          repeating: UInt8(0),
          count: nProb),
        count: nContext),
      count: nBand
    ),
    count: nPlane
  )

  var useSkipProb = false
  var skipProb: UInt8 = 0

  var filterParams =
  Array(repeating: [FilterParam](repeating: FilterParam(), count: 2), count: nSegment)
  var perMBFilterParams: [FilterParam] = []

  var segment = 0
  var leftMB = MacroblockState()
  var upMB: [MacroblockState] = []

  var nzDCMask: UInt32 = 0
  var nzACMask: UInt32 = 0

  var usePredY16 = false
  var predY16: UInt8 = 0
  var predC8: UInt8 = 0
  var predY4 = Array(repeating: Array(repeating: UInt8(0), count: 4), count: 4)

  var coeff = [Int16](repeating: 0, count: 1 * 16 * 16 + 2 * 8 * 8 + 1 * 4 * 4)

  var ybr = Array(repeating: Array(repeating: UInt8(0), count: 32), count: 1 + 16 + 1 + 8)
}

extension VP8Decoder {
  static func make() -> VP8Decoder {
    VP8Decoder()
  }

  mutating func initStream(stream: RIFFReader, limit: Int) {
    self.r = LimitReader(stream: stream, limit: limit)
  }

  mutating func decodeFrameHeader() throws -> FrameHeader {

    var b = [UInt8](repeating: 0, count: 3)
    try r.readFull(into: &b)

    frameHeader.keyFrame = (b[0] & 0x01) == 0
    frameHeader.versionNumber = (b[0] >> 1) & 0x07
    frameHeader.showFrame = ((b[0] >> 4) & 0x01) == 1
    frameHeader.firstPartitionLen =
    (UInt32(b[0]) >> 5)
    | (UInt32(b[1]) << 3)
    | (UInt32(b[2]) << 11)

    if !frameHeader.keyFrame {
      return frameHeader
    }

    b = [UInt8](repeating: 0, count: 7)
    try r.readFull(into: &b)

    guard b[0] == 0x9d, b[1] == 0x01, b[2] == 0x2a else {
      throw WebPError.invalidFormat
    }

    frameHeader.width   = Int(b[4] & 0x3f) << 8 | Int(b[3])
    frameHeader.height  = Int(b[6] & 0x3f) << 8 | Int(b[5])
    frameHeader.xScale  = b[4] >> 6
    frameHeader.yScale  = b[6] >> 6

    mbw = (frameHeader.width  + 0x0f) >> 4
    mbh = (frameHeader.height + 0x0f) >> 4

    segmentHeader = SegmentHeader()
    segmentHeader.prob = [0xff, 0xff, 0xff]

    filterHeader  = FilterHeader()

    tokenProb = defaultTokenProb

    segment = 0

    return frameHeader
  }

  mutating func ensureImg() {
    if let img = img {
      let p0 = img.rect.origin
      let p1 = CGPoint(x: img.rect.maxX, y: img.rect.maxY)
      if p0.x == 0, p0.y == 0,
         Int(p1.x) >= 16 * mbw,
         Int(p1.y) >= 16 * mbh {
        return
      }
    }

    let fullW  = 16 * mbw
    let fullH  = 16 * mbh
    let fullRC = CGRect(x: 0, y: 0, width: fullW, height: fullH)

    let canvas = YCbCrImage(fullRC, subsampleRatio: .sub420)
    let cropRC = CGRect(x: 0, y: 0, width: frameHeader.width, height: frameHeader.height)

    self.img = canvas.subImage(cropRC)

    self.perMBFilterParams =
    Array(repeating: FilterParam(), count: mbw * mbh)

    self.upMB = Array(repeating: MacroblockState(), count: mbw)
  }

  mutating func parseSegmentHeader() {
    segmentHeader.useSegment  = fp.readBit(prob: uniformProb)
    guard segmentHeader.useSegment else {
      segmentHeader.updateMap = false
      return
    }

    segmentHeader.updateMap   = fp.readBit(prob: uniformProb)

    if fp.readBit(prob: uniformProb) {
      segmentHeader.relativeDelta = !fp.readBit(prob: uniformProb)

      for i in 0..<nSegment {
        let v = fp.readOptionalInt(prob: uniformProb, bits: 7)
        segmentHeader.quantizer[i] = Int8(truncatingIfNeeded: v)
      }

      for i in 0..<nSegment {
        let v = fp.readOptionalInt(prob: uniformProb, bits: 6)
        segmentHeader.filterStrength[i] = Int8(truncatingIfNeeded: v)
      }
    }

    guard segmentHeader.updateMap else {
      return
    }

    for i in 0..<nSegmentProb {
      if fp.readBit(prob: uniformProb) {
        let p = fp.readUInt(prob: uniformProb, bits: 8)
        segmentHeader.prob[i] = UInt8(truncatingIfNeeded: p)
      } else {
        segmentHeader.prob[i] = 0xFF
      }
    }
  }

  mutating func parseFilterHeader() {
    filterHeader.simple     = fp.readBit(prob: uniformProb)
    filterHeader.level      = Int8(truncatingIfNeeded: fp.readUInt(prob: uniformProb, bits: 6))
    filterHeader.sharpness  = UInt8(fp.readUInt(prob: uniformProb, bits: 3))
    filterHeader.useLFDelta = fp.readBit(prob: uniformProb)

    if filterHeader.useLFDelta, fp.readBit(prob: uniformProb) {
      for idx in 0..<nRefLFDelta {
        let v = fp.readOptionalInt(prob: uniformProb, bits: 6)
        filterHeader.refLFDelta[idx] = Int8(truncatingIfNeeded: v)
      }

      for idx in 0..<nModeLFDelta {
        let v = fp.readOptionalInt(prob: uniformProb, bits: 6)
        filterHeader.modeLFDelta[idx] = Int8(truncatingIfNeeded: v)
      }
    }

    guard filterHeader.level > 0 else {
      return
    }

    if segmentHeader.useSegment {
      for idx in 0..<nSegment {
        var strength = segmentHeader.filterStrength[idx]
        if segmentHeader.relativeDelta {
          strength &+= filterHeader.level
        }
        filterHeader.perSegmentLevel[idx] = strength
      }
    } else {
      filterHeader.perSegmentLevel[0] = filterHeader.level
    }

    computeFilterParams()
  }

  mutating func parseOtherPartitions() throws {
    let maxNOP = 1 << 3
    let pow2 = Int(fp.readUInt(prob: uniformProb, bits: 2))
    nOP = 1 << pow2
    precondition(nOP <= maxNOP)

    var partLens = [Int](repeating: 0, count: maxNOP)

    let headerBytes = 3 * (nOP - 1)
    partLens[nOP - 1] = r.remaining - headerBytes
    guard partLens[nOP - 1] >= 0 else {
      throw DecodingError.unexpectedEOF
    }

    if headerBytes > 0 {
      var hdr = [UInt8](repeating: 0, count: headerBytes)
      try r.readFull(into: &hdr)

      for i in 0 ..< (nOP - 1) {
        let pl = Int(hdr[3*i])
        | Int(hdr[3*i + 1]) << 8
        | Int(hdr[3*i + 2]) << 16

        guard pl <= partLens[nOP - 1] else {
          throw DecodingError.unexpectedEOF
        }
        partLens[i] = pl
        partLens[nOP - 1] -= pl
      }
    }

    if partLens[nOP - 1] >= (1 << 24) {
      throw DecodingError.tooMuchData
    }

    var payload = [UInt8](repeating: 0, count: r.remaining)
    try r.readFull(into: &payload)

    var offset = 0
    for i in 0 ..< nOP {
      let plen = partLens[i]
      let slice = payload[offset ..< offset + plen]
      op[i] = .init(with: [UInt8](slice))
      offset += plen
    }
  }

  mutating func parseOtherHeaders() throws {
    var firstPartition = [UInt8](repeating: 0, count: Int(frameHeader.firstPartitionLen))
    try r.readFull(into: &firstPartition)
    fp = .init(with: firstPartition)

    if frameHeader.keyFrame {
      _ = fp.readBit(prob: uniformProb)
      _ = fp.readBit(prob: uniformProb)
    }

    parseSegmentHeader()
    parseFilterHeader()
    try parseOtherPartitions()
    parseQuant()

    if !frameHeader.keyFrame {
      throw DecodingError.unimplementedFeature(
        "Golden/AltRef inter-frame decoding is not implemented")
    }

    _ = fp.readBit(prob: uniformProb)
    parseTokenProb()

    useSkipProb = fp.readBit(prob: uniformProb)
    if useSkipProb {
      skipProb = UInt8(fp.readUInt(prob: uniformProb, bits: 8))
    }

    if fp.unexpectedEOF {
      throw DecodingError.unexpectedEOF
    }
  }

  mutating func decodeFrame() throws -> YCbCrImage {
    ensureImg()
    try parseOtherHeaders()
    upMB = Array(repeating: MacroblockState(), count: mbw)

    for mby in 0..<mbh {
      leftMB = MacroblockState()

      for mbx in 0..<mbw {
        let skip = reconstruct(mbx: mbx, mby: mby)

        var fs = filterParams[segment][Int(btou(!usePredY16))]
        fs.inner = fs.inner || !skip
        perMBFilterParams[mbw * mby + mbx] = fs
      }
    }

    if fp.unexpectedEOF {
      throw DecodingError.unexpectedEOF
    }
    for part in op[0..<nOP] where part.unexpectedEOF {
      throw DecodingError.unexpectedEOF
    }

    if filterHeader.level != 0 {
      if filterHeader.simple {
        simpleFilter()
      } else {
        normalFilter()
      }
    }

    guard let yuv = img else {
      throw DecodingError.unexpectedEOF             
    }
    return yuv                                      
  }
}

enum DecodingError: Error {
  case unexpectedEOF
  case unimplementedFeature(String)
  case tooMuchData
}
