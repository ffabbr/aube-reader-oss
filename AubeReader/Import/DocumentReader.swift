import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Turns a file into a document. Takes as long as it takes, off the main thread.
enum DocumentReader {
  enum Trouble: Error {
    case locked
    case unreadable(String)
  }

  /// `said` is told how far along it is, from any thread.
  static func read(file: URL, id: String, fileName: String, said: @escaping (String, Double) -> Void) throws -> ImportedDoc {
    let type = UTType(filenameExtension: file.pathExtension.lowercased())
    if type?.conforms(to: .pdf) == true { return try readPDF(file: file, id: id, fileName: fileName, said: said) }
    return try Flowing.read(file: file, id: id, fileName: fileName)
  }

  private static func readPDF(file: URL, id: String, fileName: String, said: @escaping (String, Double) -> Void) throws -> ImportedDoc {
    guard let pdf = PDFDocument(url: file) else {
      throw Trouble.unreadable("This file isn’t a PDF that can be opened. It may be damaged.")
    }
    if pdf.isLocked { throw Trouble.locked }
    let count = pdf.pageCount
    guard count > 0 else { throw Trouble.unreadable("This PDF has no pages.") }

    let catalog = FontCatalog()
    var raw: [RawPage] = []
    raw.reserveCapacity(count)
    for i in 0..<count {
      autoreleasepool {
        guard let page = pdf.page(at: i) else {
          raw.append(RawPage(size: DocPage.letter))
          return
        }
        var r = PageReader.read(page, catalog: catalog)
        if needsEyes(r) {
          said("Reading page \(i + 1) by eye", Double(i) / Double(count))
          PageOCR.readByEye(&r, page: page, catalog: catalog)
        }
        raw.append(r)
      }
      if i % 4 == 0 || i == count - 1 { said("Reading page \(i + 1) of \(count)", Double(i + 1) / Double(count)) }
    }

    said("Working out the layout", 1)
    let measure = DocMeasure.of(raw)
    let layouts = raw.map { PageAnalyzer.analyze($0, measure: measure, fonts: catalog.fonts) }
    let attributes = pdf.documentAttributes
    return Structure.document(
      id: id, fileName: fileName, pages: raw, layouts: layouts, fonts: catalog.fonts, measure: measure,
      metaTitle: attributes?[PDFDocumentAttribute.titleAttribute] as? String,
      metaAuthor: attributes?[PDFDocumentAttribute.authorAttribute] as? String, known: Spelling.known)
  }

  /// A page with no text that can be used, but with something on it: a scan, or text in a font that doesn't say what its letters are.
  static func needsEyes(_ r: RawPage) -> Bool {
    if r.garbled { return true }
    if r.scanned { return r.runs.flatMap(\.words).filter { !$0.hidden }.count < 8 && r.runs.isEmpty }
    let words = r.runs.reduce(0) { $0 + $1.words.count }
    return words < 3 && (r.shows > 3 || !r.marks.isEmpty)
  }
}

/// Whether a word mended across a line break is a word. Only in English, where a checker can say.
enum Spelling {
  static func known(_ word: String) -> Bool {
    // "152-" and "layer" were never one word.
    if word.contains(where: \.isNumber) { return false }
    guard word.count > 1, word.allSatisfy(\.isLetter) else { return true }
    return DispatchQueue.main.sync {
      let checker = UITextChecker()
      let range = NSRange(word.startIndex..., in: word)
      return checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: "en").location == NSNotFound
    }
  }
}
