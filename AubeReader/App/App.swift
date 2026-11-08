import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    // Light or dark follows the system setting; every color is dynamic.
    let desk = DeskViewController()
    window.rootViewController = desk
    window.makeKeyAndVisible()
    self.window = window
    bringIn(options.urlContexts)
    #if DEBUG
    if let script = UserDefaults.standard.string(forKey: "drive") { desk.drive(script) }
    #endif
  }

  /// A document sent here from another app ("Open in Aube Reader").
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    bringIn(URLContexts)
  }

  private func bringIn(_ contexts: Set<UIOpenURLContext>) {
    let urls = contexts.map(\.url).filter(\.isFileURL)
    guard !urls.isEmpty else { return }
    Imports.shared.add(urls)
    // What iOS copies into the inbox is no longer needed once there's a copy here.
    for url in urls where url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    (window?.rootViewController as? DeskViewController)?.saveNow()
  }
}
