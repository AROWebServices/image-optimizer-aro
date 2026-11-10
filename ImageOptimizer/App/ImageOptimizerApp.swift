import SwiftUI
import OptimizerCore

@main
struct ImageOptimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        AppDelegate.importHandler = { urls in model.openExternal(urls) }
    }

    var body: some Scene {
        WindowGroup("Image Optimizer ARO") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1120, minHeight: 600)
        }
        .defaultSize(width: 1360, height: 840)
        .commands { AppCommands(model: model) }

        Settings {
            AppSettingsView()
                .environment(model)
        }
    }
}
