import AppKit
import SwiftUI

/// `Domo --snapshot <path.png> [flags]` renders the panel with demo data and
/// quits. Used to check the design without clicking the menu bar.
enum Snapshot {
    static var request: (path: String, isOn: Bool)? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else { return nil }
        return (args[index + 1], !args.contains("--off"))
    }

    /// `Domo --icon <path.png>` writes the 1024pt app icon.
    static var iconRequest: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--icon"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static func renderIcon(to path: String) {
        let tint = Theme.tint(for: "COOL")
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(RadialGradient(colors: [tint.opacity(0.45), .clear], center: .bottom, startRadius: 0, endRadius: 520))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 3)
                }
                .frame(width: 824, height: 824)
            ACUnitView(isOn: true, tint: tint)
                .scaleEffect(2.5)
        }
        .frame(width: 1024, height: 1024)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        exit(0)
    }

    private static var window: NSWindow?

    /// Flags: `--tab climate|feeder|plugs`, `--off` (AC powered off), `--live`
    /// (real devices), `--setup` (token screen), `--swiftui` (draws blurs).
    static func run(path: String, isOn: Bool) {
        let args = CommandLine.arguments
        let live = args.contains("--live")
        let tab = args.firstIndex(of: "--tab").flatMap { args.indices.contains($0 + 1) ? AccessoryKind(rawValue: args[$0 + 1]) : nil } ?? .climate
        let climate = live ? AirConditionerStore() : AirConditionerStore(demo: isOn)
        let feeder = live ? CatFeederStore() : CatFeederStore(demo: true)
        let plugs = live ? PlugsStore() : PlugsStore(demo: true)

        func panel() -> some View {
            RootPanel(forcedSelection: tab, startsEditingToken: args.contains("--setup"))
                .environment(climate)
                .environment(feeder)
                .environment(plugs)
                .environment(\.colorScheme, .dark)
        }

        let hosting = NSHostingView(rootView: panel())
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.orderFrontRegardless()
        self.window = window

        Task {
            if live {
                let loaded = {
                    switch tab {
                    case .climate: climate.hasLoaded
                    case .feeder: feeder.hasLoaded
                    case .plugs: plugs.hasLoaded
                    }
                }
                for _ in 0..<60 where !loaded() { try? await Task.sleep(for: .milliseconds(250)) }
                hosting.frame.size = hosting.fittingSize
                window.setContentSize(hosting.fittingSize)
            }
            // Let layout and transitions settle before capturing.
            try? await Task.sleep(for: .seconds(1.2))
            // ImageRenderer draws blurs and glows; cacheDisplay draws native menus.
            if args.contains("--swiftui") {
                let renderer = ImageRenderer(content: panel())
                renderer.scale = 2
                if let tiff = renderer.nsImage?.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                exit(0)
            }
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
