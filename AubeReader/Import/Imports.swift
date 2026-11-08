import PDFKit
import UIKit
import UniformTypeIdentifiers

// ─── The imported documents ──────────────────────────────────────────────────

/// A document in the library that came from the reader's own files.
struct ImportEntry: Codable, Equatable {
  enum Stage: String, Codable {
    case queued, reading, understanding, checking, done, failed, locked
  }

  var id: String
  var fileName: String
  var title: String
  var authors: [String] = []
  var added = Date()
  var stage = Stage.queued
  /// Why it failed.
  var problem: String?
  /// Whether there's a document to read yet: it can be opened while it's still being checked.
  var readable = false
  /// How the check came out.
  var report: ImportReport.State = .pending
  /// The format what's been made of it was kept in. Older ones get read again.
  var format = 0
}

/// Every imported document, on disk, and the work of bringing new ones in.
/// One is brought in at a time. Each lives in a folder of its own, in
/// Application Support/Imports: the original, and what was made of it.
@MainActor
final class Imports {
  static let shared = Imports()

  private(set) var entries: [ImportEntry] = []
  /// How far along each document underway is: what's being done, and how much of it, from 0 to 1.
  private(set) var progress: [String: (said: String, done: Double)] = [:]

  /// The list of documents changed.
  var onChange: (() -> Void)?
  /// A document's progress changed.
  var onProgress: ((String) -> Void)?
  /// What's been made of a document changed.
  var onDocument: ((String) -> Void)?

  private var books: [String: ImportedBook] = [:]
  private var worker: Task<Void, Never>?
  private var checking: [String: Task<Void, Never>] = [:]
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  static var root: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Imports", isDirectory: true)
  }

  static func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
  static func original(_ id: String, _ fileName: String) -> URL { folder(id).appendingPathComponent("original." + (fileName as NSString).pathExtension.lowercased()) }
  private static func docFile(_ id: String) -> URL { folder(id).appendingPathComponent("document.json") }
  private static var indexFile: URL { root.appendingPathComponent("index.json") }

  private init() {
    if let data = try? Data(contentsOf: Self.indexFile), let list = try? JSONDecoder().decode([ImportEntry].self, from: data) {
      entries = list
    }
  }

  /// What the library shows.
  var documents: [Document] {
    entries.map { Document(id: $0.id, title: $0.title, authors: $0.authors, imported: true) }
  }

  func entry(_ id: String) -> ImportEntry? { entries.first { $0.id == id } }

  /// Picks up what was underway when the app last stopped.
  func resume() {
    var changed = false
    for i in entries.indices where [.reading, .understanding, .checking].contains(entries[i].stage) {
      entries[i].stage = entries[i].readable ? .checking : .queued
      changed = true
    }
    // What was made of it under an older version of the app is read again.
    for i in entries.indices where entries[i].readable && entries[i].format != ImportedDoc.format {
      entries[i].readable = false
      entries[i].stage = .queued
      changed = true
    }
    if changed { save() }
    pump()
    for e in entries where e.stage == .checking { startCheck(e.id) }
  }

  // ─── Coming in ───────────────────────────────────────────────────────────

  /// Takes copies of `urls` and starts on them. Files the app can't read are
  /// reported by the book they leave in the library, so nothing just vanishes.
  @discardableResult
  func add(_ urls: [URL]) -> [String] {
    var ids: [String] = []
    for url in urls {
      let id = "import-" + Store.newId()
      let name = url.lastPathComponent
      var e = ImportEntry(id: id, fileName: name, title: (name as NSString).deletingPathExtension)
      do {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: Self.folder(id), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: Self.original(id, name))
      } catch {
        e.stage = .failed
        e.problem = "The file couldn’t be copied: \(error.localizedDescription)"
      }
      entries.append(e)
      ids.append(id)
    }
    save()
    onChange?()
    pump()
    return ids
  }

  /// Tries a document again after it failed.
  func retry(_ id: String) {
    guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
    entries[i].stage = .queued
    entries[i].problem = nil
    save()
    onChange?()
    pump()
  }

  /// Opens a locked document with `password`: true if it fits. What's kept from
  /// then on is an unlocked copy, in the app's own folder.
  func unlock(_ id: String, password: String) -> Bool {
    guard let e = entry(id), let pdf = PDFDocument(url: Self.original(id, e.fileName)), pdf.unlock(withPassword: password) else { return false }
    let file = Self.original(id, e.fileName)
    let temp = file.appendingPathExtension("open")
    // Written as it stands, it would come out locked again. Its pages, moved into a new document, don't.
    let open = PDFDocument()
    for i in 0..<pdf.pageCount {
      if let page = pdf.page(at: i)?.copy() as? PDFPage { open.insert(page, at: open.pageCount) }
    }
    guard open.pageCount == pdf.pageCount, open.write(to: temp), (try? FileManager.default.replaceItemAt(file, withItemAt: temp)) != nil else { return false }
    retry(id)
    return true
  }

  /// Takes a document out of the library, with everything made of it.
  func remove(_ id: String) {
    checking[id]?.cancel()
    checking[id] = nil
    books[id] = nil
    entries.removeAll { $0.id == id }
    progress[id] = nil
    try? FileManager.default.removeItem(at: Self.folder(id))
    let rewritten = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Rewritten/\(id).json")
    try? FileManager.default.removeItem(at: rewritten)
    Store.forgetReading(id)
    save()
    onChange?()
  }

  private func save() {
    let list = entries
    let file = Self.indexFile
    DispatchQueue.global(qos: .utility).async {
      guard let data = try? JSONEncoder().encode(list) else { return }
      try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
    }
  }

  private func update(_ id: String, _ change: (inout ImportEntry) -> Void) {
    guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
    change(&entries[i])
    save()
    onChange?()
  }

  private func say(_ id: String, _ words: String, _ done: Double) {
    progress[id] = (words, done)
    onProgress?(id)
  }

  // ─── What's been made of them ────────────────────────────────────────────

  /// A document as it's been read, set out for the reader. Nil until it can be opened.
  func book(_ id: String) -> ImportedBook? {
    if let b = books[id] { return b }
    guard let e = entry(id), e.readable, let doc = load(id) else { return nil }
    let b = ImportedBook(doc, file: Self.original(id, e.fileName))
    books[id] = b
    return b
  }

  private func load(_ id: String) -> ImportedDoc? {
    guard let data = try? Data(contentsOf: Self.docFile(id)) else { return nil }
    return try? JSONDecoder().decode(ImportedDoc.self, from: data)
  }

  /// Keeps `doc` as what's been made of its document, and lets the desk know.
  func store(_ doc: ImportedDoc) {
    let file = Self.docFile(doc.id)
    if let data = try? JSONEncoder().encode(doc) {
      try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: file, options: .atomic)
    }
    books[doc.id] = nil
    update(doc.id) {
      $0.title = doc.title
      $0.authors = doc.authors
      $0.report = doc.report.state
      $0.format = doc.format
    }
    onDocument?(doc.id)
  }

  // ─── The work ────────────────────────────────────────────────────────────

  private func pump() {
    guard worker == nil, let next = entries.first(where: { $0.stage == .queued }) else {
      endBackground()
      return
    }
    beginBackground()
    worker = Task { [weak self] in
      await self?.read(next)
      self?.worker = nil
      self?.pump()
    }
  }

  private func read(_ entry: ImportEntry) async {
    let id = entry.id
    let file = Self.original(id, entry.fileName)
    update(id) { $0.stage = .reading }
    say(id, "Reading", 0)
    let outcome: Result<ImportedDoc, DocumentReader.Trouble> = await Task.detached(priority: .userInitiated) {
      Result {
        try DocumentReader.read(file: file, id: id, fileName: entry.fileName) { said, done in
          Task { @MainActor in self.say(id, said, done) }
        }
      }.mapError { ($0 as? DocumentReader.Trouble) ?? .unreadable($0.localizedDescription) }
    }.value
    guard self.entry(id) != nil else { return }
    switch outcome {
    case let .success(doc):
      update(id) {
        $0.readable = true
        $0.stage = .checking
      }
      store(doc)
      startCheck(id)
    case .failure(.locked):
      update(id) {
        $0.stage = .locked
        $0.problem = "This PDF is locked with a password."
      }
    case let .failure(.unreadable(why)):
      update(id) {
        $0.stage = .failed
        $0.problem = why
      }
    }
    progress[id] = nil
    onProgress?(id)
  }

  /// Has the model look over what was made of a document, and put right what it can.
  func startCheck(_ id: String) {
    guard checking[id] == nil, let e = entry(id), e.readable, let doc = load(id) else { return }
    beginBackground()
    update(id) { $0.stage = .checking }
    checking[id] = Task { [weak self] in
      guard let self else { return }
      let inspector = Inspector(doc, file: Self.original(id, e.fileName)) { [weak self] said, done in
        self?.say(id, said, done)
      } onImproved: { [weak self] better in
        self?.store(better)
      }
      let final = await inspector.run()
      guard !Task.isCancelled, self.entry(id) != nil else { return }
      self.store(final)
      self.checking[id] = nil
      self.progress[id] = nil
      self.update(id) { $0.stage = .done }
      self.onProgress?(id)
      self.pump()
    }
  }

  /// A document being brought in keeps going for the moments iOS allows after the app leaves the screen.
  private func beginBackground() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Importing") { [weak self] in self?.endBackground() }
  }

  private func endBackground() {
    guard backgroundTask != .invalid, worker == nil, checking.isEmpty else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}

// ─── Reading a file ──────────────────────────────────────────────────────────

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
          raw.append(RawPage(index: i, size: CGSize(width: 612, height: 792)))
          return
        }
        var r = PageReader.read(page, index: i, catalog: catalog)
        if needsEyes(r) {
          said("Reading page \(i + 1) by eye", Double(i) / Double(count))
          if let picture = PagePicture.make(page, pixels: 2200) {
            PageOCR.read(&r, picture: picture, plain: catalog.stand(FontNames.record("", flags: 2, weight: 0, angle: 0)))
            ScanFigures.find(&r, picture: picture)
          }
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
