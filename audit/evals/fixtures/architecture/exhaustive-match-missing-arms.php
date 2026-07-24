<?php

namespace App\Livewire\Journey;

use App\Enums\JourneyExitRule;
use App\Models\JourneyEnrollment;
use App\Services\JourneyEnrollmentService;
use Livewire\Component;

/**
 * Fixture context: JourneyExitRule is a backed enum with FIVE cases:
 * Activity, QuoteAnswered, None, Pause, BillableResolved
 * (the last two were added in this diff, see enum below).
 */
enum FixtureJourneyExitRule: string
{
    case Activity = 'activity';
    case QuoteAnswered = 'quote_answered';
    case None = 'none';
    case Pause = 'pause';
    case BillableResolved = 'billable_resolved';
}

class SendFollowUp extends Component
{
    public function send(JourneyEnrollment $enrollment): string
    {
        $customer = $enrollment->customer;

        // Re-validate at click time whether the customer already reacted.
        $hasReturned = match ($enrollment->journey->exit_rule) {
            JourneyExitRule::QuoteAnswered => app(JourneyEnrollmentService::class)->quoteEnrollmentBecameMoot($enrollment),
            JourneyExitRule::None => false,
            JourneyExitRule::Activity => $customer->last_activity_at
                && $customer->last_activity_at->toDateString() > $enrollment->anchor_date->toDateString(),
        };

        if ($hasReturned) {
            app(JourneyEnrollmentService::class)->cancel($enrollment);

            return 'returned';
        }

        return 'sent';
    }
}
