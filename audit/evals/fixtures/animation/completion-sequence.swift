// Fixture: a transition that cannot be seen, because its start state and its
// end state are assigned in the same main-actor pass. SwiftUI renders once at
// the end of the pass, so no frame ever carries the start value and the
// animation is a no-op with a cost.
//
// The give-away is structural, not aesthetic: `leaving = true` and
// `leaving = false` (via `step = .complete`) happen with no suspension point
// between them. No `await`, no `Task` hop, no second render.
//
// Included below: the same effect written correctly, so the finding has to name
// the mechanism rather than "animations are unreliable".
//
// Real-world origin: three consecutive rounds were spent tuning the VALUES of
// this effect (a scale factor, a sequenced swap, a keyboard delay) while the
// user kept reporting "I don't see it". Two of the three rounds were tuning a
// no-op. The rule that came out of it: prove it runs before asking whether it
// is strong enough.
import SwiftUI

enum Step {
    case writing
    case complete
}

struct CompletionCard: View {
    @State private var step: Step = .writing
    @State private var contentLeaving = false
    @State private var answerArrived = false
    @State private var recedeScale: CGFloat = 1.0

    var body: some View {
        VStack {
            if step == .writing {
                Text("Composer")
                    .opacity(contentLeaving ? 0 : 1)
                    .offset(y: contentLeaving ? 12 : 0)
            } else {
                Text("Answer")
                    .opacity(answerArrived ? 1 : 0)
            }
        }
        .scaleEffect(recedeScale)
    }

    // BUG: every state change below happens in one synchronous pass. The frame
    // with `contentLeaving == true` and `recedeScale == 0.97` is never drawn;
    // the view goes straight to its final state. Adjusting 0.97, the durations
    // or the offsets changes nothing at all.
    func finish() {
        withAnimation(.easeOut(duration: 0.25)) {
            contentLeaving = true
            recedeScale = 0.97
        }
        step = .complete
        withAnimation(.easeIn(duration: 0.3)) {
            answerArrived = true
            recedeScale = 1.0
        }
    }

    // CORRECT: the start state gets a pass of its own before the end state is
    // set, so both halves are actually drawn.
    func finishCorrectly() async {
        withAnimation(.easeOut(duration: 0.25)) {
            contentLeaving = true
            recedeScale = 0.97
        }
        try? await Task.sleep(for: .seconds(0.25))
        step = .complete
        withAnimation(.easeIn(duration: 0.3)) {
            answerArrived = true
            recedeScale = 1.0
        }
    }
}
