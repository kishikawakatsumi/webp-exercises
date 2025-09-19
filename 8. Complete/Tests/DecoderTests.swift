import Foundation
import CoreGraphics
import Testing
@testable import WebP

@Test
func readBits() async throws {
  let bits: [UInt8] = [0b1101_0010, 0b1000_0001]
  let data = Data(bits)
  var decoder = VP8LDecoder(data: data)

  #expect(try decoder.read(5) == 0b10010)
  #expect(try decoder.read(7) == 0b0001110)
}

@Test
func readVP8LHeader() async throws {
  let bytes: [UInt8] = [
    0x2F, 0x0F, 0xC0, 0x03, 0x10, 0x12
  ]
  var decoder = VP8LDecoder(data: Data(bytes))
  let (w, h) = try decoder.decodeHeader()

  #expect(w == 16)
  #expect(h == 16)
}

/*
 Feature list:
 lossless_vec_?_0.webp: none
 lossless_vec_?_1.webp: PALETTE
 lossless_vec_?_2.webp: PREDICTION
 lossless_vec_?_3.webp: PREDICTION PALETTE
 lossless_vec_?_4.webp: SUBTRACT-GREEN
 lossless_vec_?_5.webp: SUBTRACT-GREEN PALETTE
 lossless_vec_?_6.webp: PREDICTION SUBTRACT-GREEN
 lossless_vec_?_7.webp: PREDICTION SUBTRACT-GREEN PALETTE
 lossless_vec_?_8.webp: CROSS-COLOR-TRANSFORM
 lossless_vec_?_9.webp: CROSS-COLOR-TRANSFORM PALETTE
 lossless_vec_?_10.webp: PREDICTION CROSS-COLOR-TRANSFORM
 lossless_vec_?_11.webp: PREDICTION CROSS-COLOR-TRANSFORM PALETTE
 lossless_vec_?_12.webp: CROSS-COLOR-TRANSFORM SUBTRACT-GREEN
 lossless_vec_?_13.webp: CROSS-COLOR-TRANSFORM SUBTRACT-GREEN PALETTE
 lossless_vec_?_14_.webp: PREDICTION CROSS-COLOR-TRANSFORM SUBTRACT-GREEN
 lossless_vec_?_15.webp: PREDICTION CROSS-COLOR-TRANSFORM SUBTRACT-GREEN PALETTE
 */
@Test
func decodeLossless01() async throws {
  let testcases = [
    "lossless_vec_1_0",
    "lossless_vec_1_1",
    "lossless_vec_1_2",
    "lossless_vec_1_3",
    "lossless_vec_1_4",
    "lossless_vec_1_5",
    "lossless_vec_1_6",
    "lossless_vec_1_7",
    "lossless_vec_1_8",
    "lossless_vec_1_9",
    "lossless_vec_1_10",
    "lossless_vec_1_11",
    "lossless_vec_1_12",
    "lossless_vec_1_13",
    "lossless_vec_1_14",
    "lossless_vec_1_15",
    "lossless_vec_2_0",
    "lossless_vec_2_1",
    "lossless_vec_2_2",
    "lossless_vec_2_3",
    "lossless_vec_2_4",
    "lossless_vec_2_5",
    "lossless_vec_2_6",
    "lossless_vec_2_7",
    "lossless_vec_2_8",
    "lossless_vec_2_9",
    "lossless_vec_2_10",
    "lossless_vec_2_11",
    "lossless_vec_2_12",
    "lossless_vec_2_13",
    "lossless_vec_2_14",
    "lossless_vec_2_15",
    "blue-purple-pink.lossless",
    "blue-purple-pink-large.lossless",
    "gopher-doc.1bpp.lossless",
    "gopher-doc.2bpp.lossless",
    "gopher-doc.4bpp.lossless",
    "gopher-doc.8bpp.lossless",
    "tux.lossless",
    "yellow_rose.lossless",
    "lossless_color_transform",
    "lossless_big_random_alpha",
    "color_cache_bits_11",
    "dual_transform",
    "bad_palette_index",
    "lossless1",
    "lossless2",
    "lossless3",
    "lossless4",
    "near_lossless_75",
    "one_color_no_palette",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8L", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(let buffer):
        #expect(Data(buffer.data) == fixture)
      case .ycbcr(_):
        fatalError()
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossless02() async throws {
  let testcases = [
    "blue-purple-pink",
    "blue-purple-pink-large",
    "gopher-doc.1bpp",
    "gopher-doc.2bpp",
    "gopher-doc.4bpp",
    "gopher-doc.8bpp",
    "tux",
    "yellow_rose",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8L", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).lossless.webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).lossless.bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(let buffer):
        #expect(Data(buffer.data) == fixture)
      case .ycbcr(_):
        fatalError()
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossless03() async throws {
  let testcases = [
    "near_lossless_75",
    "one_color_no_palette",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8L", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(let buffer):
        #expect(Data(buffer.data) == fixture)
      case .ycbcr(_):
        fatalError()
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossless04() async throws {
  let testcases = [
    "bad_palette_index",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8L", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(let buffer):
        #expect(Data(buffer.data) == fixture)
      case .ycbcr(_):
        fatalError()
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLosslessAlpha() async throws {
  let testcases = [
    "dual_transform",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8L", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(let buffer):
        #expect(Data(buffer.data) == fixture)
      case .ycbcr(_):
        fatalError()
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossless05() async throws {
  let testcases = [
    "1_webp_ll",
    "2_webp_ll",
    "3_webp_ll",
    "4_webp_ll",
    "5_webp_ll",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8L", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(let buffer):
        #expect(Data(buffer.data) == fixture)
      case .ycbcr(_):
        fatalError()
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossy01() async throws {
  let testcases = [
    "small_1x1",
    "small_1x13",
    "small_13x1",
    "small_31x13",
    "test",
    "test-nostrong",
    "very_short",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossy02() async throws {
  let testcases = [
    "test",
    "test-nostrong",
    "very_short",
    "bryce",
    "bug3",
    "lossy_extreme_probabilities",
    "lossy_q0_f100",
    "segment01",
    "segment02",
    "segment03",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossy03() async throws {
  let testcases = [
    "vp80-00-comprehensive-001",
    "vp80-00-comprehensive-002",
    "vp80-00-comprehensive-003",
    "vp80-00-comprehensive-004",
    "vp80-00-comprehensive-005",
    "vp80-00-comprehensive-006",
    "vp80-00-comprehensive-007",
    "vp80-00-comprehensive-008",
    "vp80-00-comprehensive-009",
    "vp80-00-comprehensive-010",
    "vp80-00-comprehensive-011",
    "vp80-00-comprehensive-012",
    "vp80-00-comprehensive-013",
    "vp80-00-comprehensive-014",
    "vp80-00-comprehensive-015",
    "vp80-00-comprehensive-016",
    "vp80-00-comprehensive-017",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossy04() async throws {
  let testcases = [
    "vp80-01-intra-1400",
    "vp80-01-intra-1411",
    "vp80-01-intra-1416",
    "vp80-01-intra-1417",
    "vp80-02-inter-1402",
    "vp80-02-inter-1412",
    "vp80-02-inter-1418",
    "vp80-02-inter-1424",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossy05() async throws {
  let testcases = [
    "vp80-03-segmentation-1442",
    "vp80-03-segmentation-1401",
    "vp80-03-segmentation-1403",
    "vp80-03-segmentation-1407",
    "vp80-03-segmentation-1408",
    "vp80-03-segmentation-1409",
    "vp80-03-segmentation-1410",
    "vp80-03-segmentation-1413",
    "vp80-03-segmentation-1414",
    "vp80-03-segmentation-1415",
    "vp80-03-segmentation-1425",
    "vp80-03-segmentation-1426",
    "vp80-03-segmentation-1427",
    "vp80-03-segmentation-1432",
    "vp80-03-segmentation-1435",
    "vp80-03-segmentation-1436",
    "vp80-03-segmentation-1437",
    "vp80-03-segmentation-1441",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossy06() async throws {
  let testcases = [
    "vp80-04-partitions-1404",
    "vp80-04-partitions-1405",
    "vp80-04-partitions-1406",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossy07() async throws {
  let testcases = [
    "vp80-05-sharpness-1428",
    "vp80-05-sharpness-1429",
    "vp80-05-sharpness-1430",
    "vp80-05-sharpness-1431",
    "vp80-05-sharpness-1433",
    "vp80-05-sharpness-1434",
    "vp80-05-sharpness-1438",
    "vp80-05-sharpness-1439",
    "vp80-05-sharpness-1440",
    "vp80-05-sharpness-1443",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossy08() async throws {
  let testcases = [
    "blue-purple-pink-large.no-filter.lossy",
    "blue-purple-pink-large.normal-filter.lossy",
    "blue-purple-pink-large.simple-filter.lossy",
    "blue-purple-pink.lossy",
    "video-001.lossy",
    "yellow_rose.lossy",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(_):
        fatalError()
      }
    }
  }
}

@Test
func decodeLossyAlpha01() async throws {
  let testcases = [
    "alpha_color_cache",
    "big_endian_bug_393",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(_):
        fatalError()
      case .nycbcra(let yuvA):
        var data = Data(capacity: yuvA.ycbcr.y.count + yuvA.ycbcr.cb.count + yuvA.ycbcr.cr.count + yuvA.a.count)

        data.append(contentsOf: yuvA.ycbcr.y)
        data.append(contentsOf: yuvA.ycbcr.cb)
        data.append(contentsOf: yuvA.ycbcr.cr)
        data.append(contentsOf: yuvA.a)

        #expect(data == fixture)
      }
    }
  }
}

@Test
func decodeLossyAlpha02() async throws {
  let testcases = [
    "alpha_filter_0_method_0",
    "alpha_filter_0_method_1",
    "alpha_filter_1_method_0",
    "alpha_filter_1_method_1",
    "alpha_filter_1",
    "alpha_filter_2_method_0",
    "alpha_filter_2_method_1",
    "alpha_filter_2",
    "alpha_filter_3_method_0",
    "alpha_filter_3_method_1",
    "alpha_filter_3",
    "alpha_no_compression",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(_):
        fatalError()
      case .nycbcra(let yuvA):
        var data = Data(capacity: yuvA.ycbcr.y.count + yuvA.ycbcr.cb.count + yuvA.ycbcr.cr.count + yuvA.a.count)

        data.append(contentsOf: yuvA.ycbcr.y)
        data.append(contentsOf: yuvA.ycbcr.cb)
        data.append(contentsOf: yuvA.ycbcr.cr)
        data.append(contentsOf: yuvA.a)

        #expect(data == fixture)
      }
    }
  }
}

@Test
func decodeLossyAlpha03() async throws {
  let testcases = [
    "lossy_alpha1",
    "lossy_alpha2",
    "lossy_alpha3",
    "lossy_alpha4",
    "yellow_rose.lossy-with-alpha",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(_):
        fatalError()
      case .nycbcra(let yuvA):
        var data = Data(capacity: yuvA.ycbcr.y.count + yuvA.ycbcr.cb.count + yuvA.ycbcr.cr.count + yuvA.a.count)

        data.append(contentsOf: yuvA.ycbcr.y)
        data.append(contentsOf: yuvA.ycbcr.cb)
        data.append(contentsOf: yuvA.ycbcr.cr)
        data.append(contentsOf: yuvA.a)

        #expect(data == fixture)
      }
    }
  }
}

@Test
func decodeLossyAlpha04() async throws {
  let testcases = [
    "1",
    "2",
    "3",
    "4",
    "5",
    "1_webp_a",
    "2_webp_a",
    "3_webp_a",
    "4_webp_a",
    "5_webp_a",
  ]

  let resources = Bundle.module.url(forResource: "Resources/VP8", withExtension: nil)!
  for tc in testcases {
    let data = try Data(contentsOf: resources.appendingPathComponent("\(tc).webp"))

    let image = try WebPDecoder.decode(data)
    let cgImage = image.makeCGImage()
    _ = try #require(cgImage)

    let fixture = try Data(contentsOf: resources.appendingPathComponent("\(tc).bin"))
    image.withUnsafePlanes { (planes) in
      switch planes {
      case .nrgba(_):
        fatalError()
      case .ycbcr(let yuv):
        var data = Data(capacity: yuv.y.count + yuv.cb.count + yuv.cr.count)
        data.append(contentsOf: yuv.y)
        data.append(contentsOf: yuv.cb)
        data.append(contentsOf: yuv.cr)
        #expect(data == fixture)
      case .nycbcra(let yuvA):
        var data = Data(capacity: yuvA.ycbcr.y.count + yuvA.ycbcr.cb.count + yuvA.ycbcr.cr.count + yuvA.a.count)

        data.append(contentsOf: yuvA.ycbcr.y)
        data.append(contentsOf: yuvA.ycbcr.cb)
        data.append(contentsOf: yuvA.ycbcr.cr)
        data.append(contentsOf: yuvA.a)

        #expect(data == fixture)
      }
    }
  }
}

@Test
func decodeTestImage() async throws {
  let imageUrl = URL(fileURLWithPath: "/Users/katsumi/Documents/transforms_composite.webp")
  let data = try Data(contentsOf: imageUrl)

  let image = try WebPDecoder.decode(data)
  let cgImage = image.makeCGImage()
  _ = try #require(cgImage)
}
