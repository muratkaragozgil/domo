import AppKit
import SwiftUI

/// First-run and "Change Token…" screen, shared by every integration that
/// needs a secret: a few steps, one field, one button. The integration
/// checks the token before anything is saved.
struct TokenSetupView: View {
    let title: String
    let summary: String
    /// Markdown, so steps can carry **bold** and [links](https://…).
    let steps: [LocalizedStringKey]
    let placeholder: String
    let footnote: String
    var canCancel = false
    let onConnect: (String) async -> String?
    var onDone: () -> Void = {}

    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?
    @FocusState private var isFieldFocused: Bool

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
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

            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index + 1, step)
                }
            }
            .font(.system(size: 13))
            .tint(Theme.tint(for: "COOL"))
            .padding(.top, 16)

            tokenField
                .padding(.top, 16)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            connectButton
                .padding(.top, 12)

            Text(footnote)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.easeOut(0.2), value: error)
        .onAppear { isFieldFocused = true }
    }

    private func stepRow(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background { Circle().fill(Theme.surface).overlay { Circle().strokeBorder(Theme.hairline) } }
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tokenField: some View {
        HStack(spacing: 8) {
            SecureField(placeholder, text: $token)
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
        .animation(Theme.easeOut(0.15), value: isConnecting)
        .animation(Theme.ease(0.15), value: trimmedToken.isEmpty)
    }

    private func connect() {
        guard !trimmedToken.isEmpty, !isConnecting else { return }
        isConnecting = true
        error = nil
        Task {
            let message = await onConnect(trimmedToken)
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
