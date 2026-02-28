import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            preferencesSection
            Divider()
            footerSection
        }
        .frame(width: 340)
        .onAppear { viewModel.startIfNeeded() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AppIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentTrackTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(viewModel.connectionStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                viewModel.updateNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help("Update now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(label: "Endpoint") {
                TextField("wss://…", text: $viewModel.endpointInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
            }

            LabeledField(label: "Token") {
                SecureField("Auth token", text: $viewModel.tokenInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
            }

            LabeledField(label: "Interval") {
                HStack(spacing: 4) {
                    TextField("15", text: $viewModel.intervalInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(maxWidth: 40)
                    Text("s")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            LabeledField(label: "Source") {
                Picker("", selection: $viewModel.selectedSource) {
                    ForEach(MediaSource.supportedInSwiftApp, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if !viewModel.sourceWarning.isEmpty {
                Text(viewModel.sourceWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !viewModel.lastError.isEmpty {
                Text(viewModel.lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 8) {
            Button("Save") { viewModel.savePreferencesFromInputs() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Button("Reconnect") { viewModel.reconnectNow() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch viewModel.connectionStatus {
        case "Connected": return .green
        case "Connecting...": return .yellow
        default: return .red
        }
    }
}

// MARK: - LabeledField

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )

                content()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
