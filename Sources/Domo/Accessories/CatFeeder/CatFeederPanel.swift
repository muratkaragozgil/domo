import SwiftUI

struct CatFeederPanel: View {
    @Environment(CatFeederStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var isEditingToken = false

    /// Warm kibble amber; this panel's counterpart to the AC's mode tint.
    static let accent = Color(red: 0.96, green: 0.72, blue: 0.42)

    var body: some View {
        VStack(spacing: 0) {
            if store.needsToken || isEditingToken {
                FeederTokenView(canCancel: !store.needsToken) { isEditingToken = false }
            } else if !store.hasLoaded, case .failed(let message) = store.status {
                ConnectionErrorView(
                    systemImage: "cat",
                    message: message,
                    detail: "Check that the feeder is plugged in and this Mac is on the same Wi-Fi. Domo looks again every few minutes.",
                    onRetry: store.reload
                )
            } else {
                header
                FeederIllustration(feedCount: store.feedCount, portions: store.portions)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                VStack(spacing: 0) {
                    portionsRow
                    feedButton
                        .padding(.top, 14)
                    tiles
                        .padding(.top, 18)
                }
                .redacted(reason: store.hasLoaded ? [] : .placeholder)
                .allowsHitTesting(store.hasLoaded)
            }
            PanelFooter(status: status, menuTitle: "Cat Feeder", onRefresh: store.reload) {
                isEditingToken = true
            }
            .padding(.top, 18)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            if let meal = store.nextMeal {
                Text("Next meal")
                    .foregroundStyle(.secondary)
                Text(meal.time)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text("· \(Self.portions(meal.portions))")
                    .foregroundStyle(.secondary)
            } else {
                Text(store.isScheduleOn ? "No meals scheduled" : "Schedule paused")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.system(size: 15))
        .frame(height: 40)
        .accessibilityElement(children: .combine)
    }

    private var portionsRow: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(store.portions)")
                    .font(.system(size: 64, weight: .semibold))
                    .tracking(-2)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(store.portions)))
                Text(store.portions == 1 ? "portion" : "portions")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .animation(Theme.spring(reduceMotion), value: store.portions)
            .accessibilityElement(children: .combine)

            Spacer()

            HStack(spacing: 10) {
                StepButton(systemImage: "minus", label: "Fewer portions") { store.setPortions(store.portions - 1) }
                    .disabled(store.portions <= CatFeederStore.portionRange.lowerBound)
                StepButton(systemImage: "plus", label: "More portions") { store.setPortions(store.portions + 1) }
                    .disabled(store.portions >= CatFeederStore.portionRange.upperBound)
            }
        }
    }

    /// Idle → spinner while the feeder works → a checkmark once it confirms.
    /// Each state swaps with a short blur so the label reads as one morphing thing.
    private var feedButton: some View {
        Button(action: store.feed) {
            Group {
                switch store.feedState {
                case .idle:
                    Label("Feed \(Self.portions(store.portions))", systemImage: "fork.knife")
                        .contentTransition(.numericText(value: Double(store.portions)))
                case .feeding:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                        Text("Feeding…")
                    }
                case .fed:
                    Label("Fed", systemImage: "checkmark")
                }
            }
            .id(store.feedState)
            .transition(.blurReplace)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(store.feedState != .idle)
        .animation(Theme.easeOut(0.2), value: store.feedState)
        .animation(Theme.spring(reduceMotion), value: store.portions)
        .accessibilityLabel("Feed \(Self.portions(store.portions))")
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            StatusTile(
                title: "Food",
                value: store.foodLevel.title,
                systemImage: "fork.knife",
                iconTint: Self.accent,
                valueTint: foodTint
            )
            MenuTile(
                title: "Schedule",
                value: store.isScheduleOn ? "\(store.meals.count) meals" : "Paused",
                systemImage: "calendar",
                valueTint: store.isScheduleOn ? .primary : .orange
            ) {
                if !store.meals.isEmpty {
                    Section("\(Self.portions(store.dailyPortions)) a day") {
                        ForEach(store.meals) { meal in
                            Text("\(meal.time)    \(Self.portions(meal.portions))")
                        }
                    }
                }
                Toggle("Feed on Schedule", isOn: Binding(get: { store.isScheduleOn }, set: { store.setSchedule(on: $0) }))
            }
            MenuTile(
                title: "Desiccant",
                value: desiccantText,
                systemImage: "humidity",
                valueTint: store.desiccantDays == 0 ? .orange : .primary
            ) {
                Text("A pack keeps food dry for about 30 days.")
                Button("Reset After Replacing", action: store.resetDesiccant)
            }
        }
    }

    // MARK: - Text

    static func portions(_ count: Int) -> String {
        count == 1 ? "1 portion" : "\(count) portions"
    }

    private var foodTint: Color {
        switch store.foodLevel {
        case .normal: .primary
        case .low: .orange
        case .empty: .red
        }
    }

    private var desiccantText: String {
        guard let days = store.desiccantDays else { return "—" }
        return days == 0 ? "Replace" : "\(days) days"
    }

    private var status: StatusLine {
        if let notice = store.notice { return .warning(notice) }
        if store.hasFault { return .warning("Feeder reports a fault") }
        if store.foodLevel == .empty { return .warning("Food container is empty") }
        return switch store.status {
        case .connecting: .connecting
        case .connected: .connected
        case .failed(let message): .warning(message)
        }
    }
}

struct FeederTokenView: View {
    var canCancel = false
    var onDone: () -> Void = {}
    @Environment(CatFeederStore.self) private var store

    var body: some View {
        TokenSetupView(
            title: "Connect your cat feeder",
            summary: "Domo talks to the feeder directly over your Wi-Fi, using its Xiaomi device token.",
            steps: [
                "Run [Xiaomi Cloud Tokens Extractor ↗](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) and sign in with your Xiaomi account.",
                "Copy the token of the device whose model starts with **mmgg.feeder**.",
                "Paste it here. Domo finds the feeder on your network by itself.",
            ],
            placeholder: "32-character device token",
            footnote: "Stored only on this Mac, in ~/.config/xiaomi-feeder.",
            canCancel: canCancel,
            onConnect: { await store.connect(token: $0) },
            onDone: onDone
        )
    }
}
