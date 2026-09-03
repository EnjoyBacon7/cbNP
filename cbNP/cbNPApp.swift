import SwiftUI

@main
struct cbNPApp: App {
    @State private var viewModel: AppViewModel

    init() {
        let viewModel = AppViewModel()
        _viewModel = State(initialValue: viewModel)

        // MenuBarExtra builds its content lazily, only once the popover is
        // opened, so starting the timers from ContentView.onAppear left the app
        // publishing nothing after launch until the icon happened to be
        // clicked. Start them at launch, where the app lifecycle belongs.
        viewModel.startIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra("cbNP", image: "MenuBarIcon") {
            ContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
