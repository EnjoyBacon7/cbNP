import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    private let labelWidth: CGFloat = 64
    private let fieldHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 320)
        .onAppear { viewModel.startIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.trackTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !viewModel.trackArtist.isEmpty {
                    Text(viewModel.trackArtist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(viewModel.connectionStatus.displayText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 8)

            Button {
                viewModel.updateNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help("Update now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var artwork: some View {
        let size: CGFloat = 50
        Group {
            if let image = viewModel.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 9) {
            field("Endpoint") {
                TextField("wss://…", text: $viewModel.endpointInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
            }

            field("Token") {
                SecureField("Auth token", text: $viewModel.tokenInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
            }

            row("Interval") {
                HStack(spacing: 8) {
                    TextField("15", text: $viewModel.intervalInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .frame(width: 48, height: fieldHeight)
                        .background(fieldBackground)
                    Text("seconds")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            row("Source") {
                Picker("", selection: $viewModel.selectedSource) {
                    ForEach(MediaSource.supportedInSwiftApp, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if !viewModel.sourceWarning.isEmpty {
                note(viewModel.sourceWarning, color: .orange)
            }

            if !viewModel.lastError.isEmpty {
                note(viewModel.lastError, color: .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // A labelled row whose trailing content fills a bordered field box.
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        row(label) {
            content()
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: fieldHeight, alignment: .leading)
                .background(fieldBackground)
        }
    }

    // A labelled row with arbitrary trailing content (no implicit field box).
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            content()
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.background)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, labelWidth + 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Save") { viewModel.savePreferencesFromInputs() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Button("Reconnect") { viewModel.reconnectNow() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch viewModel.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected, .invalidEndpoint: return .red
        }
    }
}
