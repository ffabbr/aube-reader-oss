import Foundation

/// Every request the app makes of OpenAI's models goes through here, and all
/// of them the same way: to the Responses API, streamed and not stored, as the
/// ChatGPT plan requires. Only the credential differs: the plan's access token
/// or an API key.
enum OpenAI {
  /// What went wrong with a request: what to tell the reader, and the HTTP
  /// status and OpenAI's error code and parameter, where there are some.
  struct Failure: LocalizedError {
    let errorDescription: String?
    var status = 0
    var code: String?
    var param: String?
  }

  /// Posted on the main thread when how the model is reached has changed: a
  /// sign-in, a sign-out, a key, or a different choice in Settings.
  static let accessChanged = Notification.Name("aube.openai.access-changed")
  /// Posted on the main thread when the ChatGPT plan's usage for the app has run out.
  static let usageLimitReached = Notification.Name("aube.openai.usage-limit")

  static func announceChange() {
    let post = { NotificationCenter.default.post(name: accessChanged, object: nil) }
    if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
  }

  // ─── Access ──────────────────────────────────────────────────────────────

  /// How requests are made: none until the welcome screen has been answered.
  static var access: Access { Store.access ?? .off }

  /// Whether the model can be asked anything at all, as access now stands.
  static var available: Bool {
    switch access {
    case .chatGPT: ChatGPT.shared.ready
    case .apiKey: key != nil
    case .off: false
    }
  }

  /// Where OpenAI's API is.
  static let api = URL(string: "https://api.openai.com/v1")!
  /// The models a key's requests go to: the usual one, and the one Settings
  /// can turn to instead. (`tools/levels/llm.py` writes with the usual one too.)
  static let keyModel = "gpt-6.1-terra"
  static let lunaModel = "gpt-6-luna"

  /// The model requests go to: on the plan, the one `ChatGPT.ladder` has
  /// reached; on a key, as Settings has it.
  static var model: String {
    access == .chatGPT ? ChatGPT.shared.choice.model : Store.useLuna ? lunaModel : keyModel
  }

  /// The API key typed into the app, kept in the keychain.
  static var key: String? {
    get { Keychain.string("openai-api-key") }
    set {
      Keychain.setString(newValue, "openai-api-key")
      announceChange()
    }
  }

  /// What OpenAI says to `key` when asked for its models: 200 if it takes it,
  /// nil if OpenAI couldn't be reached.
  static func check(key: String) async -> Int? {
    var request = URLRequest(url: api.appendingPathComponent("models"), timeoutInterval: 20)
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
    return response.status
  }

  // ─── Asking ──────────────────────────────────────────────────────────────

  /// One part of a message that holds pictures: words, or a picture of a page.
  enum Part {
    case text(String)
    /// JPEG data, sent at high detail, which reads small print.
    case jpeg(Data)

    fileprivate var json: [String: Any] {
      switch self {
      case let .text(t): ["type": "input_text", "text": t]
      case let .jpeg(d): ["type": "input_image", "image_url": "data:image/jpeg;base64," + d.base64EncodedString(), "detail": "high"]
      }
    }
  }

  /// `messages` as chat models take them, each a role ("system", "user",
  /// "assistant") and its content; the answer comes piece by piece. `effort`
  /// is how long the model reasons first: "none" to start writing at once, up
  /// to "xhigh".
  static func stream(_ messages: [[String: String]], effort: String = "low") -> AsyncThrowingStream<String, Error> {
    // The Responses API takes system messages as the request's instructions.
    let instructions = messages.filter { $0["role"] == "system" }.compactMap { $0["content"] }.joined(separator: "\n\n")
    let input = messages.filter { $0["role"] != "system" }.map { ["role": $0["role"] ?? "user", "content": $0["content"] ?? ""] }
    var body: [String: Any] = ["input": input, "reasoning": ["effort": effort]]
    if !instructions.isEmpty { body["instructions"] = instructions }

    return AsyncThrowingStream { out in
      let task = Task {
        do {
          try await respond(body, timeout: 60) { out.yield($0) }
          out.finish()
        } catch {
          out.finish(throwing: error)
        }
      }
      out.onTermination = { _ in task.cancel() }
    }
  }

  /// Asks about pictures and words, and hands back the answer whole, as JSON
  /// in the shape of `schema`. Tried up to `tries` times while the service is
  /// busy or the connection fails, waiting longer each time.
  static func answer(
    system: String, _ parts: [Part], schemaName: String, schema: [String: Any], effort: String = "low", timeout: TimeInterval = 120, tries: Int = 3
  ) async throws -> Data {
    let body: [String: Any] = [
      "instructions": system,
      "input": [["role": "user", "content": parts.map(\.json)]],
      "reasoning": ["effort": effort],
      "text": ["format": ["type": "json_schema", "name": schemaName, "strict": true, "schema": schema]],
    ]
    var last: Error = Failure(errorDescription: "Nothing came back.")
    for attempt in 0..<max(tries, 1) {
      if attempt > 0 { try await Task.sleep(for: .seconds(pow(2, Double(attempt)) * 1.5)) }
      do {
        var answer = ""
        try await respond(body, timeout: timeout) { answer += $0 }
        guard !answer.isEmpty else { throw Failure(errorDescription: "The model gave no answer.") }
        return Data(answer.utf8)
      } catch let f as Failure where f.isTransient {
        last = f
      } catch let e as URLError where e.code != .cancelled {
        last = e
      }
    }
    throw last
  }

  // ─── The request ─────────────────────────────────────────────────────────

  /// Makes one request, and hands each piece of the answer to `piece` as it
  /// comes. On the ChatGPT plan it goes down `ChatGPT.ladder` while a model
  /// or its tier is turned away, and renews an access token that's turned
  /// away once.
  private static func respond(_ request: [String: Any], timeout: TimeInterval, piece: (String) -> Void) async throws {
    var body = request
    body["model"] = model
    body["stream"] = true
    body["store"] = false

    switch access {
    case .off:
      throw Failure(errorDescription: "AI is turned off. Choose how to use it in Settings.")

    case .apiKey:
      guard let key else { throw Failure(errorDescription: "There’s no OpenAI API key. Enter one in Settings.") }
      if Store.fastTier { body["service_tier"] = "fast" }
      try await send(body, token: key, timeout: timeout, piece: piece)

    case .chatGPT:
      let plan = ChatGPT.shared
      var choice = plan.choice
      var renewed = false
      var answering = false
      while true {
        body["model"] = choice.model
        if let requested = choice.tier.requested { body["service_tier"] = requested } else { body["service_tier"] = nil }
        do {
          let token = try await plan.accessToken(renew: renewed)
          try await send(body, token: token, timeout: timeout) {
            answering = true
            piece($0)
          }
          return
        } catch let f as Failure where !answering && f.turnsAwayChoice {
          guard let next = plan.stepDown(from: choice) else { throw f }
          choice = next
        } catch let f as Failure where !answering && !renewed && f.status == 401 {
          renewed = true
        }
      }
    }
  }

  /// Sends `body` to the Responses API and reads its events as they stream in,
  /// until the response is complete.
  private static func send(_ body: [String: Any], token: String, timeout: TimeInterval, piece: (String) -> Void) async throws {
    var request = URLRequest(url: api.appendingPathComponent("responses"), timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    let status = response.status ?? 0
    guard status == 200 else {
      var data = Data()
      for try await b in bytes { data.append(b) }
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      throw failure(json?["error"] as? [String: Any], status: status)
    }

    // Server-sent events, one `data:` line each.
    for try await line in bytes.lines where line.hasPrefix("data:") {
      let payload = Data(line.dropFirst(5).utf8)
      guard let event = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { continue }
      let response = event["response"] as? [String: Any]
      switch event["type"] as? String {
      case "response.output_text.delta":
        if let delta = event["delta"] as? String, !delta.isEmpty { piece(delta) }
      case "response.completed":
        return
      case "response.failed":
        throw failure(response?["error"] as? [String: Any], status: 0)
      case "response.incomplete":
        throw Failure(errorDescription: "The answer was cut off.", code: "incomplete")
      case "error":
        throw failure(event["error"] as? [String: Any] ?? event, status: 0)
      default:
        continue
      }
    }
    throw Failure(errorDescription: "The answer stopped partway.", code: "interrupted")
  }

  /// What went wrong, as the API put it, in words for the page.
  private static func failure(_ error: [String: Any]?, status: Int) -> Failure {
    let code = error?["code"] as? String
    let words: String
    switch code {
    case "subscription_sharing_usage_limit_exceeded":
      DispatchQueue.main.async { NotificationCenter.default.post(name: usageLimitReached, object: nil) }
      words = "Your ChatGPT plan’s usage for this app has run out."
    case "subscription_sharing_usage_unavailable":
      words = "ChatGPT couldn’t check your plan’s usage just now. Try again in a moment."
    case "subscription_sharing_invalid_user":
      words = "Your ChatGPT sign-in has ended. Sign in again in Settings."
    default:
      words = error?["message"] as? String ?? (status > 0 ? "OpenAI answered with status \(status)." : "OpenAI couldn’t answer.")
    }
    return Failure(errorDescription: words, status: status, code: code, param: error?["param"] as? String)
  }
}

extension OpenAI.Failure {
  /// The model, or the tier it was asked at, was turned away or is too busy,
  /// rather than the request itself: the next of `ChatGPT.ladder` may answer.
  /// Not when the plan's usage has run out, which no other model changes.
  var turnsAwayChoice: Bool {
    guard code?.hasPrefix("subscription_sharing") != true else { return false }
    return param == "model" || param == "service_tier" || code == "model_not_found" || status == 404 || status == 429
  }

  /// Worth asking again: the service was busy or unwell. Not when the plan's
  /// usage has run out, which asking again won't change.
  var isTransient: Bool {
    guard code != "subscription_sharing_usage_limit_exceeded" else { return false }
    return status == 408 || status == 409 || status == 429 || status >= 500
  }
}

extension URLResponse {
  /// The HTTP status, if it was an HTTP response.
  var status: Int? { (self as? HTTPURLResponse)?.statusCode }
}
