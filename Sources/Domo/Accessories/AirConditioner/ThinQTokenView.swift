import SwiftUI

struct ThinQTokenView: View {
    var canCancel = false
    var onDone: () -> Void = {}
    @Environment(AirConditionerStore.self) private var store

    var body: some View {
        TokenSetupView(
            title: "Connect to LG ThinQ",
            summary: "Domo talks to your AC through LG's official API using a personal access token from your LG account.",
            steps: [
                "Sign in at [connect-pat.lgthinq.com ↗](https://connect-pat.lgthinq.com).",
                "Add a new token with **view devices**, **view device status** and **device control**.",
                "Paste it here.",
            ],
            placeholder: "Personal access token",
            footnote: "Stored only on this Mac, in ~/.config/lg-thinq.",
            canCancel: canCancel,
            onConnect: { await store.connect(token: $0) },
            onDone: onDone
        )
    }
}
