import Foundation

/// How the app reaches OpenAI's models, as chosen on the welcome screen or in Settings.
enum Access: String {
  /// On the user's ChatGPT plan, signed in with ChatGPT (see `ChatGPT`).
  case chatGPT
  /// On an OpenAI API key the user typed in, kept in the keychain.
  case apiKey
  /// Not at all: only the documents that come with the app, every version written ahead.
  case off
}
