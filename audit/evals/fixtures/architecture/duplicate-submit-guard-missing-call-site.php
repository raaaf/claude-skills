<?php

namespace App\Livewire;

use App\Models\DateSuggestion;
use App\Models\WishItem;
use App\Traits\PreventsDuplicateSubmit;
use Livewire\Component;

// Rollout batch: PreventsDuplicateSubmit was added to all create flows
// without a DB unique constraint. This call site got the guard:
class SuggestDateForm extends Component
{
    use PreventsDuplicateSubmit;

    public string $date = '';

    public function save(): void
    {
        if (! $this->acquireSubmitLock('date-suggestion:'.$this->event->id)) {
            return;
        }

        DateSuggestion::create([
            'event_id' => $this->event->id,
            'date' => $this->date,
        ]);
    }
}

// BUG: structurally identical create flow from the same rollout batch, but
// the guard trait is missing — a double-click or second tab creates
// duplicate wish rows. The rollout covered only the diff's call sites;
// this component was never touched.
class SecretWishForm extends Component
{
    public string $title = '';

    public function save(): void
    {
        WishItem::create([
            'event_id' => $this->event->id,
            'title' => $this->title,
        ]);
    }
}
