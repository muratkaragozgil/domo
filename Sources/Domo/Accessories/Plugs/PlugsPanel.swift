import SwiftUI

struct PlugsPanel: View {
    @Environment(PlugsStore.self) private var store

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

/// One outlet: the device's picture, its name, and Domo's switch. The tile
/// stays neutral; state reads from the switch and the picture, which is in
/// color while powered and grey while off. Clicking anywhere on the tile
/// flips it too, so the target is the whole tile, not just the switch.
/// Right-click to rename or change the picture.
private struct OutletTile: View {
    let strip: PowerStrip
    let outlet: Outlet
    @Environment(PlugsStore.self) private var store
    @State private var isRenaming = false
    @State private var isHovered = false

    var body: some View {
        let name = store.name(of: outlet, in: strip)
        let icon = store.icon(of: outlet, in: strip)

        Button {
            store.toggle(outlet, in: strip)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                artwork(icon)
                    .frame(height: 36, alignment: .topLeading)
                    .saturation(outlet.isOn ? 1 : 0)
                    .opacity(outlet.isOn ? 1 : 0.5)
                Spacer(minLength: 8)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(outlet.isOn ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .leading)
            .background { SurfaceBackground(radius: 12, isHovered: isHovered) }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .accessibilityHidden(true) // the switch below is the accessible control
        .overlay(alignment: .topTrailing) {
            DomoSwitch(label: name, isOn: outlet.isOn) { store.toggle(outlet, in: strip) }
                .padding(10)
                .help("Turn \(name) \(outlet.isOn ? "off" : "on")")
        }
        .animation(Theme.ease(0.15), value: outlet.isOn)
        .onHover { isHovered = $0 }
        .contextMenu { menu(icon: icon) }
        .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
            RenameField(title: "Rename outlet", name: name) { store.rename(outlet, in: strip, to: $0) }
        }
    }

    @ViewBuilder
    private func artwork(_ icon: OutletIcon) -> some View {
        if let photo = store.photo(of: outlet, in: strip) {
            Image(nsImage: photo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                // Narrow enough to clear the switch in the top-right corner.
                .frame(maxWidth: 50, maxHeight: 36, alignment: .leading)
                // A soft light behind it: real devices are often black.
                .background {
                    RadialGradient(colors: [.white.opacity(0.2), .clear], center: .center, startRadius: 2, endRadius: 36)
                        .frame(width: 66, height: 48)
                }
        } else if let image = icon.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "poweroutlet.type.f")
                .resizable()
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private func menu(icon: OutletIcon) -> some View {
        Button("Rename…") { isRenaming = true }
        Menu("Icon") {
            Button("Choose Image…") { store.choosePhoto(for: outlet, in: strip) }
            if store.photo(of: outlet, in: strip) != nil {
                Button("Remove Image") { store.removePhoto(for: outlet, in: strip) }
            }
            Divider()
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
}
