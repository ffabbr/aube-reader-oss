import UIKit

/// Every version of every paragraph, laid out in one face as it's needed:
/// once for a version that's written, and again whenever one still being
/// written changes.
final class Typeset {
  let setter: Typesetter
  /// For a text whose paragraphs aren't all set alike.
  private let custom: ((Int) -> Typesetter)?
  private var setters: [Int: Typesetter] = [:]
  private let texts: Versions
  private var cells: [Cell: (revision: Int, layout: Layout)] = [:]
  /// Written versions that read the same are set once.
  private var memo: [String: Layout] = [:]
  private var trackCache: [Morph.Pair: (revisions: [Int], tracks: [Track])] = [:]
  /// Each paragraph's placeholders, in the order they stand in for its words.
  private var stand: [Int: [Glyphs]] = [:]

  private struct Cell: Hashable {
    let p: Int
    let c: Int
    let z: Int
  }

  init(_ texts: Versions, _ setter: Typesetter, custom: ((Int) -> Typesetter)? = nil) {
    self.texts = texts
    self.setter = setter
    self.custom = custom
  }

  /// How paragraph `pi` is set.
  func setter(_ pi: Int) -> Typesetter {
    guard let custom else { return setter }
    if let s = setters[pi] { return s }
    let s = custom(pi)
    setters[pi] = s
    return s
  }

  /// About how tall a version will be, without setting it: exact if it's been set.
  func height(_ pi: Int, _ v: (c: Int, z: Int)) -> Double {
    let d = texts.draft(pi, v.c, v.z)
    if let hit = cells[Cell(p: pi, c: v.c, z: v.z)], hit.revision == d.revision { return hit.layout.height }
    let chars = d.skeleton.map { $0 * 6 } ?? d.text.count
    return setter(pi).estimate(characters: chars)
  }

  func revision(_ pi: Int, _ v: (c: Int, z: Int)) -> Int { texts.draft(pi, v.c, v.z).revision }

  /// Whether two versions read the same, both written.
  func same(_ pi: Int, _ a: (c: Int, z: Int), _ b: (c: Int, z: Int)) -> Bool {
    let x = texts.draft(pi, a.c, a.z)
    let y = texts.draft(pi, b.c, b.z)
    return x.done && y.done && x.text == y.text
  }

  /// A version as written so far, over the placeholders it was expected to
  /// fill: those the words have reached give way to them, and the rest stay
  /// where they stood, so nothing moves as the words come in.
  func layout(_ pi: Int, _ v: (c: Int, z: Int)) -> Layout {
    let d = texts.draft(pi, v.c, v.z)
    let key = Cell(p: pi, c: v.c, z: v.z)
    if let hit = cells[key], hit.revision == d.revision { return hit.layout }
    let l: Layout
    let setter = setter(pi)
    // Paragraphs set alike can share what they read alike.
    let shared = custom == nil
    if let skeleton = d.skeleton {
      let text = setter.layout(d.text)
      let bars = setter.layout("", then: placeholders(pi, 0..<skeleton))
      let end = text.words.last.map { (y: $0.y, x: $0.x + Double($0.glyphs.width) + Double(setter.fontSize) * 0.3) }
      let rest = bars.words.filter { w in end.map { w.y > $0.y || (w.y == $0.y && w.x >= $0.x) } ?? true }
      l = Layout(words: text.words + rest, height: max(text.height, bars.height))
    } else if shared, let m = memo[d.text] {
      l = m
    } else {
      l = setter.layout(d.text)
      if shared { memo[d.text] = l }
    }
    cells[key] = (d.revision, l)
    return l
  }

  func tracks(_ pi: Int, _ m: Morph) -> [Track] {
    var key = m.pair
    key.paragraph = pi
    let revisions = [revision(pi, m.a), revision(pi, m.b)]
    if let t = trackCache[key], t.revisions == revisions { return t.tracks }
    let t = align(layout(pi, m.a).words, layout(pi, m.b).words)
    trackCache[key] = (revisions, t)
    return t
  }

  /// Placeholders `range` of paragraph `pi`, as long as English words run:
  /// mostly three to five letters, now and then ten or more.
  private func placeholders(_ pi: Int, _ range: Range<Int>) -> [Glyphs] {
    var all = stand[pi] ?? []
    if all.count < range.upperBound {
      let odds = [3, 17, 20, 16, 11, 9, 8, 6, 4, 3, 2, 1]
      // The same placeholders for the same paragraph, every time.
      var random = Seeded(UInt64(pi + 1) &* 0x9E37_79B9_7F4A_7C15)
      while all.count < range.upperBound {
        var roll = Int(random.next() % 100)
        var letters = 1
        for n in odds {
          if roll < n { break }
          roll -= n
          letters += 1
        }
        all.append(setter(pi).placeholder(letters, name: "\(pi).\(all.count)"))
      }
      stand[pi] = all
    }
    return Array(all[range])
  }
}
