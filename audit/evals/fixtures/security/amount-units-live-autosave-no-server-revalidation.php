<?php

namespace App\Livewire\Wizard\Steps;

use App\Livewire\Wizard\Steps\Concerns\ResolvesSubscription;
use Livewire\Attributes\Validate;
use Livewire\Component;

/**
 * Fixture: live-bound financial field whose background autosave bypasses
 * its own step's validation, with no re-validation anywhere in the submit
 * path (real case: /audit 2026-09-16, digitale-zeichnungsstrecke).
 *
 * `units`/`amount` are bound wire:model.live so the price preview updates
 * as the user types. The autosave fires on every live update and persists
 * straight to the DB. But autosave() never calls validate(), and it is the
 * ONLY write path for these two columns: nextStep() only reads them back
 * to compute a display total, and the final submit transition never
 * touches amount/units again. A negative or out-of-range value entered
 * here reaches subscriptions.amount/units untouched, all the way to the
 * PDF and the CSV export.
 */
class ProductAmountStep extends Component
{
    use ResolvesSubscription;

    #[Validate('required|integer|min:1|max:1000')]
    public int $units = 1;

    #[Validate('required|numeric|min:1000')]
    public float $amount = 1000.0;

    // BUG: fires on every wire:model.live keystroke and writes straight to
    // the subscription, bypassing the #[Validate] attributes above (those
    // only apply when validate() is called explicitly, which this method
    // never does).
    public function autosave(): void
    {
        $subscription = $this->resolveSubscription();

        $subscription->update([
            'units' => $this->units,
            'amount' => $this->amount,
        ]);
    }

    // Only re-reads the already-persisted values to render a price
    // preview; never re-validates or re-writes amount/units. A value
    // smuggled in via autosave() above sails through here unchecked.
    public function nextStep(): void
    {
        $subscription = $this->resolveSubscription();

        $this->dispatch('amount-confirmed', total: $subscription->amount);

        $this->goToNextStep();
    }
}
