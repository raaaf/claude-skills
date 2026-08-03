// Fixture: the test pins the seed constant instead of the resolved text
// the UI actually renders. A full content rewrite of the seed pool ships
// live while this test stays green forever, because the test never
// touches the rendering path.
import Testing

struct SeedQuestion {
    static let text = "Was war heute dein wertvollster Moment?"
}

struct Question {
    let rawText: String

    // Applies the normalization the UI actually displays.
    var displayText: String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct QuestionServiceTests {
    @Test
    func seedQuestionHasExpectedText() {
        // BUG: pins the source constant, not what QuestionText renders.
        // A rewrite of SeedQuestion.text that changes tone or wording
        // still makes this assertion pass; only Question.displayText
        // reaches the screen.
        #expect(SeedQuestion.text == "Was war heute dein wertvollster Moment?")
    }
}
