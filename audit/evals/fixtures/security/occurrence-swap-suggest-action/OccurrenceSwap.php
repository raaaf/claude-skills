<?php

namespace App\Livewire;

use App\Models\Occurrence;
use Livewire\Component;

class OccurrenceSwap extends Component
{
    public Occurrence $occurrence;
    public bool $isSeriesMember;
    public $guestRow = null;

    public function mount(Occurrence $occurrence)
    {
        $this->occurrence = $occurrence;

        // Membership in the series as a whole - true for anyone added to
        // the recurring series, regardless of whether they have a row for
        // THIS specific occurrence yet.
        $this->isSeriesMember = $occurrence->series->members()
            ->where('user_id', auth()->id())
            ->exists();

        $this->guestRow = $occurrence->guestRows()
            ->where('user_id', auth()->id())
            ->first();
    }

    public function proposeSwap()
    {
        // The server guard is narrower than the Blade gate in the view:
        // it requires a guest row for this occurrence, not just series
        // membership. A member who joined after this occurrence was
        // generated has no row yet, still sees the button, and gets a
        // silent 403 - the action can never succeed for them.
        abort_unless($this->guestRow, 403);

        $this->guestRow->update(['swap_requested' => true]);
    }
}
