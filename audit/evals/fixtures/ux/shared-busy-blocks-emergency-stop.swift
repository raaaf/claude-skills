// Printer control panel: Pause, Resume and Stop all read the same `controlBusy`
// flag. The PrusaLink request timeout is 15 s, so a hanging Pause request keeps
// controlBusy true and leaves the emergency Stop button disabled for the full
// timeout — exactly when the user needs it. An abort action must own its busy
// flag and must not queue behind routine requests.
import SwiftUI

@MainActor
final class PrinterControlModel: ObservableObject {
    @Published var controlBusy = false

    private let client: PrusaLinkClient

    init(client: PrusaLinkClient) {
        self.client = client
    }

    func pause() async {
        controlBusy = true
        defer { controlBusy = false }
        try? await client.send(.pause)          // 15 s timeout
    }

    func resume() async {
        controlBusy = true
        defer { controlBusy = false }
        try? await client.send(.resume)
    }

    func stop() async {
        controlBusy = true
        defer { controlBusy = false }
        try? await client.send(.stop)
    }
}

struct PrinterControls: View {
    @ObservedObject var model: PrinterControlModel

    var body: some View {
        HStack(spacing: 12) {
            Button("Pause") { Task { await model.pause() } }
                .disabled(model.controlBusy)

            Button("Resume") { Task { await model.resume() } }
                .disabled(model.controlBusy)

            Button("Stop Print", role: .destructive) { Task { await model.stop() } }
                .disabled(model.controlBusy)
        }
    }
}
