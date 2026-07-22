// Voice picker: tapping a voice both plays a preview sample AND posts a
// VoiceOver announcement. There is no central audio guard, so with VoiceOver
// active the preview audio plays on top of the announcement and both are
// unintelligible. Any audio-producing control must route through a shared
// guard that defers (or ducks) app audio while an announcement is in flight.
import SwiftUI
import AVFoundation

struct VoicePickerRow: View {
    let voice: TTSVoice
    let isSelected: Bool
    let onSelect: (TTSVoice) -> Void

    var body: some View {
        Button {
            onSelect(voice)
            // Preview so the user hears the voice they just picked.
            TTSService.shared.play(sample: voice.sampleURL)
            // Announce the change for VoiceOver users.
            UIAccessibility.post(notification: .announcement, argument: "Stimme \(voice.displayName) gewählt")
        } label: {
            HStack {
                Text(voice.displayName)
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}
