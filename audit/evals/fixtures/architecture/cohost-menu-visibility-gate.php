<?php

namespace App\Livewire;

use App\Models\Event;
use App\Models\EventSession;
use Livewire\Component;

class CohostMenuGate extends Component
{
    public Event $event;

    public EventSession $sessionRow;

    /**
     * Cohost status resolved across every session in the series, not just
     * the row loaded for this request. Gates which admin actions render in
     * the recap toolbar.
     */
    public function canManageRecap(): bool
    {
        return $this->event->effectiveCohostRows()
            ->where('user_id', auth()->id())
            ->exists();
    }

    // BUG: compares against the viewer's own session row instead of the
    // series-wide resolved set canManageRecap() uses above. A cohost added
    // on a different date in the same series has no is_cohost flag on THIS
    // session row, so the badge stays hidden even though canManageRecap()
    // (and the actions it gates) already treats them as a cohost.
    public function showsCohostBadge(): bool
    {
        return $this->sessionRow->is_cohost;
    }

    public function render()
    {
        return view('livewire.cohost-menu-gate');
    }
}
