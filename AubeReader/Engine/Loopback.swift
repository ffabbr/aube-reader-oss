import Foundation
import Network

/// A listener on 127.0.0.1 for the one request the browser makes on its way
/// back from signing in. It keeps the query, and sends the browser on to the
/// app's scheme, which closes the sheet.
final class Loopback: @unchecked Sendable {
  private let listener: NWListener
  private let path: String
  private let onwards: String
  private let queue = DispatchQueue(label: "aube.chatgpt.loopback")
  private let lock = NSLock()
  private var answer: [String: String]?
  private(set) var port: UInt16 = 0
  /// Called on the listener's queue with the query, the first time it comes.
  var onReceive: (([String: String]) -> Void)?

  var received: [String: String]? { lock.withLock { answer } }

  /// A listener on `port`, or on any port if that one is taken: the flow lets
  /// only the port change from one sign-in to the next.
  static func open(preferring port: UInt16, path: String, onwards: String) async throws -> Loopback {
    do {
      return try await Loopback(port: port, path: path, onwards: onwards).started()
    } catch {
      return try await Loopback(port: 0, path: path, onwards: onwards).started()
    }
  }

  private init(port: UInt16, path: String, onwards: String) throws {
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
    listener = try NWListener(using: parameters)
    self.path = path
    self.onwards = onwards
  }

  private func started() async throws -> Loopback {
    try await withCheckedThrowingContinuation { (started: CheckedContinuation<Void, Error>) in
      let once = Once()
      listener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          self?.port = self?.listener.port?.rawValue ?? 0
          once.run { started.resume() }
        case let .failed(error):
          self?.listener.cancel()
          once.run { started.resume(throwing: error) }
        case .cancelled:
          once.run { started.resume(throwing: CancellationError()) }
        default:
          break
        }
      }
      listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
      listener.start(queue: queue)
    }
    return self
  }

  func close() { listener.cancel() }

  private func serve(_ connection: NWConnection) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
      guard let self else { return connection.cancel() }
      // The request line: "GET /auth/callback?code=… HTTP/1.1".
      let head = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      let target = head.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
      let url = URLComponents(string: target)
      let reply: String
      if url?.path == self.path, let items = url?.queryItems {
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let first = self.lock.withLock { () -> Bool in
          guard self.answer == nil else { return false }
          self.answer = query
          return true
        }
        if first { self.onReceive?(query) }
        reply = "HTTP/1.1 302 Found\r\nLocation: \(self.onwards)\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      } else {
        reply = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      }
      connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
  }
}
