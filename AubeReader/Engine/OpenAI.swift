import Foundation

/// Asks OpenAI's chat model and hands back its answer as it is written, piece
/// by piece. The key comes from the app's Info.plist, which takes it from
/// `Local.xcconfig` (kept out of git; see `Local.example.xcconfig`).
enum OpenAI {
  /// The model for everything but Decisions, as Settings has it.
  static var model: String { Store.useLuna ? decider : "gpt-6.1-terra" }
  /// The only model the Decisions API takes.
  static let decider = "gpt-6-luna"

  struct Failure: LocalizedError {
    let errorDescription: String?
  }

  static var key: String? {
    guard let k = Bundle.main.object(forInfoDictionaryKey: "OpenAIKey") as? String else { return nil }
    let key = k.trimmingCharacters(in: .whitespaces)
    return key.isEmpty || key.hasPrefix("$(") ? nil : key
  }

  /// One yes-or-no question for the Decisions API: `name` comes back with its answer.
  struct Predicate {
    let name: String
    let instructions: String
  }

  /// How likely each predicate is to be true of `input`, by name. Decisions
  /// answers at once, whole, rather than being written out. A question the
  /// model declines has no entry.
  static func decide(_ input: String, _ questions: [Predicate], timeout: TimeInterval = 8) async throws -> [String: Double] {
    guard let key else { throw Failure(errorDescription: "No OpenAI key.") }
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/decisions")!, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": decider,
      "input": input,
      "questions": questions.map { ["type": "predicate", "name": $0.name, "instructions": $0.instructions] },
    ] as [String: Any])
    let (body, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    guard status == 200, let answers = json?["answers"] as? [[String: Any]] else {
      let said = (json?["error"] as? [String: Any])?["message"] as? String
      throw Failure(errorDescription: said ?? "OpenAI answered with status \(status).")
    }
    var out: [String: Double] = [:]
    for a in answers {
      if let name = a["name"] as? String, let p = a["probability"] as? Double { out[name] = p }
    }
    return out
  }

  /// One part of a message that holds pictures: words, or a picture of a page.
  enum Part {
    case text(String)
    /// JPEG data. Sent at high detail, which reads small print; see the image guide.
    case jpeg(Data)

    fileprivate var json: [String: Any] {
      switch self {
      case let .text(t): return ["type": "text", "text": t]
      case let .jpeg(d):
        return ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + d.base64EncodedString(), "detail": "high"]]
      }
    }
  }

  /// Whether a request is worth making again: the service was busy or the line dropped.
  private static func transient(_ status: Int) -> Bool { status == 408 || status == 409 || status == 429 || status >= 500 }

  /// Asks the model something about pictures and words, and hands back its
  /// answer whole, as JSON in the shape of `schema`. Tried up to `tries` times
  /// when the service is busy or the connection fails, waiting longer each time.
  static func answer(
    system: String, _ parts: [Part], schemaName: String, schema: [String: Any], effort: String = "low", timeout: TimeInterval = 120, tries: Int = 3
  ) async throws -> Data {
    guard let key else { throw Failure(errorDescription: "No OpenAI key.") }
    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = [
      "model": model,
      "reasoning_effort": effort,
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": parts.map(\.json)],
      ],
      "response_format": ["type": "json_schema", "json_schema": ["name": schemaName, "strict": true, "schema": schema]],
    ]
    if Store.fastTier { body["service_tier"] = "fast" }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    var last: Error = Failure(errorDescription: "Nothing came back.")
    for attempt in 0..<max(tries, 1) {
      if attempt > 0 { try await Task.sleep(for: .seconds(pow(2, Double(attempt)) * 1.5)) }
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
          let said = (json?["error"] as? [String: Any])?["message"] as? String
          let failure = Failure(errorDescription: said ?? "OpenAI answered with status \(status).")
          if transient(status) {
            last = failure
            continue
          }
          throw failure
        }
        guard
          let message = (json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any],
          let content = message["content"] as? String
        else {
          // A refusal, or an answer cut off: neither gets better for asking again.
          throw Failure(errorDescription: "The model gave no answer.")
        }
        return Data(content.utf8)
      } catch is CancellationError {
        throw CancellationError()
      } catch let e as URLError {
        last = e
      }
    }
    throw last
  }

  /// `messages` as the API takes them: each a role ("system", "user",
  /// "assistant") and its content. `effort` is how long the model reasons
  /// first: "none" to start writing at once, up to "xhigh".
  static func stream(_ messages: [[String: String]], effort: String = "low") -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { out in
      let task = Task {
        do {
          guard let key else {
            throw Failure(errorDescription: "No OpenAI key. Set OPENAI_API_KEY in Local.xcconfig and build again.")
          }
          var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
          request.httpMethod = "POST"
          request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          var body: [String: Any] = [
            "model": model,
            "stream": true,
            "reasoning_effort": effort,
            "messages": messages,
          ]
          if Store.fastTier { body["service_tier"] = "fast" }
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          let (bytes, response) = try await URLSession.shared.bytes(for: request)
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          guard status == 200 else {
            var body = Data()
            for try await b in bytes { body.append(b) }
            let said = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])
              .flatMap { $0["error"] as? [String: Any] }
              .flatMap { $0["message"] as? String }
            throw Failure(errorDescription: said ?? "OpenAI answered with status \(status).")
          }
          // Server-sent events: one `data:` line per piece, then `[DONE]`.
          for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst(6)
            if payload == "[DONE]" { break }
            guard
              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let piece = (choice["delta"] as? [String: Any])?["content"] as? String,
              !piece.isEmpty
            else { continue }
            out.yield(piece)
          }
          out.finish()
        } catch {
          out.finish(throwing: error)
        }
      }
      out.onTermination = { _ in task.cancel() }
    }
  }
}
