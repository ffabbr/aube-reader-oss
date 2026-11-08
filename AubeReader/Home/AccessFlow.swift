import UIKit

/// What the welcome screen and Settings share in choosing how the app reaches
/// OpenAI: signing in with ChatGPT, keeping an API key, and the notes OpenAI
/// asks apps to show about the ChatGPT plan. Problems come back as a sentence
/// to show in place, never as an alert.
@MainActor
enum AccessFlow {
  /// How a sign-in ended.
  enum Outcome {
    case signedIn
    /// The person closed the sheet or declined: nothing to say.
    case cancelled
    /// It didn't work, and this says why.
    case failed(String)
  }

  /// Signs in with ChatGPT over `vc`, and from then on requests run on the plan.
  static func signIn(from vc: UIViewController) async -> Outcome {
    guard let window = vc.view.window else { return .failed(ChatGPT.Problem.couldNotOpen.localizedDescription) }
    do {
      let session = try await ChatGPT.shared.signIn(from: window)
      guard session.scopes.contains(ChatGPT.planScope) else {
        return .failed("Signing in with ChatGPT needs a paid ChatGPT plan, Plus or Pro, and this account doesn’t have one. You can use your own OpenAI API key instead.")
      }
      Store.access = .chatGPT
      if !Store.planNoted {
        Store.planNoted = true
        await notePlan(over: vc)
      }
      return .signedIn
    } catch is CancellationError {
      return .cancelled
    } catch ChatGPT.Problem.offline {
      return .failed(ChatGPT.Problem.offline.localizedDescription)
    } catch {
      return .failed(signInFailed)
    }
  }

  /// What a sign-in that didn't work says, other than for want of a
  /// connection: that the plan is a paid one, and that a key works without it.
  private static let signInFailed =
    "Couldn’t sign in with ChatGPT. It needs a paid ChatGPT plan, Plus or Pro. If you don’t have one, use your own OpenAI API key instead."

  /// Why a key wasn't kept.
  enum KeyProblem {
    case empty, rejected, offline

    /// A word or two the field shows in place of what was typed; none when
    /// the field was empty, where the shake says enough.
    var hint: String? {
      switch self {
      case .empty: nil
      case .rejected: "Key not accepted"
      case .offline: "Couldn’t reach OpenAI"
      }
    }
  }

  /// Checks `typed` with OpenAI and keeps it, and from then on requests run on
  /// it. Nil once it's in use, or else why not.
  static func save(key typed: String) async -> KeyProblem? {
    let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return .empty }
    switch await OpenAI.check(key: key) {
    case 200:
      OpenAI.key = key
      Store.access = .apiKey
      return nil
    case nil:
      return .offline
    default:
      return .rejected
    }
  }

  /// OpenAI's note for the first sign-in that grants the plan, in its words.
  static func notePlan(over vc: UIViewController) async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      let alert = UIAlertController(
        title: "You’re using your ChatGPT plan",
        message: "Eligible usage in this app uses your ChatGPT plan. Manage usage in your ChatGPT settings.",
        preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "Got it", style: .default) { _ in done.resume() })
      vc.present(alert, animated: true)
    }
  }

  /// The plan's usage for the app has run out, or met a limit the person set.
  static func usageLimit(over vc: UIViewController) {
    let alert = UIAlertController(
      title: "Usage limit reached",
      message: "This app has used what your ChatGPT plan allows it for now, or reached a limit you set. You can see and change that in your ChatGPT settings.",
      preferredStyle: .alert)
    let manage = UIAlertAction(title: "Manage Usage", style: .default) { _ in UIApplication.shared.open(ChatGPT.usageURL) }
    alert.addAction(manage)
    alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
    alert.preferredAction = manage
    vc.present(alert, animated: true)
  }
}
