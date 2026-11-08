import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
import os

/// Sign in with ChatGPT, and the ChatGPT plan it lets requests run on: OpenAI's
/// OAuth flow for open-source apps (developers.openai.com/siwc).
///
/// The first sign-in registers the app with the account, and OpenAI issues it
/// a client ID of its own, kept for every sign-in after. The browser comes back
/// to a listener on this device's loopback address, as the flow requires, and
/// the listener sends it on to the app's own scheme so the sign-in sheet
/// closes. `OpenAI` then makes requests with the access token in place of a key.
final class ChatGPT: @unchecked Sendable {
  static let shared = ChatGPT()

  /// A signed-in account and its tokens, kept in the keychain.
  struct Session: Codable {
    var email: String?
    /// The account, as the verified ID token names it.
    var subject: String
    var clientID: String
    var idToken: String
    var accessToken: String
    var refreshToken: String?
    var expires: Date
    var scopes: [String]
  }

  /// The service tiers asked for, fastest first. `standard` asks for none.
  enum Tier: String, CaseIterable {
    case ultrafast, fast, standard

    var requested: String? { self == .standard ? nil : rawValue }
    var name: String { rawValue.capitalized }
  }

  /// Why signing in, or staying signed in, didn't work, in words for the
  /// person. What actually went wrong is written to the log.
  enum Problem: LocalizedError {
    case offline, couldNotOpen, refused, unconfirmed, ended, signedOut

    var errorDescription: String? {
      switch self {
      case .offline: "Couldn’t reach OpenAI. Check your internet connection and try again."
      case .couldNotOpen: "The ChatGPT sign-in page couldn’t open. Please try again."
      case .refused: "ChatGPT didn’t finish signing you in. Please try again in a moment."
      case .unconfirmed: "The sign-in couldn’t be confirmed, so it wasn’t used. Please try again."
      case .ended: "Your ChatGPT sign-in has ended. Sign in again in Settings."
      case .signedOut: "You’re not signed in to ChatGPT. Sign in in Settings."
      }
    }
  }

  /// The app's name, which OpenAI shows on the first sign-in.
  private static let appName = "Aube Reader"
  private static let issuer = "https://auth.openai.com"
  private static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
  private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
  private static let revokeURL = URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!
  private static let keysURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
  /// What the tokens are for, sent with every token request.
  private static let resource = OpenAI.api.absoluteString
  private static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
  /// The scope that lets requests run on the plan; signing in alone doesn't.
  static let planScope = "chatgpt.tokens.use.direct"
  /// Where ChatGPT shows, and lets the user limit, what apps have used of the plan.
  static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!

  /// The scheme the listener sends the browser on to, which closes the sheet.
  private static let returnScheme = "aubereader"
  private static let callbackPath = "/auth/callback"
  private static let preferredPort: UInt16 = 1455

  private static let defaults = UserDefaults.standard
  private static let log = Logger(subsystem: "aube-reader", category: "chatgpt")

  private let lock = NSLock()
  private var current: Session?
  private var renewal: Task<Session, Error>?
  /// The sign-in sheet while it's open, and the window it's shown over.
  private var sheet: (session: ASWebAuthenticationSession, anchor: Anchor)?

  private init() {
    current = Keychain.read("chatgpt-session").flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
  }

  // ─── State ───────────────────────────────────────────────────────────────

  var session: Session? { lock.withLock { current } }

  /// Signed in, with the plan granted: requests can run on it.
  var ready: Bool { session?.scopes.contains(Self.planScope) == true }

  /// Keeps `s` as the sign-in, or forgets it if nil. With `previous`, only if
  /// that is still the sign-in: a renewal that comes back after a sign-out, or
  /// after signing in afresh, mustn't bring the old one back. Says whether it kept it.
  @discardableResult
  private func keep(_ s: Session?, replacing previous: Session? = nil) -> Bool {
    let outcome = lock.withLock { () -> (kept: Bool, changed: Bool) in
      if let previous, current?.subject != previous.subject || current?.refreshToken != previous.refreshToken {
        return (false, false)
      }
      defer { current = s }
      return (true, current?.subject != s?.subject || current?.scopes != s?.scopes)
    }
    guard outcome.kept else { return false }
    Keychain.write(s.flatMap { try? JSONEncoder().encode($0) }, "chatgpt-session")
    if outcome.changed { OpenAI.announceChange() }
    return true
  }

  /// The client ID the first registration was issued. Kept through sign-outs,
  /// so signing in again doesn't register the app a second time.
  private var clientID: String? {
    get { Self.defaults.string(forKey: "aube-chatgpt-client") }
    set { Self.defaults.set(newValue, forKey: "aube-chatgpt-client") }
  }

  /// This install, as OpenAI's "agent host": made once, opaque, and nothing
  /// to do with who the user is.
  private var hostID: String {
    if let id = Self.defaults.string(forKey: "aube-chatgpt-host") { return id }
    let id = "urn:uuid:" + UUID().uuidString.lowercased()
    Self.defaults.set(id, forKey: "aube-chatgpt-host")
    return id
  }

  // ─── Signing in ──────────────────────────────────────────────────────────

  /// Signs in through the browser sheet over `window`. The session says in its
  /// scopes whether the plan was granted. Throws `CancellationError` if the
  /// person closed the sheet or declined, and otherwise a `Problem`.
  @MainActor
  func signIn(from window: ASPresentationAnchor) async throws -> Session {
    do {
      return try await signingIn(from: window)
    } catch let e where e is CancellationError || e is Problem {
      if let p = e as? Problem { Self.log.error("Sign-in failed: \(String(describing: p), privacy: .public)") }
      throw e
    } catch let e as URLError {
      Self.log.error("Sign-in failed, network: \(e.localizedDescription, privacy: .public)")
      throw Problem.offline
    } catch {
      Self.log.error("Sign-in failed: \(String(describing: error), privacy: .public)")
      throw Problem.refused
    }
  }

  @MainActor
  private func signingIn(from window: ASPresentationAnchor) async throws -> Session {
    let state = Self.random()
    let nonce = Self.random()
    let verifier = Self.random(48)
    let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))

    let loopback: Loopback
    do {
      loopback = try await Loopback.open(preferring: Self.preferredPort, path: Self.callbackPath, onwards: "\(Self.returnScheme)://signed-in")
    } catch {
      Self.log.error("Loopback listener didn't start: \(String(describing: error), privacy: .public)")
      throw Problem.couldNotOpen
    }
    defer { loopback.close() }
    let redirect = "http://127.0.0.1:\(loopback.port)\(Self.callbackPath)"

    // The first sign-in registers the app; later ones reuse what that issued.
    let saved = clientID
    var query = [("client_id", saved ?? "dynamic_agent_client")]
    if saved == nil { query.append(("agent_name_hint", Self.appName)) }
    query += [
      ("ext_agent_host_id", hostID),
      ("response_type", "code"),
      ("redirect_uri", redirect),
      ("scope", Self.scope),
      ("resource", Self.resource),
      ("state", state),
      ("nonce", nonce),
      ("code_challenge_method", "S256"),
      ("code_challenge", challenge),
    ]
    var url = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
    url.percentEncodedQuery = query.map { "\($0.0)=\(Self.encode($0.1))" }.joined(separator: "&")

    let back = try await browse(url.url!, over: window, loopback: loopback)
    if let error = back["error"] {
      Self.log.error("Authorization error: \(error, privacy: .public) \(back["error_description"] ?? "", privacy: .public)")
      if error == "access_denied" { throw CancellationError() }
      // A client ID that no longer works is let go, so the next try registers afresh.
      if saved != nil, ["invalid_client", "unauthorized_client"].contains(error) { clientID = nil }
      throw Problem.refused
    }
    guard back["state"] == state, let code = back["code"], !code.isEmpty else { throw Problem.unconfirmed }

    let issued: String
    if let saved {
      guard back["client_id"] == nil || back["client_id"] == saved else { throw Problem.unconfirmed }
      issued = saved
    } else {
      guard let id = back["client_id"], !id.isEmpty else { throw Problem.refused }
      issued = id
      // Kept at once: a code that fails to exchange is retried with this client ID, not a new registration.
      clientID = id
    }

    let tokens = try await post(Self.tokenURL, [
      "grant_type": "authorization_code",
      "client_id": issued,
      "code": code,
      "code_verifier": verifier,
      "redirect_uri": redirect,
      "resource": Self.resource,
    ])
    guard let idToken = tokens["id_token"] as? String else { throw Problem.unconfirmed }
    let claims = try await verify(idToken, clientID: issued, nonce: nonce)
    let session = try Self.session(from: tokens, clientID: issued, claims: claims, previous: nil)
    keep(session)
    lock.withLock { step = 0 }
    return session
  }

  /// Opens the sign-in page, and hands back what the browser brought to the
  /// listener. Closing the sheet before that is a cancellation.
  @MainActor
  private func browse(_ url: URL, over window: ASPresentationAnchor, loopback: Loopback) async throws -> [String: String] {
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<[String: String], Error>) in
      let once = Once()
      let finish: (Result<[String: String], Error>) -> Void = { [weak self] result in
        once.run {
          done.resume(with: result)
          // If the sheet didn't close itself on the way back, it's closed here.
          self?.sheet?.session.cancel()
          self?.sheet = nil
        }
      }
      let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.returnScheme) { _, error in
        DispatchQueue.main.async {
          // Come back through the listener, the sheet then closes on its own; closed sooner, the person gave up.
          if let answer = loopback.received { return finish(.success(answer)) }
          if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return finish(.failure(CancellationError())) }
          Self.log.error("Sign-in sheet closed: \(String(describing: error), privacy: .public)")
          finish(.failure(Problem.couldNotOpen))
        }
      }
      loopback.onReceive = { answer in DispatchQueue.main.async { finish(.success(answer)) } }
      let anchor = Anchor(window)
      auth.presentationContextProvider = anchor
      // The browser's own sign-in to ChatGPT is used, if it has one.
      auth.prefersEphemeralWebBrowserSession = false
      sheet = (auth, anchor)
      if !auth.start() { finish(.failure(Problem.couldNotOpen)) }
    }
  }

  // ─── Tokens ──────────────────────────────────────────────────────────────

  /// A live access token, renewed first if it's about to run out, or if
  /// `renew` says the last one was turned away.
  func accessToken(renew: Bool = false) async throws -> String {
    guard let s = session else { throw Problem.signedOut }
    if !renew, s.expires.timeIntervalSinceNow > 90 { return s.accessToken }
    return try await renewed().accessToken
  }

  /// Renews the tokens, one renewal at a time: each hands back a new refresh
  /// token, and spends the old one.
  private func renewed() async throws -> Session {
    let task: Task<Session, Error> = lock.withLock {
      if let r = renewal { return r }
      let r = Task { try await self.renew() }
      renewal = r
      return r
    }
    defer { lock.withLock { if renewal == task { renewal = nil } } }
    return try await task.value
  }

  private func renew() async throws -> Session {
    guard let s = session else { throw Problem.signedOut }
    guard let refresh = s.refreshToken else { return try ended(s) }
    do {
      let tokens = try await post(Self.tokenURL, [
        "grant_type": "refresh_token",
        "refresh_token": refresh,
        "client_id": s.clientID,
        "resource": Self.resource,
      ])
      let next = try Self.session(from: tokens, clientID: s.clientID, claims: nil, previous: s)
      // Signed out, or in afresh, while this was on its way: what's there now stands.
      guard keep(next, replacing: s) else {
        guard let now = session else { throw Problem.signedOut }
        return now
      }
      return next
    } catch let e as TokenError where e.isFinal {
      Self.log.error("Renewal refused: \(e.code, privacy: .public)")
      return try ended(s)
    }
  }

  /// The sign-in `s` can't be renewed: it's forgotten, unless it has already
  /// given way to another, and the person asked to sign in again.
  private func ended(_ s: Session) throws -> Session {
    keep(nil, replacing: s)
    throw Problem.ended
  }

  /// Signs out: the refresh token is revoked with OpenAI, then forgotten here
  /// either way. Says whether OpenAI confirmed it.
  func signOut() async -> Bool {
    guard let s = session else { return true }
    var confirmed = s.refreshToken == nil
    if let token = s.refreshToken {
      for attempt in 0..<3 where !confirmed {
        if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt))) }
        var request = URLRequest(url: Self.revokeURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["token": token, "token_type_hint": "refresh_token", "client_id": s.clientID])
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { continue }
        let status = response.status ?? 0
        if status == 200 { confirmed = true }
        if status < 500 { break }
      }
    }
    keep(nil)
    lock.withLock { step = 0 }
    return confirmed
  }

  // ─── Models and tiers ────────────────────────────────────────────────────

  /// A model, and the service tier it's asked at.
  struct Choice: Equatable {
    let model: String
    let tier: Tier

    /// The model as people know it: "gpt-6.1-sol" is "GPT-6.1 Sol".
    var name: String {
      let parts = model.split(separator: "-")
      guard parts.count > 2, parts[0] == "gpt" else { return model }
      return "GPT-\(parts[1]) " + parts.dropFirst(2).map(\.capitalized).joined(separator: " ")
    }
  }

  /// What requests try, in order, each tried when the one before is turned
  /// away: Sol at its fastest, then Terra fast, then Terra at standard speed.
  static let ladder = [
    Choice(model: "gpt-6.1-sol", tier: .ultrafast),
    Choice(model: "gpt-6.1-terra", tier: .fast),
    Choice(model: "gpt-6.1-terra", tier: .standard),
  ]

  /// How far down `ladder` requests have had to go, since the app opened or
  /// the account signed in.
  private var step = 0

  /// The model and tier requests use now.
  var choice: Choice { Self.ladder[lock.withLock { step }] }

  /// `rejected` was turned away: goes on to the next of `ladder` from now on,
  /// and hands it back; nil if there's none after it. Requests turned away
  /// together step down only once.
  func stepDown(from rejected: Choice) -> Choice? {
    lock.withLock {
      guard let i = Self.ladder.firstIndex(of: rejected), i + 1 < Self.ladder.count else { return nil }
      step = max(step, i + 1)
      return Self.ladder[step]
    }
  }

  // ─── The token endpoint ──────────────────────────────────────────────────

  /// What the token endpoint said when it said no. Final when the grant is
  /// spent or revoked, rather than the service or the line being unwell.
  private struct TokenError: Error {
    let code: String
    var isFinal: Bool { ["invalid_grant", "token_expired", "refresh_token_invalidated", "invalid_token", "invalid_client"].contains(code) }
  }

  private func post(_ url: URL, _ fields: [String: String]) async throws -> [String: Any] {
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = Self.form(fields)
    let (data, response) = try await URLSession.shared.data(for: request)
    let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    let status = response.status ?? 0
    guard status == 200 else {
      // OAuth's own shape, or the API's.
      let code = json["error"] as? String ?? (json["error"] as? [String: Any])?["code"] as? String ?? "status \(status)"
      Self.log.error("Token endpoint said no: \(code, privacy: .public)")
      throw TokenError(code: code)
    }
    return json
  }

  /// A session from what the token endpoint handed back. A renewal may leave
  /// out what hasn't changed, which is kept from `previous`.
  private static func session(from tokens: [String: Any], clientID: String, claims: [String: Any]?, previous: Session?) throws -> Session {
    guard let access = tokens["access_token"] as? String, let subject = claims?["sub"] as? String ?? previous?.subject else {
      throw Problem.unconfirmed
    }
    let lifetime = (tokens["expires_in"] as? NSNumber)?.doubleValue ?? 3600
    let granted = (tokens["scope"] as? String)?.split(separator: " ").map(String.init) ?? tokens["scope"] as? [String] ?? previous?.scopes ?? []
    return Session(
      email: claims?["email"] as? String ?? previous?.email,
      subject: subject,
      clientID: clientID,
      idToken: tokens["id_token"] as? String ?? previous?.idToken ?? "",
      accessToken: access,
      refreshToken: tokens["refresh_token"] as? String ?? previous?.refreshToken,
      expires: Date().addingTimeInterval(lifetime),
      scopes: granted)
  }

  // ─── The ID token ────────────────────────────────────────────────────────

  /// The claims of `token`, once its signature checks out against OpenAI's
  /// published keys, and it's from OpenAI, for this client, for this sign-in.
  private func verify(_ token: String, clientID: String, nonce: String) async throws -> [String: Any] {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard
      parts.count == 3,
      let head = Self.unbase64url(parts[0]).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
      let claims = Self.unbase64url(parts[1]).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
      let signature = Self.unbase64url(parts[2]),
      head["alg"] as? String == "RS256"
    else { throw Problem.unconfirmed }

    let (data, _) = try await URLSession.shared.data(from: Self.keysURL)
    let keys = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["keys"] as? [[String: Any]] ?? []
    let kid = head["kid"] as? String
    guard
      let jwk = keys.first(where: { kid == nil || $0["kid"] as? String == kid }),
      let n = (jwk["n"] as? String).flatMap({ Self.unbase64url(Substring($0)) }),
      let e = (jwk["e"] as? String).flatMap({ Self.unbase64url(Substring($0)) }),
      let key = Self.rsaKey(modulus: n, exponent: e),
      SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data("\(parts[0]).\(parts[1])".utf8) as CFData, signature as CFData, nil)
    else { throw Problem.unconfirmed }

    let audience = claims["aud"] as? [String] ?? (claims["aud"] as? String).map { [$0] } ?? []
    let expiry = Date(timeIntervalSince1970: (claims["exp"] as? NSNumber)?.doubleValue ?? 0)
    guard
      claims["iss"] as? String == Self.issuer,
      audience.contains(clientID),
      expiry > Date().addingTimeInterval(-300),
      claims["nonce"] as? String == nonce,
      claims["sub"] is String
    else { throw Problem.unconfirmed }
    return claims
  }

  /// An RSA public key from a JWK's modulus and exponent, as PKCS #1 DER.
  private static func rsaKey(modulus n: Data, exponent e: Data) -> SecKey? {
    func length(_ k: Int) -> Data {
      if k < 128 { return Data([UInt8(k)]) }
      let bytes = withUnsafeBytes(of: k.bigEndian, Array.init).drop(while: { $0 == 0 })
      return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    func integer(_ d: Data) -> Data {
      var v = Data(d.drop(while: { $0 == 0 }))
      if v.isEmpty || v.first! & 0x80 != 0 { v.insert(0, at: 0) }
      return Data([0x02]) + length(v.count) + v
    }
    let body = integer(n) + integer(e)
    let der = Data([0x30]) + length(body.count) + body
    let attributes = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic] as CFDictionary
    return SecKeyCreateWithData(der as CFData, attributes, nil)
  }

  // ─── Encoding ────────────────────────────────────────────────────────────

  private static func random(_ bytes: Int = 32) -> String {
    var data = Data(count: bytes)
    _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
    return base64url(data)
  }

  private static func base64url(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  private static func unbase64url(_ s: Substring) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
  }

  /// `s` with everything but the unreserved characters percent-encoded, spaces included.
  private static func encode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
  }

  private static func form(_ fields: [String: String]) -> Data {
    Data(fields.map { "\($0.key)=\(encode($0.value))" }.joined(separator: "&").utf8)
  }
}

// ─── Pieces of the sign-in ───────────────────────────────────────────────────

/// The window the sign-in sheet is shown over.
private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
  private let window: ASPresentationAnchor

  init(_ window: ASPresentationAnchor) { self.window = window }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
