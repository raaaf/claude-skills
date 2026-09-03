// App-wide design values. Colors are the single source of truth; views and
// tests should reference these constants rather than repeating hex values.
import SwiftUI

enum AppTheme {
    // Background changed 2026-08: linen read as yellowish next to the new
    // accent color, so it was swapped for parchment, a cooler off-white.
    static let background = Color(hex: "F1E9D8") // parchment
    static let accent = Color(hex: "2E6F5E")
}
