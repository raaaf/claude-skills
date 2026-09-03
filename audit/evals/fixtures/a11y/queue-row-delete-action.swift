// Print queue row: each job has a delete action. To keep the row visually
// quiet, the delete button only appears while the pointer is over the row.
// macOS is a mixed input device though: trackpad users without a pointer
// gesture, external keyboard users tabbing through the list, and VoiceOver
// users never trigger .onHover, so the delete action has no other path to
// reach it. A row action must stay reachable without hover.
import SwiftUI

struct QueueRow: View {
    let job: PrintJob
    let onDelete: (PrintJob) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(job.name)
            Spacer()
            Text(job.status)
                .foregroundStyle(.secondary)

            // BUG: the only way to reveal or activate delete is a hover
            // gesture. No .accessibilityActions and no always-visible
            // keyboard-reachable control exist for this row.
            Button(role: .destructive) {
                onDelete(job)
            } label: {
                Image(systemName: "trash")
            }
            .opacity(isHovering ? 1 : 0)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
