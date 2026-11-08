import PDFKit
import UIKit
import os

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
  private static let log = Logger(subsystem: "aube-reader", category: "imports")
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
    Disk.support.appendingPathComponent("Imports", isDirectory: true)
  }

  static func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
  static func original(_ id: String, _ fileName: String) -> URL { folder(id).appendingPathComponent("original." + (fileName as NSString).pathExtension.lowercased()) }
  private static func docFile(_ id: String) -> URL { folder(id).appendingPathComponent("document.json") }
  private static var indexFile: URL { root.appendingPathComponent("index.json") }

  private init() {
    guard let data = try? Data(contentsOf: Self.indexFile) else { return }
    do {
      entries = try JSONDecoder().decode([ImportEntry].self, from: data)
    } catch {
      // Kept aside, rather than lost to the next save, so the documents can still be found.
      Self.log.error("The list of imports couldn't be read: \(error.localizedDescription, privacy: .public)")
      Disk.write(data, to: Self.indexFile.appendingPathExtension("unreadable"))
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

  /// Whether documents can be brought in at all: it takes the model.
  static var canImport: Bool { OpenAI.available }

  /// Why nothing can be brought in without the model, for an alert.
  static let needsKeyTitle = "Importing Takes AI"
  static let needsKeyMessage = "Bringing in a document takes OpenAI’s models. Sign in with ChatGPT or enter an OpenAI API key in Settings."

  /// Takes copies of `urls` and starts on them. Files the app can't read are
  /// reported by the book they leave in the library, so nothing just vanishes.
  /// Without the model nothing is taken; callers say why first.
  @discardableResult
  func add(_ urls: [URL]) -> [String] {
    guard Self.canImport else { return [] }
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
    try? FileManager.default.removeItem(at: LiveText.file(for: id))
    Store.forgetReading(id)
    save()
    onChange?()
  }

  private func save() {
    let list = entries
    let file = Self.indexFile
    DispatchQueue.global(qos: .utility).async {
      Disk.writeJSON(list, to: file)
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
    Disk.writeJSON(doc, to: file)
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
