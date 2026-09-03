// Article reader: each section streams narration audio from the network.
// Swiping to the next section cancels the previous section's fetch task and
// starts a new one. If the network narration is unavailable, the section
// falls back to on-device speech synthesis.
import AVFoundation

@MainActor
final class SectionPlayer: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var currentTask: Task<Void, Never>?

    func play(section: ArticleSection) {
        currentTask?.cancel()
        currentTask = Task {
            do {
                let audio = try await fetchNarration(for: section)
                try Task.checkCancellation()
                playNetworkAudio(audio)
            } catch {
                // BUG: this fallback runs even when the fetch failed because
                // the task above was cancelled (user already swiped to the
                // next section). There is no Task.isCancelled check here, so
                // the synthesizer starts reading section N out loud while
                // section N+1's network audio is already playing.
                speakFallback(for: section)
            }
        }
    }

    private func speakFallback(for section: ArticleSection) {
        let utterance = AVSpeechUtterance(string: section.plainText)
        synthesizer.speak(utterance)
    }

    private func fetchNarration(for section: ArticleSection) async throws -> Data {
        try await URLSession.shared.data(from: section.narrationURL).0
    }

    private func playNetworkAudio(_ data: Data) {
        // hands off to the shared AVAudioPlayer instance
    }
}
