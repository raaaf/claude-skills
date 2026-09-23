<?php

namespace App\Livewire\Tax;

use App\Models\Tax\TaxTransaction;
use Livewire\Component;

class TransactionReview extends Component
{
    public array $selected = [];

    public int $quarterFilter;

    // Single-row path: TaxTransaction has a saving() observer that throws
    // when the transaction's quarter is locked, so this is safe.
    public function markPrivate(int $transactionId): void
    {
        $transaction = TaxTransaction::forUser(auth()->id())->findOrFail($transactionId);
        $transaction->update(['classification' => 'private']);
    }

    // BUG: query-builder bulk update bypasses the model observer entirely
    // (update() here runs on the Builder, not on a hydrated model), so this
    // silently rewrites transactions in a locked/reported quarter.
    public function bulkMarkBusiness(): void
    {
        TaxTransaction::forUser(auth()->id())
            ->whereIn('id', $this->selected)
            ->update(['classification' => 'business']);
    }

    // BUG: same bypass, second occurrence in the same file. A reviewer (or
    // an audit) that stops after flagging bulkMarkBusiness() above will
    // miss this one, which is the actual defect this fixture pins: every
    // mass-update path needs its own finding, not just the first.
    public function confirmAll(): void
    {
        TaxTransaction::forUser(auth()->id())
            ->where('quarter', $this->quarterFilter)
            ->update(['reviewed' => true]);
    }
}
