import SwiftUI

struct PlugsPanel: View {
    @Environment(PlugsStore.self) private var store

    /// Warm "power on" yellow.
    static let accent = Color(red: 1.0, green: 0.82, blue: 0.38)

    var body: some View {
        VStack(spacing: 0) {
            if !store.hasLoaded {
                if case .failed(let message) = store.status {
                    ConnectionErrorView(
                        systemImage: "poweroutlet.type.f",
                        message: message,
                        detail: "Domo looks for Meross plugs on this Mac's network. Check they're powered and on the same Wi-Fi.",
                        onRetry: store.rescan
                    )
                } else {
                    SearchingView()
                }
            } else {
                VStack(spacing: 20) {
                    ForEach(store.strips) { strip in
                        StripSection(strip: strip)
                    }
                }
            }
            PanelFooter(status: status, menuTitle: "Meross Plugs", onRefresh: store.rescan)
                .padding(.top, 18)
        }
    }

    private var status: StatusLine {
        if let notice = store.notice { return .warning(notice) }
        return switch store.status {
        case .searching: StatusLine(text: "Looking for plugs…", symbol: "magnifyingglass")
        case .connected: .connected
        case .failed(let message): .warning(message)
        }
    }
}

private struct SearchingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Looking for Meross plugs…")
                .font(.system(size: 13, weight: .medium))
            Text("The first search takes a few seconds.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }
}

private struct StripSection: View {
    let strip: PowerStrip
    @Environment(PlugsStore.self) private var store
    @State private var isRenaming = false
    @State private var confirmsAllOff = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(store.name(of: strip))
                    .font(.system(size: 13, weight: .semibold))
                    .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
                        RenameField(title: "Rename strip", name: store.name(of: strip)) { store.rename(strip, to: $0) }
                    }
                if store.name(of: strip) != strip.displayModel {
                    Text(strip.displayModel)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(strip.outlets.filter(\.isOn).count) of \(strip.outlets.count) on")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Theme.easeOut(0.2), value: strip.outlets)
                Menu {
                    if strip.hasMasterSwitch {
                        Button("Turn All On") { store.setAll(in: strip, on: true) }
                        Button("Turn All Off…") { confirmsAllOff = true }
                        Divider()
                    }
                    Button("Rename…") { isRenaming = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(PressableStyle(scale: 0.9))
                .menuIndicator(.hidden)
                .accessibilityLabel("\(store.name(of: strip)) options")
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(strip.outlets) { outlet in
                    OutletTile(strip: strip, outlet: outlet)
                }
            }
        }
        // Channel 0 can take the router or this Mac's charger down with it.
        .confirmationDialog("Turn off everything on \(store.name(of: strip))?", isPresented: $confirmsAllOff) {
            Button("Turn All Off", role: .destructive) { store.setAll(in: strip, on: false) }
        } message: {
            Text("Whatever is plugged into it loses power, including a router or a charger.")
        }
    }
}

/// One outlet. Toggled tens of times a day, so the motion is only what
/// confirms the press: a 150ms color ease, the symbol filling, a small
/// press scale. Right-click to rename.
private struct OutletTile: View {
    let strip: PowerStrip
    let outlet: Outlet
    @Environment(PlugsStore.self) private var store
    @State private var isRenaming = false
    @State private var isHovered = false

    var body: some View {
        let name = store.name(of: outlet, in: strip)
        let icon = store.icon(of: outlet, in: strip)
        let accent = PlugsPanel.accent

        Button {
            store.toggle(outlet, in: strip)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    // Full color while powered, grey and faded while off.
                    Group {
                        if let image = icon.image {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                        } else {
                            Image(systemName: "poweroutlet.type.f")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .saturation(outlet.isOn ? 1 : 0)
                    .opacity(outlet.isOn ? 1 : 0.45)
                    Spacer()
                    Text(outlet.isOn ? "On" : "Off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(outlet.isOn ? accent : Color(white: 0.45))
                }
                Spacer(minLength: 8)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(outlet.isOn ? accent.opacity(0.14) : (isHovered ? Theme.surfaceHover : Theme.surface))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(outlet.isOn ? accent.opacity(0.35) : Theme.hairline)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .animation(Theme.ease(0.15), value: outlet.isOn)
        .animation(Theme.ease(0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Rename…") { isRenaming = true }
            Menu("Icon") {
                Button {
                    store.setIcon(nil, for: outlet, in: strip)
                } label: {
                    if store.hasCustomIcon(outlet, in: strip) { Text("Match Name") } else { Label("Match Name", systemImage: "checkmark") }
                }
                Divider()
                ForEach(OutletIcon.allCases) { option in
                    Button {
                        store.setIcon(option, for: outlet, in: strip)
                    } label: {
                        if store.hasCustomIcon(outlet, in: strip) && option == icon {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
        }
        .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
            RenameField(title: "Rename outlet", name: name) { store.rename(outlet, in: strip, to: $0) }
        }
        .help("Click to turn \(outlet.isOn ? "off" : "on"). Right-click to rename.")
        .accessibilityLabel(name)
        .accessibilityValue(outlet.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
