import UIKit

/// A document's edition: its texts, typeset for each look a reader can take.
/// Shared by all readers of the document.
final class Edition {
  let texts: Versions
  /// For a document that was imported, what it takes to set it out.
  let book: ImportedBook?
  /// For one that came with the app, the paper its paragraphs are set into.
  let manuscript: Manuscript?
  /// The width of a page.
  private(set) var width: CGFloat = 668
  /// Changes whenever the layouts do, so paragraphs know to redraw.
  private(set) var version = 0
  /// The plain and paper looks share one setting of the text; the journal has its own.
  private var sets: [ReadingStyle: Typeset] = [:]

  init(_ texts: Versions, book: ImportedBook? = nil, manuscript: Manuscript? = nil) {
    self.texts = texts
    self.book = book
    self.manuscript = manuscript
  }

  /// What a reader opens in, before it's been told otherwise: the paper, wherever there is one.
  var startingLook: ReadingStyle { book?.look ?? (texts.looks.contains(.paper) ? .paper : texts.looks[0]) }

  /// What each note marked in the text is labelled.
  var noteLabels: [Int: String] { book?.noteLabels ?? manuscript?.noteLabels ?? [:] }

  /// What a note says, set to be read over the page when its mark is tapped.
  func noteText(_ id: Int, traits: UITraitCollection) -> NSAttributedString? {
    if let book { return book.noteText(id, traits: traits) }
    guard let note = manuscript?.notes[id] else { return nil }
    return Press(style: .paper, sheet: .notes).typed(
      note.text, math: true, literal: false, labels: [:], size: NoteTip.textSize, leading: NoteTip.leading, traits: traits)
  }

  /// What a note says, for VoiceOver.
  func spokenNote(_ id: Int) -> String? {
    if let book { return book.spokenNote(id) }
    return manuscript?.notes[id].map { $0.text.replacingOccurrences(of: "$", with: "") }
  }

  /// What a look is called in this text.
  func name(_ style: ReadingStyle) -> String {
    book != nil && style == .journal ? ImportedBook.originalName : style.name
  }

  var cMax: Int { texts.cMax }
  var zMax: Int { texts.zMax }

  /// Fits the texts to a page `width` wide; true if any typesetting changed.
  @discardableResult
  func measure(width: CGFloat) -> Bool {
    func faces(_ w: CGFloat) -> [Double] {
      [Sheet.plain(w), Sheet.journal(w)].flatMap { [Double($0.fontSize), $0.column] }
    }
    let changed = faces(width) != faces(self.width)
    self.width = width
    if changed {
      sets = [:]
      version += 1
    }
    return changed
  }

  func sheet(_ style: ReadingStyle) -> Sheet {
    style == .journal ? (book?.magazineSheet(width) ?? .journal(width)) : .plain(width)
  }

  func typeset(_ style: ReadingStyle) -> Typeset {
    let key: ReadingStyle = style == .journal ? .journal : .plain
    if let t = sets[key] { return t }
    let s = sheet(key)
    let t: Typeset
    if let book {
      // Text found in a document may hold dollar signs that are only dollar signs.
      let plain = Typesetter(fontSize: s.fontSize, column: CGFloat(s.column), math: false)
      t = Typeset(texts, plain) { [weak book] i in
        guard let book else { return plain }
        return key == .journal ? book.magazineSetter(i, sheet: s) : book.cleanSetter(i, sheet: s)
      }
    } else {
      let notes = manuscript?.noteLabels ?? [:]
      let setter =
        key == .journal
        ? Typesetter(
          fontSize: s.fontSize, column: CGFloat(s.column), serif: true, leading: 1.3, justify: true, indent: s.fontSize, notes: notes)
        : Typesetter(fontSize: s.fontSize, column: CGFloat(s.column), notes: notes)
      t = Typeset(texts, setter)
    }
    sets[key] = t
    return t
  }
}
