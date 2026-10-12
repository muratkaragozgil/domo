import AppKit
import ServiceManagement
import SwiftUI

/// One line at the bottom of every panel: how the connection is doing.
struct StatusLine: Equatable {
    var text: String
    var symbol: String
    var isWarning = false

    static let connecting = StatusLine(text: "Connecting…", symbol: "arrow.triangle.2.circlepath")
    static let connected = StatusLine(text: "Connected", symbol: "checkmark.shield")
    static func warning(_ text: String) -> StatusLine {
        StatusLine(text: text, symbol: "exclamationmark.triangle", isWarning: true)
    }
}

struct PanelFooter: View {
    let status: StatusLine
    let menuTitle: String
    let onRefresh: () -> Void
    var onChangeToken: (() -> Void)? = nil

    var body: some View {
        HStack {
            Label(status.text, systemImage: status.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.isWarning ? Color.orange : Color.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(Theme.ease(0.2), value: status)

            Spacer()

            SettingsMenu(title: menuTitle, onRefresh: onRefresh, onChangeToken: onChangeToken)
        }
    }
}

struct SettingsMenu: View {
    let title: String
    let onRefresh: () -> Void
    var onChangeToken: (() -> Void)? = nil

    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Section(title) {
                Button("Refresh Now", action: onRefresh)
                    .keyboardShortcut("r")
                if let onChangeToken {
                    Button("Change Token…", action: onChangeToken)
                }
            }
            Divider()
            Toggle("Open at Login", isOn: $opensAtLogin)
            Button("Quit Domo") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle(scale: 0.9))
        .menuIndicator(.hidden)
        .accessibilityLabel("Settings")
        .onChange(of: opensAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                opensAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

/// Couldn't reach the device before its first load.
struct ConnectionErrorView: View {
    let systemImage: String
    let message: String
    let detail: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 17, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background { SurfaceBackground(radius: 8) }
            }
            .buttonStyle(PressableStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
