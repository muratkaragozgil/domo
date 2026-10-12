import AppKit
import SwiftUI

/// First-run and "Change Token…" screen. Three steps, one field, one button.
struct ThinQTokenView: View {
    var canCancel = false
    var onDone: () -> Void = {}

    @Environment(AirConditionerStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?
    @FocusState private var isFieldFocused: Bool

    private static let tokenPage = URL(string: "https://connect-pat.lgthinq.com")!

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Connect to LG ThinQ")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if canCancel {
                    Button("Cancel", action: onDone)
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                }
            }

            Text("Domo talks to your AC through LG's official API using a personal access token from your LG account.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 12) {
                step(1) {
                    HStack(spacing: 4) {
                        Text("Sign in at")
                        Button {
                            openURL(Self.tokenPage)
                        } label: {
                            HStack(spacing: 2) {
                                Text("connect-pat.lgthinq.com")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Theme.tint(for: "COOL"))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                step(2) {
                    Text("Add a new token with **view devices**, **view device status** and **device control**.")
                }
                step(3) {
                    Text("Paste it here.")
                }
            }
            .font(.system(size: 13))
            .padding(.top, 16)

            tokenField
                .padding(.top, 16)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            connectButton
                .padding(.top, 12)

            Text("Stored only on this Mac, in ~/.config/lg-thinq.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: error)
        .onAppear { isFieldFocused = true }
    }

    private func step(_ number: Int, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background { Circle().fill(Theme.surface).overlay { Circle().strokeBorder(Theme.hairline) } }
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tokenField: some View {
        HStack(spacing: 8) {
            SecureField("Personal access token", text: $token)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($isFieldFocused)
                .onSubmit(connect)
            // ⌘V can be unreliable in menu bar apps; one click always works.
            Button {
                if let pasted = NSPasteboard.general.string(forType: .string) {
                    token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    error = nil
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .help("Paste from clipboard")
            .accessibilityLabel("Paste from clipboard")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background { SurfaceBackground(radius: 10) }
        .onChange(of: token) { error = nil }
    }

    private var connectButton: some View {
        Button(action: connect) {
            ZStack {
                Text("Connect")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(isConnecting ? 0 : 1)
                ProgressView()
                    .controlSize(.small)
                    .tint(.black)
                    .opacity(isConnecting ? 1 : 0)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(trimmedToken.isEmpty ? 0.35 : 1))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(trimmedToken.isEmpty || isConnecting)
        .keyboardShortcut(.defaultAction)
        .animation(.easeOut(duration: 0.15), value: isConnecting)
        .animation(.easeOut(duration: 0.15), value: trimmedToken.isEmpty)
    }

    private func connect() {
        guard !trimmedToken.isEmpty, !isConnecting else { return }
        isConnecting = true
        error = nil
        Task {
            let message = await store.connect(token: token)
            isConnecting = false
            if let message {
                error = message
            } else {
                token = ""
                onDone()
            }
        }
    }
}
