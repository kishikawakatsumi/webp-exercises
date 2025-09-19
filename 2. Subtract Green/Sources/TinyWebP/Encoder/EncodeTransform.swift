func applySubtractGreenTransform(pixels: inout [NRGBA]) {
  for i in pixels.indices {
    pixels[i].r = pixels[i].r &- pixels[i].g
    pixels[i].b = pixels[i].b &- pixels[i].g
  }
}
