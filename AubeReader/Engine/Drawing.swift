import Foundation

/// A drawing in the library (`graphics/`, bundled as `svg/` and `index.json`).
struct Drawing: Decodable {
  let id: String
  let discipline: String
  let title: String
  let description: String
  let tags: [String]

  static let all: [Drawing] = {
    guard
      let url = Bundle.main.url(forResource: "index", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let all = try? JSONDecoder().decode([Drawing].self, from: data)
    else { return [] }
    return all
  }()

  /// The drawing itself: standalone SVG, its house style and animation baked in.
  var svg: String? {
    Bundle.main.url(forResource: id, withExtension: "svg", subdirectory: "svg").flatMap { try? String(contentsOf: $0) }
  }
}

extension Drawing {
  /// The drawings for which the answer to `question` about `input` is yes,
  /// likeliest first, as the model picks them from the whole list; none if it
  /// can't be asked.
  static func ranked(for input: String, asking question: String) async -> [Drawing] {
    guard OpenAI.available, !all.isEmpty else { return [] }
    let list = all.map { "\($0.id): \($0.title). \($0.description) (\($0.tags.joined(separator: ", ")))" }.joined(separator: "\n")
    let brief = """
      You choose drawings from a list. Ask of each drawing: \(question) Give the ids of up to eight \
      drawings for which the answer is yes, the most fitting first, and none if no drawing fits.
      """
    let schema: [String: Any] = [
      "type": "object",
      "properties": ["ids": ["type": "array", "items": ["type": "string", "enum": all.map(\.id)]]],
      "required": ["ids"],
      "additionalProperties": false,
    ]
    guard
      let data = try? await OpenAI.answer(
        system: brief, [.text("Input:\n\(input)\n\nDrawings:\n\(list)")], schemaName: "drawings", schema: schema, timeout: 30, tries: 2),
      let ids = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["ids"] as? [String]
    else { return [] }
    var seen = Set<String>()
    return ids.compactMap { id in seen.insert(id).inserted ? all.first { $0.id == id } : nil }
  }
}
