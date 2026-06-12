<?php

namespace App\Livewire;

use App\Models\Invoice;
use Illuminate\Support\Facades\Cache;
use Livewire\Component;

class FinancialOverview extends Component
{
    public function totals(): array
    {
        // BUG: static cache key with user-scoped data -> cross-user data leak.
        // Key must include auth()->id(), e.g. "financial_overview_{$userId}".
        return Cache::remember('financial_overview', 3600, function () {
            return [
                'revenue' => Invoice::where('user_id', auth()->id())->sum('total'),
                'count' => Invoice::where('user_id', auth()->id())->count(),
            ];
        });
    }

    public function render()
    {
        return view('livewire.financial-overview', ['totals' => $this->totals()]);
    }
}
