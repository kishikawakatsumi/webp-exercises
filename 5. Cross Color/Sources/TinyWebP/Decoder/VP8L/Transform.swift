///// Returns the number of square tiles (of side 2ᵇⁱᵗˢ pixels) needed to cover
///// `size` pixels. Mirrors the Go helper 1-for-1.
/////
///// Equivalent to: `ceil(size / (1 << bits))`.
//@inline(__always)
//func nTiles(_ size: Int32, bits: UInt32) -> Int32 {
//  (size + (1 << bits) - 1) >> bits
//}
//
///// Matches the VP8L spec and the earlier Swift enums we defined.
//enum TransformType: UInt32 {
//  case predictor = 0
//  case crossColor = 1
//  case subtractGreen = 2
//  case colorIndexing = 3
//  static let count = 4
//}
//
///// Parameters for one forward/inverse transform stage.
//struct Transform {
//  var type: TransformType = .predictor
//
//  /// Width *before* forward transform (= after inverse).
//  /// Color-indexing may shrink this.
//  var oldWidth: Int32 = 0
//
//  /// * Predictor / Cross-Color:  log₂(tileSize).
//  /// * Color-Indexing:           bits per color-table index (8 >> bits).
//  /// * Subtract-Green:           unused.
//  var bits: UInt32 = 0
//
//  /// For Predictor & Cross-Color: the tile ARGB values.
//  /// For Color-Indexing:          the palette (≤ 256×4 bytes).
//  /// Unused for Subtract-Green.
//  var pix: [UInt8] = []
//}
//
//// Each inverse transform has the signature:
////    (Transform, [UInt8], Int32 /*imageHeight*/) -> [UInt8]
//typealias InverseTransformFn = (_ t: Transform, _ pix: [UInt8], _ height: Int32) -> [UInt8]
//
///// Table indexed by `TransformType.rawValue`.
//nonisolated(unsafe) let inverseTransforms: [InverseTransformFn] = [
//  inversePredictor,       // 0
//  inverseCrossColor,      // 1
//  inverseSubtractGreen,   // 2
//  inverseColorIndexing    // 3
//]
//
//// MARK: - Tiny helpers (spec §3.4.1) -----------------------------------------
//
///// Absolute value for a 32-bit signed integer.
///// (Swift already has a global `abs`, but we keep the same signature as the Go code.)
//@inline(__always)
//func abs(_ x: Int32) -> Int32 {
//  return x < 0 ? -x : x
//}
//
///// Average of two bytes, rounded toward zero (same as integer division in Go).
//@inline(__always)
//func avg2(_ a: UInt8, _ b: UInt8) -> UInt8 {
//  return UInt8((Int(a) + Int(b)) / 2)
//}
//
///// a + b − c, clamped to the 0‥255 range.
//@inline(__always)
//func clampAddSubtractFull(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
//  let x = Int(a) + Int(b) - Int(c)
//  switch x {
//  case ..<0:
//    return 0
//  case 0...255:
//    return UInt8(x)
//  default:
//    return 255
//  }
//}
//
///// a + (a − b)/2, clamped to the 0‥255 range.
//@inline(__always)
//func clampAddSubtractHalf(_ a: UInt8, _ b: UInt8) -> UInt8 {
//  let x = Int(a) + (Int(a) - Int(b)) / 2
//  switch x {
//  case ..<0:
//    return 0
//  case 0...255:
//    return UInt8(x)
//  default:
//    return 255
//  }
//}
//
//func inversePredictor(_ t: Transform, _ pix: [UInt8], _ h: Int32) -> [UInt8] {
//  // Trivial no-op cases.
//  guard t.oldWidth > 0 && h > 0 else { return pix }
//
//  // Copy-on-write so we can mutate freely.
//  var out = pix
//
//  // ------------------------------------------------------------------ //
//  // 1) First pixel and first row.                                      //
//  // ------------------------------------------------------------------ //
//  out[3] = out[3] &+ 0xFF                              // (0,0) predictor = opaque black
//
//  var p: Int32 = 4                                     // current write index
//  //  let mask = (Int32(1) << t.bits) &- 1
//  let mask = (Int32(1) << t.bits) - 1
//
//  // First row → mode 1 (Left).
//  for _ in 1..<t.oldWidth {
//    out[Int(p + 0)] = out[Int(p + 0)] &+ out[Int(p - 4)]
//    out[Int(p + 1)] = out[Int(p + 1)] &+ out[Int(p - 3)]
//    out[Int(p + 2)] = out[Int(p + 2)] &+ out[Int(p - 2)]
//    out[Int(p + 3)] = out[Int(p + 3)] &+ out[Int(p - 1)]
//    p &+= 4
//  }
//
//  // ------------------------------------------------------------------ //
//  // 2) Remaining rows.                                                 //
//  // ------------------------------------------------------------------ //
//  var top = 0                                           // index of pixel immediately above (p − 4 × oldWidth)
//  let tilesPerRow = nTiles(t.oldWidth, bits: t.bits)
//
//  for y in 1..<h {
//    // First column of the row → mode 2 (Top).
//    out[Int(p + 0)] = out[Int(p + 0)] &+ out[top + 0]
//    out[Int(p + 1)] = out[Int(p + 1)] &+ out[top + 1]
//    out[Int(p + 2)] = out[Int(p + 2)] &+ out[top + 2]
//    out[Int(p + 3)] = out[Int(p + 3)] &+ out[top + 3]
//    p   &+= 4
//    top &+= 4
//
//    // Tile predictor map lookup.
//    var q            = 4 * Int((y >> t.bits) * tilesPerRow)
//    var mode: UInt8  = t.pix[q + 1] & 0x0F
//    q += 4
//
//    for x in 1..<t.oldWidth {
//      if (x & mask) == 0 {
//        mode = t.pix[q + 1] & 0x0F       // new tile
//        q   += 4
//      }
//
//      switch mode {
//      case 0:   // Opaque black
//        out[Int(p + 3)] = out[Int(p + 3)] &+ 0xFF
//
//      case 1:   // Left
//        for c in 0..<4 {
//          out[Int(p + Int32(c))] = out[Int(p + Int32(c))] &+ out[Int(p - 4 + Int32(c))]
//        }
//
//      case 2:   // Top
//        for c in 0..<4 {
//          out[Int(p + Int32(c))] = out[Int(p + Int32(c))] &+ out[top + c]
//        }
//
//      case 3:   // Top-Right
//        for c in 0..<4 {
//          out[Int(p + Int32(c))] = out[Int(p + Int32(c))] &+ out[top + 4 + c]
//        }
//
//      case 4:   // Top-Left
//        for c in 0..<4 {
//          out[Int(p + Int32(c))] = out[Int(p + Int32(c))] &+ out[top - 4 + c]
//        }
//
//      case 5:   // avg2(avg2(L,TR),T)
//        out[Int(p + 0)] &+= avg2(avg2(out[Int(p - 4)], out[top + 4]), out[top + 0])
//        out[Int(p + 1)] &+= avg2(avg2(out[Int(p - 3)], out[top + 5]), out[top + 1])
//        out[Int(p + 2)] &+= avg2(avg2(out[Int(p - 2)], out[top + 6]), out[top + 2])
//        out[Int(p + 3)] &+= avg2(avg2(out[Int(p - 1)], out[top + 7]), out[top + 3])
//
//      case 6:   // avg2(L, TL)
//        for c in 0..<4 {
//          out[Int(p + Int32(c))] = out[Int(p + Int32(c))] &+ avg2(out[Int(p - 4 + Int32(c))], out[top - 4 + c])
//        }
//
//      case 7:   // avg2(L, T)
//        for c in 0..<4 {
//          out[Int(p + Int32(c))] = out[Int(p + Int32(c))] &+ avg2(out[Int(p - 4 + Int32(c))], out[top + c])
//        }
//
//      case 8:   // avg2(TL, T)
//        for c in 0..<4 {
//          out[Int(p + Int32(c))] = out[Int(p + Int32(c))] &+ avg2(out[top - 4 + c], out[top + c])
//        }
//
//      case 9:   // avg2(T, TR)
//        for c in 0..<4 {
//          out[Int(p + Int32(c))] = out[Int(p + Int32(c))] &+ avg2(out[top + c], out[top + 4 + c])
//        }
//
//      case 10:  // avg2(avg2(L,TL), avg2(T,TR))
//        out[Int(p + 0)] &+= avg2(avg2(out[Int(p - 4)], out[top - 4]), avg2(out[top + 0], out[top + 4]))
//        out[Int(p + 1)] &+= avg2(avg2(out[Int(p - 3)], out[top - 3]), avg2(out[top + 1], out[top + 5]))
//        out[Int(p + 2)] &+= avg2(avg2(out[Int(p - 2)], out[top - 2]), avg2(out[top + 2], out[top + 6]))
//        out[Int(p + 3)] &+= avg2(avg2(out[Int(p - 1)], out[top - 1]), avg2(out[top + 3], out[top + 7]))
//
//      case 11:  // Select(L, T, TL)
//        let l0 = Int32(out[Int(p - 4)]), l1 = Int32(out[Int(p - 3)])
//        let l2 = Int32(out[Int(p - 2)]), l3 = Int32(out[Int(p - 1)])
//        let c0 = Int32(out[top - 4]),    c1 = Int32(out[top - 3])
//        let c2 = Int32(out[top - 2]),    c3 = Int32(out[top - 1])
//        let t0 = Int32(out[top + 0]),    t1 = Int32(out[top + 1])
//        let t2 = Int32(out[top + 2]),    t3 = Int32(out[top + 3])
//
//        let l  = abs(c0 - t0) + abs(c1 - t1) + abs(c2 - t2) + abs(c3 - t3)
//        let tt = abs(c0 - l0) + abs(c1 - l1) + abs(c2 - l2) + abs(c3 - l3)
//
//        if l < tt {
//          out[Int(p + 0)] &+= UInt8(l0)
//          out[Int(p + 1)] &+= UInt8(l1)
//          out[Int(p + 2)] &+= UInt8(l2)
//          out[Int(p + 3)] &+= UInt8(l3)
//        } else {
//          out[Int(p + 0)] &+= UInt8(t0)
//          out[Int(p + 1)] &+= UInt8(t1)
//          out[Int(p + 2)] &+= UInt8(t2)
//          out[Int(p + 3)] &+= UInt8(t3)
//        }
//
//      case 12:  // clampAddSubtractFull(L, T, TL)
//        out[Int(p + 0)] &+= clampAddSubtractFull(out[Int(p - 4)], out[top + 0], out[top - 4])
//        out[Int(p + 1)] &+= clampAddSubtractFull(out[Int(p - 3)], out[top + 1], out[top - 3])
//        out[Int(p + 2)] &+= clampAddSubtractFull(out[Int(p - 2)], out[top + 2], out[top - 2])
//        out[Int(p + 3)] &+= clampAddSubtractFull(out[Int(p - 1)], out[top + 3], out[top - 1])
//
//      case 13:  // clampAddSubtractHalf(avg2(L,T), TL)
//        out[Int(p + 0)] &+= clampAddSubtractHalf(avg2(out[Int(p - 4)], out[top + 0]), out[top - 4])
//        out[Int(p + 1)] &+= clampAddSubtractHalf(avg2(out[Int(p - 3)], out[top + 1]), out[top - 3])
//        out[Int(p + 2)] &+= clampAddSubtractHalf(avg2(out[Int(p - 2)], out[top + 2]), out[top - 2])
//        out[Int(p + 3)] &+= clampAddSubtractHalf(avg2(out[Int(p - 1)], out[top + 3]), out[top - 1])
//
//      default:
//        break
//      }
//
//      p   &+= 4
//      top &+= 4
//    }
//  }
//
//  return out
//}
//
///// Reverses the Cross-Color transform (spec §3.3).
/////
///// The transform applies three signed coefficients—green→red, green→blue, and
///// red→blue—to reconstruct the original RGB channels.
//func inverseCrossColor(_ t: Transform, _ pix: [UInt8], _ h: Int32) -> [UInt8] {
//  // Copy-on-write: output buffer we can mutate freely.
//  var out = pix
//
//  var greenToRed:  Int32 = 0
//  var greenToBlue: Int32 = 0
//  var redToBlue:   Int32 = 0
//
//  var p: Int32 = 0  // byte offset in `out`
//  //  let mask = (Int32(1) << t.bits) &- 1
//  let mask = (Int32(1) << t.bits) - 1
//  let tilesPerRow   = nTiles(t.oldWidth, bits: t.bits)
//
//  for y in 0..<h {
//    // q indexes the tile-parameter image (`t.pix`).
//    var q = 4 * Int((y >> t.bits) * tilesPerRow)
//
//    for x in 0..<t.oldWidth {
//
//      // --- Load new coefficients at tile boundaries ---------------
//      if (x & mask) == 0 {
//        redToBlue   = Int32(Int8(bitPattern: t.pix[q + 0]))
//        greenToBlue = Int32(Int8(bitPattern: t.pix[q + 1]))
//        greenToRed  = Int32(Int8(bitPattern: t.pix[q + 2]))
//        q += 4
//      }
//
//      let idx  = Int(p)
//      var r    = out[idx + 0]
//      let g    = out[idx + 1]
//      var b    = out[idx + 2]
//
//      r &+= UInt8(truncatingIfNeeded: (greenToRed &* Int32(Int8(bitPattern: g))) >> 5)
//      b &+= UInt8(truncatingIfNeeded: (greenToBlue &* Int32(Int8(bitPattern: g))) >> 5)
//      b &+= UInt8(truncatingIfNeeded: (redToBlue &* Int32(Int8(bitPattern: r))) >> 5)
//
//      out[idx + 0] = r
//      out[idx + 2] = b
//
//      p &+= 4 // move to next pixel (RGBA → +4 bytes)
//    }
//  }
//
//  return out
//}
//
///// Reverses the Subtract-Green stage (spec §3.2).
/////
///// Each pixel was previously stored as:
///// ```text
/////   R' = R − G
/////   G' = G
/////   B' = B − G
///// ```
///// Recover the original values by adding the green channel back into red & blue.
//func inverseSubtractGreen(_ t: Transform, _ pix: [UInt8], _ h: Int32) -> [UInt8] {
//  var out = pix                              // copy-on-write
//
//  var p = 0
//  while p < out.count {
//    let g = out[p + 1]                     // green
//    out[p + 0] &+= g                       // red   += green
//    out[p + 2] &+= g                       // blue  += green
//    p += 4                                 // next RGBA pixel
//  }
//
//  return out
//}
//
///// Reconstructs true-color pixels from the packed index image produced by the
///// Color-Index transform (spec §3.1).
/////
///// * `t.pix`    holds the **palette** (≤ 256 colors, each as 4-byte ARGB).
///// * `pix`      is the index image (still stored in 4-byte RGBA tuples, but
/////              only the **green** byte is significant).
///// * `t.bits`   tells how many indices are packed into one byte:
/////              *0 → 8 bits / pixel (1:1 width)
/////              *1 → 4 bits / pixel (2:1)
/////              *2 → 2 bits / pixel (4:1)
/////              *3 → 1 bit  / pixel (8:1)
//func inverseColorIndexing(_ t: Transform, _ pix: [UInt8], _ h: Int32) -> [UInt8] {
//
//  // --------------------------- Fast path: 8-bit indices -------------------
//  if t.bits == 0 {
//    var out = pix                                // copy-on-write buffer
//    var p = 0
//    while p < out.count {
//      let palIdx = Int(pix[p + 1]) * 4         // index uses green byte
//      out[p + 0] = t.pix[palIdx + 0]           // R
//      out[p + 1] = t.pix[palIdx + 1]           // G
//      out[p + 2] = t.pix[palIdx + 2]           // B
//      out[p + 3] = t.pix[palIdx + 3]           // A
//      p += 4
//    }
//
//    return out
//  }
//
//  // --------------------------- Packed-index paths -------------------------
//  // `bitsPerPixel` = 4, 2, or 1  for t.bits = 1, 2, 3.
//  let bitsPerPixel: UInt32 = 8 >> t.bits
//
//  // Masks to extract current pixel’s index and to detect “byte boundaries”.
//  // (Direct port of Go’s vMask / xMask table.)
//  let (vMask, xMask): (UInt32, Int32) = {
//    switch t.bits {
//    case 1: return (0x0F, 0x01)
//    case 2: return (0x03, 0x03)
//    default: return (0x01, 0x07)     // t.bits == 3
//    }
//  }()
//
//  // Output buffer: original width × height × 4 bytes (RGBA).
//  var dst = [UInt8](repeating: 0, count: Int(4 * t.oldWidth * h))
//
//  var srcOffset: Int32 = 0    // byte offset in `pix`
//  var dstOffset: Int32 = 0    // byte offset in `dst`
//  var packed: UInt32  = 0     // current packed-indices byte
//
//  for _ in 0..<h {
//    for x in 0..<t.oldWidth {
//
//      // Load a new byte of packed indices whenever we cross a boundary.
//      if (x & xMask) == 0 {
//        packed = UInt32(pix[Int(srcOffset + 1)])
//        srcOffset &+= 4                             // advance to next RGBA tuple
//      }
//
//      // Extract current palette index.
//      let palIdx = Int((packed & vMask) * 4)
//      dst[Int(dstOffset + 0)] = t.pix[palIdx + 0]
//      dst[Int(dstOffset + 1)] = t.pix[palIdx + 1]
//      dst[Int(dstOffset + 2)] = t.pix[palIdx + 2]
//      dst[Int(dstOffset + 3)] = t.pix[palIdx + 3]
//      dstOffset &+= 4
//
//      packed >>= bitsPerPixel                       // next index in the byte
//    }
//  }
//
//  return dst
//}
