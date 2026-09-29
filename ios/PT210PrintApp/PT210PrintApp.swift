import PT210PrintCore
import SwiftUI

@main
struct PT210PrintApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.handleForeground() }
                }
        }
    }
}
