import SwiftUI

@main
struct cbNPApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra("cbNP", image: "MenuBarIcon") {
            ContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
