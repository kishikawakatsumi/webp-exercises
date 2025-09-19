struct DecNode {
  var left:  Int? = nil
  var right: Int? = nil
  var sym: Int? = nil
}

func buildCLDecodingTree(from clCodeLengths: [UInt32], maxLen: Int = 7) -> [DecNode] {
  var blCount = [Int](repeating: 0, count: maxLen + 1)
  for L in clCodeLengths {
    if L > 0 {
      blCount[Int(L)] += 1
    }
  }

  var firstCode = [UInt32](repeating: 0, count: maxLen + 1)
  if maxLen >= 2 {
    for L in 2...maxLen {
      firstCode[L] = (firstCode[L - 1] + UInt32(blCount[L - 1])) << 1
    }
  }

  var pairs: [(len:Int, sym:Int)] = []
  for (sym, L) in clCodeLengths.enumerated() where L > 0 {
    pairs.append( (Int(L), sym) )
  }
  pairs.sort {
    (a,b) in a.len == b.len ? a.sym < b.sym : a.len < b.len
  }

  var nodes: [DecNode] = [DecNode()]
  func newNode() -> Int {
    nodes.append(DecNode())
    return nodes.count - 1
  }

  var nextPerLen = firstCode
  for (len, sym) in pairs {
    let codeMSB = nextPerLen[len]
    nextPerLen[len] &+= 1
    print(bitString(UInt64(codeMSB), len: len))

    var v = codeMSB
    var rev: UInt32 = 0
    for _ in 0..<len {
      rev = (rev << 1) | (v & 1)
      v >>= 1
    }

    var idx = 0
    for i in 0..<len {
      let bit = (rev >> i) & 1
      if bit == 0 {
        if nodes[idx].left == nil {
          nodes[idx].left = newNode()
        }
        idx = nodes[idx].left!
      } else {
        if nodes[idx].right == nil {
          nodes[idx].right = newNode()
        }
        idx = nodes[idx].right!
      }
    }
    nodes[idx].sym = sym 
  }
  return nodes
}
