private let bCoeffBase = 1 * 16 * 16 + 0 * 8 * 8
private let rCoeffBase = 1 * 16 * 16 + 1 * 8 * 8
private let whtCoeffBase = 1 * 16 * 16 + 2 * 8 * 8

private let ybrYX = 8
private let ybrYY = 1
private let ybrBX = 8
private let ybrBY = 18
private let ybrRX = 24
private let ybrRY = 18

extension VP8Decoder {
  mutating func prepareYBR(mbx: Int, mby: Int) {
    if mbx == 0 {
      for y in 0..<17 {
        ybr[y][7] = 0x81
      }
      for y in 17..<26 {
        ybr[y][7] = 0x81
        ybr[y][23] = 0x81
      }
    } else {
      for y in 0..<17 {
        ybr[y][7] = ybr[y][7 + 16]
      }
      for y in 17..<26 {
        ybr[y][7] = ybr[y][15]
        ybr[y][23] = ybr[y][31]
      }
    }

    if mby == 0 {
      for x in 7..<28 {
        ybr[0][x] = 0x7F
      }           // Y
      for x in 7..<16 {
        ybr[17][x] = 0x7F
      }           // Cb left
      for x in 23..<32 {
        ybr[17][x] = 0x7F
      }           // Cr left
    } else {
      for i in 0..<16 {
        ybr[0][8 + i] = img.Y[(16 * mby - 1) * img.YStride + 16 * mbx + i]
      }
      for i in 0..<8 {
        ybr[17][8 + i]  = img.Cb[(8 * mby - 1) * img.CStride + 8 * mbx + i]
        ybr[17][24 + i] = img.Cr[(8 * mby - 1) * img.CStride + 8 * mbx + i]
      }
      if mbx == mbw - 1 {
        for i in 16..<20 {
          ybr[0][8 + i] = img.Y[(16 * mby - 1) * img.YStride + 16 * mbx + 15]
        }
      } else {
        for i in 16..<20 {
          ybr[0][8 + i] = img.Y[(16 * mby - 1) * img.YStride + 16 * mbx + i]
        }
      }
    }

    for y in stride(from: 4, to: 16, by: 4) {
      ybr[y][24] = ybr[0][24]
      ybr[y][25] = ybr[0][25]
      ybr[y][26] = ybr[0][26]
      ybr[y][27] = ybr[0][27]
    }
  }
}

@inline(__always) func btou(_ b: Bool) -> UInt8 {
  b ? 1 : 0
}

@inline(__always) func pack(_ v: [UInt8], _ shift: Int) -> UInt32 {
  let u = UInt32(v[0]) << 0 |
  UInt32(v[1]) << 1 |
  UInt32(v[2]) << 2 |
  UInt32(v[3]) << 3
  return u << UInt32(shift)
}

let unpack: [[UInt8]] = (0..<16).map { m -> [UInt8] in
  [(m >> 0) & 1, (m >> 1) & 1, (m >> 2) & 1, (m >> 3) & 1].map(UInt8.init)
}

let bands: [UInt8] = [
  0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0
]

let cat3456: [[UInt8]] = [
  [173,148,140, 0,0,0,0,0,0,0,0,0],
  [176,155,140,135,0,0,0,0,0,0,0,0],
  [180,157,141,134,130,0,0,0,0,0,0,0],
  [254,254,243,230,196,177,153,140,133,130,129,0]
]

let zigzag: [UInt8] = [
  0, 1, 4, 8,
  5, 2, 3, 6,
  9,12,13,10,
  7,11,14,15
]

extension VP8Decoder {
  @discardableResult
  mutating func parseResiduals4(
    partition r: Partition,
    plane: Int,
    context: UInt8,
    quant q: (UInt16, UInt16),
    skipFirstCoeff: Bool,
    coeffBase: Int
  ) -> UInt8 {
    let r = r
    let probPlane = tokenProb[plane]

    var n = skipFirstCoeff ? 1 : 0
    var p = probPlane[Int(bands[n])][Int(context)]

    guard r.readBit(prob: p[0]) else {
      return 0
    }

    while n < 16 {
      n += 1

      if !r.readBit(prob: p[1]) {
        p = probPlane[Int(bands[n])][0]
        continue
      }

      var v: UInt32 = 0

      if !r.readBit(prob: p[2]) {
        v = 1
        p = probPlane[Int(bands[n])][1]
      } else {
        if !r.readBit(prob: p[3]) {
          v = r.readBit(prob: p[4]) ? 3 + r.readUInt(prob: p[5], bits: 1) : 2
        } else if !r.readBit(prob: p[6]) {
          if !r.readBit(prob: p[7]) {
            v = 5 + r.readUInt(prob: 159, bits: 1)
          } else {
            v = 7 + 2 * r.readUInt(prob: 165, bits: 1) + r.readUInt(prob: 145, bits: 1)
          }

        } else {
          let b1 = r.readUInt(prob: p[8], bits: 1)
          let b0 = r.readUInt(prob: p[9+Int(b1)], bits: 1)
          let cat = 2 * b1 + b0

          let table = cat3456[Int(cat)]
          var acc: UInt32 = 0
          for t in table where t != 0 {
            acc = (acc << 1) | r.readUInt(prob: t, bits: 1)
          }
          v = 3 + (8 << cat) + acc
        }

        p = probPlane[Int(bands[n])][2]
      }

      let zIndex = zigzag[n - 1]
      let scale = Int32(btou(zIndex != 0) == 0 ? q.0 : q.1)
      var c = Int32(v) * scale
      if r.readBit(prob: uniformProb) {
        c = -c
      }
      coeff[coeffBase + Int(zIndex)] = Int16(c)

      if n == 16 || !r.readBit(prob: p[0]) {
        return 1
      }
    }

    return 1
  }

  @discardableResult
  mutating func parseResiduals(mbx: Int, mby: Int) -> Bool {
    let partition = op[mby & (nOP - 1)]

    var plane: Int = Plane.y1SansY2.rawValue
    let quant = quant[segment]

    if usePredY16 {
      let context = Int(leftMB.nzY16) + Int(upMB[mbx].nzY16)

      let nz = parseResiduals4(
        partition: partition,
        plane: Plane.y2.rawValue,
        context: UInt8(context),
        quant: (quant.y2[0], quant.y2[1]),
        skipFirstCoeff: false,
        coeffBase: whtCoeffBase
      )

      leftMB.nzY16 = nz
      upMB[mbx].nzY16 = nz

      inverseWHT16()

      plane = Plane.y1WithY2.rawValue
    }

    var nzDCMask: UInt32 = 0
    var nzACMask: UInt32 = 0
    var coeffBase = 0

    var nzDC: [UInt8] = Array(repeating: 0, count: 4)
    var nzAC: [UInt8] = Array(repeating: 0, count: 4)

    var lnz = unpack[Int(leftMB.nzMask & 0x0F)]
    var unz = unpack[Int(upMB[mbx].nzMask & 0x0F)]

    for y in 0..<4 {
      var nz = lnz[y]
      for x in 0..<4 {
        nz = parseResiduals4(
          partition: partition,
          plane: plane,
          context: nz + unz[x],
          quant: (quant.y1[0], quant.y1[1]),
          skipFirstCoeff: usePredY16,
          coeffBase: coeffBase
        )

        unz[x]  = nz
        nzAC[x] = nz
        nzDC[x] = btou(coeff[coeffBase] != 0)

        coeffBase += 16
      }

      lnz[y] = nz
      nzDCMask |= pack(nzDC,  y * 4)
      nzACMask |= pack(nzAC,  y * 4)
    }

    let lnzMaskY = pack(lnz, 0)
    let unzMaskY = pack(unz, 0)

    lnz = unpack[Int(leftMB.nzMask >> 4)]
    unz = unpack[Int(upMB[mbx].nzMask >> 4)]

    for c in stride(from: 0, to: 4, by: 2) {
      for y in 0..<2 {
        var nz = lnz[y + c]
        for x in 0..<2 {
          nz = parseResiduals4(
            partition: partition,
            plane: Plane.uv.rawValue,
            context: nz + unz[x + c],
            quant: (quant.uv[0], quant.uv[1]),
            skipFirstCoeff: false,
            coeffBase: coeffBase
          )

          unz[x + c] = nz
          nzAC[y * 2 + x] = nz
          nzDC[y * 2 + x] = btou(coeff[coeffBase] != 0)

          coeffBase += 16
        }
        lnz[y + c] = nz
      }
      nzDCMask |= pack(nzDC, 16 + c * 2)
      nzACMask |= pack(nzAC, 16 + c * 2)
    }

    let lnzMaskUV = pack(lnz, 4)
    let unzMaskUV = pack(unz, 4)

    leftMB.nzMask = UInt8(lnzMaskY | lnzMaskUV)
    upMB[mbx].nzMask = UInt8(unzMaskY | unzMaskUV)
    self.nzDCMask = nzDCMask
    self.nzACMask = nzACMask

    // Skip inner filter if absolutely no coefficients
    return nzDCMask == 0 && nzACMask == 0
  }

  mutating func reconstructMacroblock(mbx: Int, mby: Int) {
    if usePredY16 {
      let p = checkTopLeftPred(mbx: mbx, mby: mby, p: predY16)
      predFunc16[Int(p)]!(&self, 1, 8)

      for j in 0..<4 {
        for i in 0..<4 {
          let n = 4 * j + i
          let yPos = 4 * j + 1
          let xPos = 4 * i + 8
          let mask = UInt32(1) << UInt32(n)

          if nzACMask & mask != 0 {
            inverseDCT4(y: yPos, x: xPos, coeffBase: 16 * n)
          } else if nzDCMask & mask != 0 {
            inverseDCT4DCOnly(y: yPos, x: xPos, coeffBase: 16 * n)
          }
        }
      }

    } else {
      for j in 0..<4 {
        for i in 0..<4 {
          let n = 4 * j + i
          let yPos = 4 * j + 1
          let xPos = 4 * i + 8
          let mode = Int(predY4[j][i])

          predFunc4[mode]!(&self, yPos, xPos)

          let mask = UInt32(1) << UInt32(n)
          if nzACMask & mask != 0 {
            inverseDCT4(y: yPos, x: xPos, coeffBase: 16 * n)
          } else if nzDCMask & mask != 0 {
            inverseDCT4DCOnly(y: yPos, x: xPos, coeffBase: 16 * n)
          }
        }
      }
    }

    let pC = checkTopLeftPred(mbx: mbx, mby: mby, p: predC8)

    predFunc8[Int(pC)]!(&self, ybrBY, ybrBX)
    if nzACMask & 0x0F00_00 != 0 {
      inverseDCT8(y: ybrBY, x: ybrBX, coeffBase: bCoeffBase)
    } else if nzDCMask & 0x0F00_00 != 0 {
      inverseDCT8DCOnly(y: ybrBY, x: ybrBX, coeffBase: bCoeffBase)
    }

    predFunc8[Int(pC)]!(&self, ybrRY, ybrRX)
    if nzACMask & 0xF000_00 != 0 {
      inverseDCT8(y: ybrRY, x: ybrRX, coeffBase: rCoeffBase)
    } else if nzDCMask & 0xF000_00 != 0 {
      inverseDCT8DCOnly(y: ybrRY, x: ybrRX, coeffBase: rCoeffBase)
    }
  }

  @discardableResult
  mutating func reconstruct(mbx: Int, mby: Int) -> Bool {
    if segmentHeader.updateMap {
      if !fp.readBit(prob: segmentHeader.prob[0]) {
        segment = Int(fp.readUInt(prob: segmentHeader.prob[1], bits: 1))
      } else {
        segment = Int(fp.readUInt(prob: segmentHeader.prob[2], bits: 1)) + 2
      }
    }

    var skip = false
    if useSkipProb {
      skip = fp.readBit(prob: skipProb)
    }

    coeff = Array(repeating: 0, count: coeff.count)
    prepareYBR(mbx: mbx, mby: mby)

    usePredY16 = fp.readBit(prob: 145)
    if usePredY16 {
      parsePredModeY16(mbx: mbx)
    } else {
      parsePredModeY4(mbx: mbx)
    }
    parsePredModeC8()

    if !skip {
      skip = parseResiduals(mbx: mbx, mby: mby)
    } else {
      if usePredY16 {
        leftMB.nzY16 = 0
        upMB[mbx].nzY16 = 0
      }
      leftMB.nzMask = 0
      upMB[mbx].nzMask = 0
      nzDCMask = 0
      nzACMask = 0
    }

    reconstructMacroblock(mbx: mbx, mby: mby)

    var yi = (mby * img.YStride + mbx) * 16
    for row in 0..<16 {
      img.Y.replaceSubrange(
        yi ..< yi + 16,
        with: ybr[ybrYY + row][ybrYX ..< ybrYX + 16]
      )
      yi += img.YStride
    }

    var ci = (mby * img.CStride + mbx) * 8
    for row in 0..<8 {
      img.Cb.replaceSubrange(
        ci ..< ci + 8,
        with: ybr[ybrBY + row][ybrBX ..< ybrBX + 8]
      )
      img.Cr.replaceSubrange(
        ci ..< ci + 8,
        with: ybr[ybrRY + row][ybrRX ..< ybrRX + 8]
      )
      ci += img.CStride
    }

    return skip
  }
}
