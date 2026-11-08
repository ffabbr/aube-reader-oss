import UIKit

/// How a document is bound, settled once and for all by its id.
@MainActor
struct BookSpec {
  /// How tall a book is for its width, before each is made a little different.
  static let aspect: CGFloat = 1.42

  enum Design: Int, CaseIterable { case gilt, label, plate, paperback, parcel }
  enum Foil {
    case gold, silver, copper
    case ink(UInt32)

    var stops: [UInt32]? {
      switch self {
      case .gold: [0x7a5a20, 0xd2b166, 0xf6e7b4, 0xb78e3d, 0x866526, 0xe9d08a, 0x96752f]
      case .silver: [0x777a7c, 0xc9cccc, 0xf4f5f2, 0xa5a8a8, 0x7e8182, 0xdfe1df, 0x8a8d8d]
      case .copper: [0x7b4322, 0xc78a5c, 0xf2c8a2, 0xb0693c, 0x83472a, 0xdda67c, 0x8f5230]
      case .ink: nil
      }
    }
    var inkColor: UIColor? {
      if case let .ink(v) = self { return UIColor(hex: v) }
      return nil
    }
  }

  let id: String
  let title: String
  let authors: [String]
  let seed: UInt64
  let design: Design
  let cloth: UInt32
  let foil: Foil
  let size: CGSize
  let thickness: CGFloat
  /// How many times larger than `size` it's shown. It's drawn as a book of `size`
  /// with finer pixels, so lettering and rules grow in proportion to the cover.
  var magnified: CGFloat = 1
  var shownSize: CGSize { CGSize(width: (size.width * magnified).rounded(), height: (size.height * magnified).rounded()) }

  /// The bindings a book may have, as a real run of old library bindings.
  private static let bindings: [(UInt32, Foil)] = [
    (0x6a1b1f, .gold), (0x1c4433, .gold), (0x1a2c52, .gold), (0x47234a, .gold), (0x154f58, .gold), (0x1d1a18, .gold),
    (0x8a3518, .gold), (0x4b5427, .gold), (0x25406a, .silver), (0x28423c, .copper), (0x7b2233, .gold),
    (0xd3c5a6, .ink(0x2a2017)), (0x9d9a8c, .ink(0x1d1712)), (0xb98a33, .ink(0x2a1a0c)), (0x6f8a84, .ink(0x14201d)),
  ]
  private static let stocks: [UInt32] = [0xb5402b, 0x1f5f6a, 0xd2902a, 0x2a4c7d, 0x4d6b47, 0x7c2f46]

  /// What's been settled about a book's look.
  struct Choice {
    var design: Design
    var binding: Int
    var stock: Int
  }

  /// What a document would choose for itself.
  private static func preference(_ id: String) -> Choice {
    var rng = Seeded(steadyHash(id + "/choice-1"))
    let roll = rng(0...1)
    let design: Design = roll < 0.34 ? .gilt : roll < 0.6 ? .label : roll < 0.85 ? .plate : .paperback
    return Choice(design: design, binding: Int.random(in: 0..<bindings.count, using: &rng), stock: Int.random(in: 0..<stocks.count, using: &rng))
  }

  /// Goes along the library letting each book have what it would choose, unless
  /// the books just before it have that binding, or that design, already.
  static func plan(_ ids: [String]) -> [String: Choice] {
    var plan: [String: Choice] = [:]
    var bindingsLately: [Int] = []
    var stocksLately: [Int] = []
    var designsLately: [Design] = []
    let designs: [Design] = [.gilt, .label, .plate, .paperback]
    for id in ids {
      var c = preference(id)
      var tries = 0
      while designsLately.suffix(1).contains(c.design), tries < 4 {
        c.design = designs[(designs.firstIndex(of: c.design)! + 1) % designs.count]
        tries += 1
      }
      while bindingsLately.suffix(5).contains(c.binding) { c.binding = (c.binding + 1) % bindings.count }
      while stocksLately.suffix(2).contains(c.stock) { c.stock = (c.stock + 1) % stocks.count }
      if c.design == .paperback { stocksLately.append(c.stock) } else { bindingsLately.append(c.binding) }
      designsLately.append(c.design)
      plan[id] = c
    }
    return plan
  }

  init(_ d: Document, unit: CGFloat, openable: Bool, choice: Choice?) {
    id = d.id
    title = d.title
    authors = d.authors
    seed = steadyHash(d.id + "/binding-3")
    var rng = Seeded(seed)
    let choice = choice ?? Self.preference(d.id)
    design = openable ? choice.design : .parcel
    let binding = Self.bindings[choice.binding]
    cloth = design == .paperback ? Self.stocks[choice.stock] : binding.0
    foil = binding.1
    let w = unit * rng(0.94...1.07)
    let h = unit * Self.aspect * rng(0.93...1.05)
    size = CGSize(width: w.rounded(), height: h.rounded())
    var t = rng(20...38)
    if d.imported, let pages = Imports.shared.book(d.id)?.doc.pages.count {
      // A book as thick as it has pages.
      t = min(52, 15 + CGFloat(pages) * 0.42)
    }
    if design == .paperback { t *= 0.72 }
    thickness = t.rounded()
  }

  /// Identifies everything drawn for this book: a cover is drawn again only when it changes.
  var key: String { "\(id)|\(title)|\(design.rawValue)|\(size.width)x\(size.height)x\(thickness)x\(magnified)" }
}
