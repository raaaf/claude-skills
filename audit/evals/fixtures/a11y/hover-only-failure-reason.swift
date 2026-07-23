// History row: a failed print used to render its failure reason as visible text
// under the file name. A "reduce visual noise" fix moved it into .help(), a
// hover-only tooltip. Keyboard users, VoiceOver and trackpad-less/touch input
// never reach it — the only explanation of WHY the print failed is now
// unreachable for them. Visible information must not degrade to hover-only.
import SwiftUI

struct HistoryRow: View {
    let entry: PrintHistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(entry.failed ? .red : .green)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .font(.body)
                Text(entry.startedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .help(entry.failureReason ?? "")
    }
}
