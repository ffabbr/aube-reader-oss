import PDFKit
import UIKit
import Vision

/// Reads a page that has no usable text from a picture of it, on the device.
enum PageOCR {
  static func read(_ raw: inout RawPage, picture: CGImage, plain: Int) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    let handler = VNImageRequestHandler(cgImage: picture, options: [:])
    guard (try? handler.perform([request])) != nil, let lines = request.results, !lines.isEmpty else { return }
    let size = raw.size
    func place(_ b: CGRect) -> CGRect {
      CGRect(x: b.minX * size.width, y: (1 - b.maxY) * size.height, width: b.width * size.width, height: b.height * size.height)
    }
    var runs: [RawRun] = []
    // The boxes come out a little taller or shorter from line to line, which isn't a change
    // of type. Lines near the page's usual height are given just that height.
    let heights = lines.map { place($0.boundingBox).height }.sorted()
    let usual = heights.isEmpty ? 10 : heights[heights.count / 2]
    for line in lines {
      guard let best = line.topCandidates(1).first else { continue }
      let string = best.string
      let box = place(line.boundingBox)
      // Taller than it's wide, with words in it, it runs sideways: a stamp, a rotated label.
      if box.height > box.width * 1.5, string.count > 4 {
        raw.sideways.append(box)
        continue
      }
      let em = max((abs(box.height - usual) < usual * 0.3 ? usual : box.height) * 0.85, 3)
      var words: [RawWord] = []
      string.enumerateSubstrings(in: string.startIndex..., options: [.byWords, .substringNotRequired]) { _, range, _, _ in
        // Words carry their punctuation, as the text layer's would.
        var end = range.upperBound
        while end < string.endIndex, !string[end].isWhitespace, !string[end].isLetter, !string[end].isNumber { end = string.index(after: end) }
        let word = string[range.lowerBound..<end]
        let rect = (try? best.boundingBox(for: range.lowerBound..<end)).flatMap { $0 }.map { place($0.boundingBox) } ?? box
        words.append(RawWord(text: String(word), rect: rect, size: em, font: plain, color: .black))
      }
      if words.isEmpty { words = [RawWord(text: string, rect: box, size: em, font: plain, color: .black)] }
      runs.append(RawRun(words: words, rect: box, baseline: box.maxY - em * 0.2, size: em, font: plain, color: .black))
    }
    raw.runs = runs
    raw.ocr = true
    raw.garbled = false
  }
}

extension PageOCR {
  /// How wide, in pixels, a page is drawn to be read by eye.
  static let pixels = 2200

  /// Reads `page` by eye, as `read` does, into `raw`, and finds the pictures
  /// on it; first throwing away the text it has, if `discardingText`. Text read
  /// this way is set in a plain serif. False if the page couldn't be drawn.
  @discardableResult
  static func readByEye(_ raw: inout RawPage, page: PDFPage, catalog: FontCatalog, discardingText: Bool = false) -> Bool {
    guard let picture = PagePicture.make(page, pixels: pixels) else { return false }
    if discardingText { raw.runs = [] }
    // Flag 2 is a PDF font descriptor's "serif".
    read(&raw, picture: picture, plain: catalog.stand(FontNames.record("", flags: 2, weight: 0, angle: 0)))
    ScanFigures.find(&raw, picture: picture)
    return true
  }
}
