<?php

namespace App\Services;

use App\Models\Event;
use Illuminate\Support\Collection;

class ExpenseService
{
    public function getSharedExpenseLines(Event $event): Collection
    {
        // BUG: created_at has only second precision; two expenses created in the
        // same second come back in a different order on every request because
        // Postgres has no stable tiebreaker for equal sort keys. Needs a
        // secondary ->orderByDesc('id') to make the order deterministic.
        return $event->expenses()
            ->orderByDesc('created_at')
            ->get();
    }
}
