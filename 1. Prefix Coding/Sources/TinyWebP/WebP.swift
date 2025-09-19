enum WebPError: Error {
  case invalidFormat
  case staleReader
  case riff(_ err: RIFFError)
}

let lengthCodeOrder = [
  17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]
