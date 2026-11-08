import UIKit

/// A paper's own words around its paragraphs: its title page, its sections,
/// what each section sets after its text, and its references. One to each
/// document that comes with the app.
struct Manuscript {
  struct Section {
    let title: String
    /// 1 for a section, 2 for a subsection, 3 for one within that.
    var level = 1
    /// Whether it's numbered: an appendix isn't.
    var numbered = true
    /// Its paragraphs (by index in the text), shown in every look. A section
    /// that opens straight onto its subsections has none of its own.
    var paragraphs: [Int] = []
    /// What it sets after them.
    var after: [Extra] = []
    /// What it sets straight after one of its paragraphs, rather than after them all.
    var within: [Int: [Extra]] = [:]
    /// Further paragraphs that only the journal page sets.
    var more: [Int] = []
  }

  struct Table {
    let caption: String
    let header: [String]
    let rows: [[String]]
    /// Headings over runs of columns, above the header: a title, and the first and last columns it spans.
    var over: [(title: String, from: Int, to: Int)] = []
    /// The rows a rule is drawn above, setting off groups of them.
    var breaks: Set<Int> = []
    /// Too wide for a column, so on a journal page of two it runs across both.
    var wide = false
  }

  /// A footnote: what it's marked with, and what it says (with `$…$` formulas and the markup `Press.rich` reads).
  struct Note {
    let label: String
    let text: String
  }

  /// The document it belongs to.
  let id: String
  let title: String
  let abstract: String
  let keywords: String
  let authors: [String]
  /// Which of `affiliations` each author belongs to, from 1.
  let places: [Int]
  /// Each place the authors work, short on the preprint and in full in the journal.
  let affiliations: [(short: String, full: String)]
  let received: String
  /// Over the preprint's title.
  let preprint: String
  /// The journal's name, volume and page, and its date, at the head of its page.
  let journal: String
  let date: String
  let doi: String
  /// At the foot of the journal page.
  let footer: (left: String, right: String)
  let sections: [Section]
  var captions: [Figure: String] = [:]
  /// Its tables, by number from 0 (see `Extra.table`).
  var tables: [Table] = []
  let references: [String]
  /// Its footnotes, by the number marked in the text as `[^n]`.
  var notes: [Int: Note] = [:]
  /// The notes marked after each author's name.
  var authorNotes: [[Int]] = []
  var acknowledgements: String? = nil
  /// Whether the journal sets it out a page at a time, each page's columns
  /// filled before the next begins, with wide figures and tables between pages.
  /// A short paper is one page, its columns run the length of it.
  var paged = false

  static let roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

  /// The headings opening at paragraph `p`, outermost first: a section that opens straight
  /// onto a subsection opens where that does.
  func headings(at p: Int) -> [(title: String, level: Int)] {
    var out: [(String, Int)] = []
    for s in sections {
      if s.paragraphs.isEmpty, s.after.isEmpty {
        out.append((s.title, s.level))
        continue
      }
      if s.paragraphs.first == p { return out + [(s.title, s.level)] }
      out = []
    }
    return []
  }

  /// Each section's number as it's printed, "3.2.1" in the preprint and "III.B.1" by the journal's
  /// count; nil for one that isn't numbered.
  func numbers(journal: Bool) -> [String?] {
    var count = [0, 0, 0]
    return sections.map { s in
      guard s.numbered else { return nil }
      let l = min(max(s.level, 1), 3) - 1
      count[l] += 1
      for k in (l + 1)..<3 { count[k] = 0 }
      if journal {
        switch l {
        case 0: return Manuscript.roman[safe: count[0] - 1] ?? "\(count[0])"
        case 1: return String(UnicodeScalar(UInt8(64 + min(count[1], 26))))
        default: return "\(count[2])"
        }
      }
      return count[...l].map(String.init).joined(separator: ".")
    }
  }

  /// The labels of its notes, by number.
  var noteLabels: [Int: String] { notes.mapValues(\.label) }

  /// An author's affiliation and notes, set after their name.
  private func marks(_ i: Int) -> String {
    let place = places[safe: i].flatMap { $0 > 0 ? "^{\($0)}" : nil } ?? ""
    return place + (authorNotes[safe: i] ?? []).map { NoteToken.make($0) }.joined()
  }

  /// The authors as the preprint lists them, each marked with where they work.
  var byline: String {
    authors.indices.map { authors[$0] + marks($0) }.joined(separator: ", ")
  }

  /// The authors as the journal lists them.
  var journalByline: String {
    let marked = authors.indices.map { i in
      authors.count > 2 && i < authors.count - 1 ? "\(authors[i]),\(marks(i))" : authors[i] + marks(i)
    }
    guard marked.count > 1 else { return marked.joined() }
    return marked.dropLast().joined(separator: " ") + " and " + marked.last!
  }

  /// The manuscript of the document with `id`, if it has one.
  static func of(_ id: String) -> Manuscript? {
    [attention, gw150914, blackHoles, swarm].first { $0.id == id }
  }
}

/// What a section sets after its paragraphs.
enum Extra {
  case equation(String)
  case figure(Figure)
  /// Its table with this index in `Manuscript.tables`.
  case table(Int)
}
