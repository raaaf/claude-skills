// AdaptRecipeSheet: applying a suggested edit mutates the @Bindable Recipe
// in place before persisting (SwiftData mutates eagerly). When context.save()
// throws, the in-memory model already reflects the edit -- the catch block
// only flips an error flag, it never reverts the mutation. The user's
// "Retry" button then calls back into the backend for a fresh set of
// suggestions instead of just re-attempting the local save of the edit that
// is already sitting in memory. Every failed save the user retries burns one
// unit of the daily adapt quota for a request that never needed the network.
import SwiftUI
import SwiftData

@MainActor
final class AdaptRecipeSheetModel: ObservableObject {
    @Published var saveFailed = false
    private let client: AdaptRecipeClient

    init(client: AdaptRecipeClient) {
        self.client = client
    }

    func apply(_ change: RecipeChange, to recipe: Recipe, context: ModelContext) {
        change.mutate(recipe)   // eager in-memory mutation on the @Bindable model

        do {
            try context.save()
            saveFailed = false
        } catch {
            saveFailed = true
            // BUG: `recipe` now holds the mutated, unsaved state. Nothing here
            // reverts it, and nothing here retries `context.save()` either.
        }
    }

    func retry(for recipe: Recipe, context: ModelContext) {
        Task {
            // BUG: retry goes back to the network for new suggestions and
            // burns adaptSubjectQuota, even though the fix is a pure local
            // persistence retry -- no new suggestions are needed, the edit
            // the user already approved is still sitting unsaved on `recipe`.
            _ = try? await client.refetchSuggestions(for: recipe)
        }
    }
}
