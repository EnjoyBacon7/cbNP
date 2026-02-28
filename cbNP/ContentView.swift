import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("cbNP")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("Status: \(viewModel.connectionStatus)")
                Text("Track: \(viewModel.currentTrackTitle)")
                    .lineLimit(2)
            }
            .font(.subheadline)

            if !viewModel.sourceWarning.isEmpty {
                Text(viewModel.sourceWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Preferences")
                    .font(.headline)

                TextField("WebSocket endpoint", text: $viewModel.endpointInput)
                    .textFieldStyle(.roundedBorder)

                SecureField("Auth token", text: $viewModel.tokenInput)
                    .textFieldStyle(.roundedBorder)

                TextField("Interval (seconds)", text: $viewModel.intervalInput)
                    .textFieldStyle(.roundedBorder)

                Picker("Source", selection: $viewModel.selectedSource) {
                    ForEach(MediaSource.supportedInSwiftApp, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 10) {
                Button("Save") { viewModel.savePreferencesFromInputs() }
                Button("Update now") { viewModel.updateNow() }
                Button("Reconnect") { viewModel.reconnectNow() }
            }

            if !viewModel.lastError.isEmpty {
                Text(viewModel.lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .onAppear { viewModel.startIfNeeded() }
        .frame(minWidth: 340, minHeight: 420)
    }
}
