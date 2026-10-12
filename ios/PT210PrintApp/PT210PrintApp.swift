import PT210PrintCore
import SwiftUI

#if targetEnvironment(macCatalyst)
import UIKit

@main
@MainActor
final class PT210PrintAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = PT210PrintSceneDelegate.self
        return configuration
    }
}

@MainActor
final class PT210PrintSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var model: AppModel?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let model = AppModel()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ContentView(model: model))
        window.makeKeyAndVisible()
        self.model = model
        self.window = window
        for context in connectionOptions.urlContexts {
            model.handleShellURL(context.url)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        model?.handleForeground()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            model?.handleShellURL(context.url)
        }
    }
}
#else
@main
@MainActor
struct PT210PrintApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: scenePhase) { phase in
                    if phase == .active { model.handleForeground() }
                }
        }
    }
}
#endif
