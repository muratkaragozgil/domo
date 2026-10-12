import SwiftUI

/// Small popover for naming something. Empty restores the default name.
struct RenameField: View {
    let title: String
    let onSave: (String) -> Void

    @State private var name: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, name: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($isFocused)
                .onSubmit(save)
            HStack {
                Text("Leave empty for the default.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .onAppear { isFocused = true }
    }

    private func save() {
        onSave(name)
        dismiss()
    }
}
