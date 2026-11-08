import Foundation

/// A document whose paragraphs are each written once, at one point of the
/// grid (level 3, length 3 on `Scale`), and rewritten by the model into every
/// other version as the reader comes near it. Every version written is kept,
/// on disk, so it's only ever written once.
final class LiveText: Versions {
  /// What the app ships for a live document: one version of each paragraph.
  struct Source: Decodable {
    let title: String
    let authors: [String]
    /// What the document is about, so the levels' "in the field" means something.
    let field: String
    let paragraphs: [String]
    /// For a document found rather than written to measure, which runs to any
    /// length and level: each paragraph's level as found, and its ladder of lengths.
    var levels: [Int]?
    var ladders: [[Int]]?
    /// Its language, where that's known. Levels are measured only in English.
    var language: String?
  }

  struct Key: Hashable {
    let p: Int
    let c: Int
    let z: Int
  }

  let id: String
  let source: Source
  private(set) lazy var rewriter = Rewriter(self)

  var count: Int { source.paragraphs.count }
  var cMax: Int { Scale.levels - 1 }
  var zMax: Int { Scale.lengths.count - 1 }
  let defaultDifficulty = Scale.middle
  let defaultZoom = 3
  var coreCount: Int { count }
  /// By default only plain prose; a document that was imported has what it needs for the others.
  var looks: [ReadingStyle] = [.plain]

  func home(_ p: Int) -> (c: Int, z: Int) { (source.levels?[safe: p] ?? defaultDifficulty, defaultZoom) }

  /// How many words version `z` of paragraph `p` should run to.
  func length(_ p: Int, _ z: Int) -> Int { source.ladders?[safe: p]?[safe: z] ?? Scale.lengths[z] }

  /// How far from that it may run: under half a step, so neighbors never overlap.
  func slack(_ p: Int, _ z: Int) -> Int {
    guard source.ladders != nil else { return Scale.lengthSlack }
    return max(Scale.lengthSlack, length(p, z) / 8)
  }

  /// Whether the measure of grade means anything for this text.
  var graded: Bool { source.language.map { $0.hasPrefix("en") } ?? true }

  /// Versions written so far, besides the originals.
  private var written: [Key: String] = [:]
  /// Versions being written: the words so far, and how many words their placeholders stand for.
  private var writing: [Key: (text: String, skeleton: Int)] = [:]
  private var revisions: [Key: Int] = [:]
  /// Called whenever a draft changes: which one, or nil for all of them.
  var onChange: ((Key?) -> Void)?
  private var saving: DispatchWorkItem?

  init(id: String, source: Source) {
    self.id = id
    self.source = source
    load()
  }

  func draft(_ p: Int, _ c: Int, _ z: Int) -> Draft {
    let key = Key(p: p, c: c, z: z)
    let revision = revisions[key] ?? 0
    if let text = text(key) { return Draft(text: text, skeleton: nil, revision: revision) }
    if let w = writing[key] { return Draft(text: w.text, skeleton: w.skeleton, revision: revision) }
    return Draft(text: "", skeleton: length(p, z), revision: revision)
  }

  /// A version that's written: an original, or one written before.
  func text(_ key: Key) -> String? {
    let h = home(key.p)
    return key.c == h.c && key.z == h.z ? source.paragraphs[key.p] : written[key]
  }

  /// Every version of paragraph `p` that's written, the original among them.
  func versions(of p: Int) -> [(key: Key, text: String)] {
    let h = home(p)
    return [(Key(p: p, c: h.c, z: h.z), source.paragraphs[p])]
      + written.filter { $0.key.p == p }.map { ($0.key, $0.value) }
  }

  /// Shows a version as it's being written: `text` so far, over placeholders for `skeleton` words.
  func show(_ key: Key, _ text: String, skeleton: Int) {
    guard self.text(key) == nil else { return }
    writing[key] = (text, skeleton)
    changed(key)
  }

  /// Drops what's shown of a version that couldn't be written, back to placeholders.
  func drop(_ key: Key) {
    guard writing.removeValue(forKey: key) != nil else { return }
    changed(key)
  }

  /// Keeps a version once it's written.
  func keep(_ key: Key, _ text: String) {
    writing[key] = nil
    written[key] = text
    changed(key)
    save()
  }

  /// Forgets every version written, so each is written afresh when next wanted.
  func forget() {
    for key in Set(written.keys).union(writing.keys) { revisions[key, default: 0] += 1 }
    written = [:]
    writing = [:]
    onChange?(nil)
    save()
  }

  private func changed(_ key: Key) {
    revisions[key, default: 0] += 1
    onChange?(key)
  }

  // ─── On disk ─────────────────────────────────────────────────────────────

  /// Each paragraph's versions, beside the original they were written from:
  /// if the original changes, they no longer belong to it.
  private struct Saved: Codable {
    var original: String
    /// "difficulty,zoom" → text
    var versions: [String: String]
  }

  private var file: URL {
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      // Versions written for the eleven levels there once were don't belong to the six there are now.
      .appendingPathComponent("Rewritten-\(Scale.levels)", isDirectory: true)
    return folder.appendingPathComponent("\(id).json")
  }

  private func load() {
    guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Saved].self, from: data) else {
      return
    }
    for (p, s) in saved.enumerated() where p < count && s.original == source.paragraphs[p] {
      for (cell, text) in s.versions {
        let n = cell.split(separator: ",").compactMap { Int($0) }
        guard n.count == 2, n[0] >= 0, n[0] <= cMax, n[1] >= 0, n[1] <= zMax else { continue }
        written[Key(p: p, c: n[0], z: n[1])] = text
      }
    }
  }

  /// Writes the versions to disk a moment after the last change, away from the main thread.
  private func save() {
    saving?.cancel()
    var saved = source.paragraphs.map { Saved(original: $0, versions: [:]) }
    for (key, text) in written { saved[key.p].versions["\(key.c),\(key.z)"] = text }
    let file = self.file
    let work = DispatchWorkItem {
      DispatchQueue.global(qos: .utility).async {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
      }
    }
    saving = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
  }

  /// Writes anything not yet on disk at once.
  func saveNow() {
    saving?.perform()
    saving = nil
  }
}
