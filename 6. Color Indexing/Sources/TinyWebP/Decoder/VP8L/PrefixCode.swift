// ========== 1) カノニカル → （LSB-firstで読める）単純な木を作る ==========

/// 1ノード（左右の子と、葉なら symbolID）
struct DecNode {
  var left:  Int? = nil
  var right: Int? = nil
  var sym:   Int? = nil
}

/// カノニカルの「コード長配列」(len[sym]) から
/// ・blCount（長さごとの個数）
/// ・firstCode（各長さの最初のコード値, MSB基準）
/// ・MSBコードを LSB順に反転して木へ挿入（←デコーダはLSB-firstで読むため）
func buildCLDecodingTree(from clCodeLengths: [UInt32], maxLen: Int = 7) -> [DecNode] {
  // bl_count[len]
  var blCount = [Int](repeating: 0, count: maxLen + 1)
  for L in clCodeLengths {
    if L > 0 {
      blCount[Int(L)] += 1
    }
  }

  // first_code[len]（MSB基準）
  var firstCode = [UInt32](repeating: 0, count: maxLen + 1)
  if maxLen >= 2 {
    for L in 2...maxLen {
      firstCode[L] = (firstCode[L - 1] + UInt32(blCount[L - 1])) << 1
    }
  }

  // （len, sym）で安定ソート → 同じ長さ内は ID 昇順
  var pairs: [(len:Int, sym:Int)] = []
  for (sym, L) in clCodeLengths.enumerated() where L > 0 {
    pairs.append( (Int(L), sym) )
  }
  pairs.sort {
    (a,b) in a.len == b.len ? a.sym < b.sym : a.len < b.len
  }

  // 単純な配列ベース木：index 0 が根
  var nodes: [DecNode] = [DecNode()] // root だけ
  func newNode() -> Int {
    nodes.append(DecNode())
    return nodes.count - 1
  }

  // 反転（MSB→LSB）して木へ挿す
  var nextPerLen = firstCode
  for (len, sym) in pairs {
    let codeMSB = nextPerLen[len]
    nextPerLen[len] &+= 1
    print(bitString(UInt64(codeMSB), len: len))

    // MSBコードを “len ビット分だけ” LSB順に反転
    var v = codeMSB
    var rev: UInt32 = 0
    for _ in 0..<len {
      rev = (rev << 1) | (v & 1)
      v >>= 1
    }

    // LSB-firstで 0→左, 1→右 に降りて葉を作る
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
    nodes[idx].sym = sym  // 葉
  }
  return nodes
}
