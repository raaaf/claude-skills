<?php

namespace App\Services;

use App\Models\Project;

class ProjectBudgetService
{
    /**
     * Build the budget summary line for a project card.
     *
     * Project::$casts includes 'fixed_price' => 'decimal:2', so the attribute
     * is a STRING like "0.00" after casting.
     */
    public function budgetLabel(Project $project): string
    {
        // BUG: decimal casts return strings ("0.00"), and any non-empty string
        // is truthy in PHP — a legitimate fixed price of 0.00 passes this guard
        // and renders a bogus "Budget: 0,00 €" instead of the no-budget label.
        if ($project->fixed_price) {
            return 'Budget: '.number_format((float) $project->fixed_price, 2, ',', '.').' €';
        }

        return 'Kein Budget hinterlegt';
    }
}
