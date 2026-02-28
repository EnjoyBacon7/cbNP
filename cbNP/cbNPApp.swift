//
//  cbNPApp.swift
//  cbNP
//
//  Created by Camille Bizeul on 8/8/25.
//

import SwiftUI

@main
struct cbNPApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra(
            "cbNP",
            systemImage: "characters.uppercase"
        ) {
            ContentView(viewModel: viewModel)
                .frame(width: 360, height: 500)
        }
        .menuBarExtraStyle(.window)
    }
}
