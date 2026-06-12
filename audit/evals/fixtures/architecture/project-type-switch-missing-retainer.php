<?php

namespace App\Services;

use App\Models\Project;

class ProjectBillingService
{
    public function rateLabel(Project $project): string
    {
        // BUG: Project type enum is hourly|fixed|retainer, but the match
        // omits the 'retainer' branch. A retainer project throws
        // UnhandledMatchError at runtime instead of returning a label.
        return match ($project->type) {
            'hourly' => __('billing.hourly_rate'),
            'fixed' => __('billing.fixed_price'),
        };
    }
}
