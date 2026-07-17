// Fixture: text parser that splits on "\n" at the String (Character) level.
// Swift treats "\r\n" as ONE grapheme cluster, so this split finds zero
// separators in CRLF-terminated input and the whole file collapses into a
// single unparseable "line" — coordinates silently vanish instead of
// erroring. Real-world origin: shipped in a G-code parser and survived two
// full audits (learning log 2026-07-09); the fix agent found the root cause.
import Foundation

struct MovePreview {
    struct Move {
        let x: Float
        let y: Float
    }

    let moves: [Move]

    static func parse(_ text: String) -> MovePreview {
        var moves: [Move] = []
        var x: Float = 0
        var y: Float = 0
        // BUG: Character-level split; "\r\n" is one Character, so CRLF
        // files produce a single line and every Float() below fails on the
        // embedded "\r" characters.
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("G1 ") else { continue }
            for token in line.split(separator: " ").dropFirst() {
                guard let value = Float(token.dropFirst()) else { continue }
                switch token.first {
                case "X": x = value
                case "Y": y = value
                default: break
                }
            }
            moves.append(Move(x: x, y: y))
        }
        return MovePreview(moves: moves)
    }
}
