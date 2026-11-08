import Foundation

/// A word's journey through a morph: index in the old text, the new text, or both (-1 = absent).
struct Track {
  var a: Int
  var b: Int
}

/// Weighted longest-common-subsequence between two versions of a paragraph.
/// Shared words become a single track that slides from its old place to its new
/// one; everything else fades out or in. Function words count for less, so they
/// don't drag content words into long, confusing journeys across the paragraph.
func align(_ A: [Word], _ B: [Word]) -> [Track] {
  let n = A.count
  let m = B.count
  let w = m + 1
  var score = [Double](repeating: 0, count: (n + 1) * w)
  func gain(_ i: Int, _ j: Int) -> Double { A[i].key == B[j].key ? (A[i].stop ? 0.3 : 1) : 0 }

  if n > 0 && m > 0 {
    for i in stride(from: n - 1, through: 0, by: -1) {
      for j in stride(from: m - 1, through: 0, by: -1) {
        let g = gain(i, j)
        score[i * w + j] = max(
          score[(i + 1) * w + j],
          score[i * w + j + 1],
          g > 0 ? score[(i + 1) * w + j + 1] + g : 0
        )
      }
    }
  }

  var tracks: [Track] = []
  var i = 0
  var j = 0
  while i < n && j < m {
    let g = gain(i, j)
    if g > 0 && score[i * w + j] == score[(i + 1) * w + j + 1] + g {
      tracks.append(Track(a: i, b: j))
      i += 1
      j += 1
    } else if score[(i + 1) * w + j] >= score[i * w + j + 1] {
      tracks.append(Track(a: i, b: -1))
      i += 1
    } else {
      tracks.append(Track(a: -1, b: j))
      j += 1
    }
  }
  while i < n { tracks.append(Track(a: i, b: -1)); i += 1 }
  while j < m { tracks.append(Track(a: -1, b: j)); j += 1 }
  return tracks
}
